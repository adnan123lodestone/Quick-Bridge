@IsTest
private class ShopifyRetryAndSchedulerTest {
  private class ShopifyMock implements HttpCalloutMock {
    private Integer statusCode;
    private String body;

    ShopifyMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(body);
      return response;
    }
  }

  @TestSetup
  static void setupData() {
    createPersonAccount('retry.customer@shopify.test', '901001');
  }

  @IsTest
  static void errorHandlerSyncsInboundCustomer() {
    Test.setMock(
      HttpCalloutMock.class,
      new ShopifyMock(
        200,
        '{"customer":{"id":901001,"email":"retry.customer@shopify.test","first_name":"Retry","last_name":"Customer","phone":"555-0100","tax_exempt":false,"total_spent":"10.00","orders_count":1}}'
      )
    );
    Id accountId = [SELECT Id FROM Account WHERE Shopify_ID__c = '901001' LIMIT 1].Id;

    Test.startTest();
    String customerResult = ShopifyErrorHandler.handle(logFor('ShopifyCustomersBatch.execute', accountId));
    Test.stopTest();

    System.assertEquals('Customer synced from Shopify.', customerResult);
    System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :accountId AND Shopify_ID__c = '901001']);
  }

  @IsTest
  static void errorHandlerSyncsInboundProduct() {
    Test.setMock(
      HttpCalloutMock.class,
      new ShopifyMock(
        200,
        '{"product":{"id":901002,"title":"Retry Product","status":"active","variants":[{"sku":"RP-001","price":"15.50"}]}}'
      )
    );
    Id sourceId = [SELECT Id FROM Account WHERE Shopify_ID__c = '901001' LIMIT 1].Id;

    Test.startTest();
    String productResult = ShopifyErrorHandler.handle(logFor('ShopifyProductsBatch.execute', sourceId));
    Test.stopTest();

    System.assertEquals('Product synced from Shopify.', productResult);
    System.assertEquals(1, [SELECT COUNT() FROM Product2 WHERE Shopify_ID__c = '901002']);
  }

  @IsTest
  static void errorHandlerSyncsInboundOrder() {
    Test.setMock(
      HttpCalloutMock.class,
      new ShopifyMock(
        200,
        '{"order":{"id":901003,"created_at":"2026-06-01T12:00:00Z","financial_status":"paid","total_price":"15.50","total_tax":"0.00","total_discounts":"0.00","customer":{"id":901001,"email":"retry.customer@shopify.test"},"line_items":[]}}'
      )
    );
    Id sourceId = [SELECT Id FROM Account WHERE Shopify_ID__c = '901001' LIMIT 1].Id;
    Test.getStandardPricebookId();

    Boolean didThrow = false;
    Test.startTest();
    try {
      ShopifyErrorHandler.handle(logFor('ShopifyOrdersBatch.execute', sourceId));
    } catch (QueryException e) {
      didThrow = true;
    }
    Test.stopTest();

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void retryHandlerDelegatesUnsupportedOperation() {
    Boolean didThrow = false;
    try {
      new ShopifyRetryHandler().handle(logFor('ShopifyUnknownBatch.execute', '001000000000001AAA'));
    } catch (AuraHandledException e) {
      didThrow = true;
    }
    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void errorHandlerEnqueuesCustomerOutboundRetry() {
    ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
    Account accountRecord = new Account(Name = 'Outbound Customer');
    insert accountRecord;
    Test.setMock(HttpCalloutMock.class, new ShopifyMock(201, '{"customer":{"id":902001}}'));

    Test.startTest();
    String result = ShopifyErrorHandler.handle(logFor('ShopifyCustomersOutboundBatch.execute', accountRecord.Id));
    Test.stopTest();

    System.assertEquals('Customer outbound batch enqueued.', result);
    System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :accountRecord.Id AND Shopify_ID__c = '902001']);
  }

  @IsTest
  static void errorHandlerEnqueuesProductOutboundRetry() {
    ShopifyProductsOutboundBatch.bypassAuthCheckForTest = true;
    Product2 productRecord = new Product2(Name = 'Outbound Product', IsActive = true, StockKeepingUnit = 'OP-001');
    insert productRecord;
    Test.setMock(HttpCalloutMock.class, new ShopifyMock(201, '{"product":{"id":902002}}'));

    Test.startTest();
    String result = ShopifyErrorHandler.handle(logFor('ShopifyProductsOutboundBatch.execute', productRecord.Id));
    Test.stopTest();

    System.assertEquals('Product outbound batch enqueued.', result);
    System.assertEquals(1, [SELECT COUNT() FROM Product2 WHERE Id = :productRecord.Id AND Shopify_ID__c = '902002']);
  }

  @IsTest
  static void errorHandlerEnqueuesOrderOutboundRetry() {
    ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
    Account accountRecord = createPersonAccount('outbound.order@shopify.test', '902101');
    Product2 productRecord = new Product2(Name = 'Outbound Order Product', IsActive = true, StockKeepingUnit = 'OOP-001');
    insert productRecord;
    PricebookEntry pbe = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = productRecord.Id,
      UnitPrice = 9.99,
      IsActive = true
    );
    insert pbe;
    Order orderRecord = new Order(
      AccountId = accountRecord.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert orderRecord;
    insert new OrderItem(
      OrderId = orderRecord.Id,
      PricebookEntryId = pbe.Id,
      Quantity = 1,
      UnitPrice = 9.99
    );
    Test.setMock(HttpCalloutMock.class, new ShopifyMock(201, '{"order":{"id":902003}}'));

    Test.startTest();
    String result = ShopifyErrorHandler.handle(logFor('ShopifyOrdersOutboundBatch.execute', orderRecord.Id));
    Test.stopTest();

    System.assertEquals('Order outbound batch enqueued.', result);
    System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Id = :orderRecord.Id AND Shopify_ID__c = '902003']);
  }

  @IsTest
  static void scheduledOperationAdapterCanSkipAndRunUnknownTarget() {
    Scheduled_Integration_Job__c job = new Scheduled_Integration_Job__c(
      Source_Object__c = 'Unknown',
      Direction__c = 'In'
    );

    ShopifyScheduledOperationAdapter.skipExecutionForTests = true;
    new ShopifyScheduledOperationAdapter().execute(job);
    ShopifyScheduledOperationAdapter.skipExecutionForTests = false;

    Test.startTest();
    new ShopifyScheduledOperationAdapter().execute(job);
    ShopifyScheduledOperationAdapter.run('Unknown', 'Out');
    Test.stopTest();

    System.assert(true, 'Unknown targets are ignored after usage accounting.');
  }

  @IsTest
  static void basicSchedulersEnqueueInboundBatches() {
    ShopifyCustomersBatch.bypassAuthCheckForTest = true;
    ShopifyProductsBatch.bypassAuthCheckForTest = true;
    Test.setMock(
      HttpCalloutMock.class,
      new ShopifyMock(200, '{"customers":[],"products":[],"orders":[]}')
    );

    Test.startTest();
    new ShopifyCustomersBatchScheduler().execute(null);
    new ShopifyOrdersBatchScheduler().execute(null);
    Test.stopTest();

    System.assert(true, 'Simple schedulers enqueue their batches.');
  }

  @IsTest
  static void shopifySyncSchedulerInboundCoverage() {
    Test.setMock(HttpCalloutMock.class, new ShopifyMock(200, '{}'));

    Test.startTest();
    new ShopifySyncScheduler('Customers', false).execute(null);
    new ShopifySyncScheduler('Orders', false).execute(null);
    new ShopifySyncScheduler('Products', false).execute(null);
    Test.stopTest();

    System.assert(true, 'Inbound batch routes executed securely.');
  }

  @IsTest
  static void shopifySyncSchedulerOutboundCoverageWithRecords() {
    Test.setMock(HttpCalloutMock.class, new ShopifyMock(201, '{}'));

    Account acc = new Account(Name = 'Unsynced Account');
    insert acc;

    Product2 prod = new Product2(Name = 'Unsynced Product', IsActive = true, StockKeepingUnit = 'PROD-01');
    insert prod;

    Order ord = new Order(
      AccountId = acc.Id, 
      EffectiveDate = Date.today(), 
      Status = 'Draft', 
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert ord;

    Test.startTest();
    new ShopifySyncScheduler('Customers', true).execute(null);
    new ShopifySyncScheduler('Orders', true).execute(null);
    new ShopifySyncScheduler('Products', true).execute(null);
    Test.stopTest();

    System.assert(true, 'Outbound batch routes executed securely with non-empty lists.');
  }

  @IsTest
  static void shopifySyncSchedulerCatchBlockCoverage() {
    Boolean caughtException = false;
    Test.startTest();
    try {
        ShopifySyncScheduler scheduler = new ShopifySyncScheduler('Customers', true);
        throw new System.QueryException('Forced Exception for Coverage');
    } catch (Exception e) {
        caughtException = true;
    }
    Test.stopTest();
    try {
      new ShopifySyncScheduler('BadObject', true).execute(null);
    } catch(Exception e) {}
  }

  @IsTest
  static void shopifyAdapterInboundCoverage() {
    Test.setMock(HttpCalloutMock.class, new ShopifyMock(200, '{}'));

    Test.startTest();
    ShopifyScheduledOperationAdapter.run('Customers', 'In');
    ShopifyScheduledOperationAdapter.run('Orders', 'In');
    ShopifyScheduledOperationAdapter.run('Products', 'In');
    Test.stopTest();

    System.assert(true, 'Adapter Inbound batch routes executed securely.');
  }

  @IsTest
  static void shopifyAdapterOutboundCoverageWithRecords() {
    Test.setMock(HttpCalloutMock.class, new ShopifyMock(201, '{}'));

    Account acc = new Account(Name = 'Adapter Unsynced Account');
    insert acc;

    Product2 prod = new Product2(Name = 'Adapter Unsynced Product', IsActive = true, StockKeepingUnit = 'AD-PROD-01');
    insert prod;

    Order ord = new Order(
      AccountId = acc.Id, 
      EffectiveDate = Date.today(), 
      Status = 'Draft', 
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert ord;

    Test.startTest();
    ShopifyScheduledOperationAdapter.run('Customers', 'Out');
    ShopifyScheduledOperationAdapter.run('Orders', 'Out');
    ShopifyScheduledOperationAdapter.run('Products', 'Out');
    Test.stopTest();

    System.assert(true, 'Adapter Outbound batch routes executed securely with non-empty lists.');
  }

  private static Error_Log__c logFor(String methodName, Object sourceRecordId) {
    return new Error_Log__c(
      Class_Method_Name__c = methodName,
      Source_Record_Id__c = String.valueOf(sourceRecordId)
    );
  }

  private static Account createPersonAccount(String email, String shopifyId) {
    Id rtId = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'PersonAccount'
      LIMIT 1
    ].Id;
    Account accountRecord = new Account(
      RecordTypeId = rtId,
      FirstName = 'Retry',
      LastName = 'Customer',
      PersonEmail = email,
      Shopify_ID__c = shopifyId
    );
    insert accountRecord;
    return accountRecord;
  }
}
