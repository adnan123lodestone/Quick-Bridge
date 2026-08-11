@IsTest
private class ShopifySharedOutboundAccountingTest {
  private class MissingExternalIdMock implements HttpCalloutMock {
    private String responseBody;

    MissingExternalIdMock(String responseBody) {
      this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(201);
      response.setBody(responseBody);
      return response;
    }
  }

  private class AccountingQueueable implements Queueable, Database.AllowsCallouts {
    private String entityName;
    private Id recordId;

    AccountingQueueable(String entityName, Id recordId) {
      this.entityName = entityName;
      this.recordId = recordId;
    }

    public void execute(QueueableContext context) {
      ConnectorExecutionResult result;
      if (entityName == 'customer') {
        ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
        ShopifyCustomersOutboundBatch.testFieldMap = new Map<String, String>{
          'Name' => 'last_name'
        };
        result = ShopifyCustomersOutboundBatch.executeSharedScope(
          requestFor('Customer', 'Account'),
          new List<SObject>{ new Account(Id = recordId) }
        );
        update new Account(Id = recordId, Description = JSON.serialize(result));
      } else if (entityName == 'product') {
        ShopifyProductsOutboundBatch.bypassAuthCheckForTest = true;
        ShopifyProductsOutboundBatch.testFieldMap = new Map<String, String>();
        result = ShopifyProductsOutboundBatch.executeSharedScope(
          requestFor('Product', 'Product2'),
          new List<SObject>{ new Product2(Id = recordId) }
        );
        update new Product2(
          Id = recordId,
          Description = JSON.serialize(result)
        );
      } else {
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        ShopifyOrdersOutboundBatch.testFieldMap = new Map<String, String>();
        ShopifyOrdersOutboundBatch.testLineItemFieldMap = new Map<String, String>{
          'Quantity' => 'quantity',
          'UnitPrice' => 'price'
        };
        result = ShopifyOrdersOutboundBatch.executeSharedScope(
          requestFor('Order', 'Order'),
          new List<SObject>{ new Order(Id = recordId) }
        );
        update new Order(Id = recordId, Description = JSON.serialize(result));
      }
    }
  }

  @TestSetup
  static void createFixtures() {
    insert new Account(Name = 'Customer Missing Shopify ID');
    insert new Product2(Name = 'Product Missing Shopify ID', IsActive = true);

    Account orderAccount = new Account(
      Name = 'Order Missing Shopify ID Account',
      Shopify_ID__c = '710001'
    );
    insert orderAccount;
    Product2 orderProduct = new Product2(
      Name = 'Order Missing Shopify ID Product',
      StockKeepingUnit = 'MISSING-ID-SKU',
      IsActive = true
    );
    insert orderProduct;
    PricebookEntry pricebookEntry = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = orderProduct.Id,
      UnitPrice = 25,
      IsActive = true
    );
    insert pricebookEntry;
    Order orderRecord = new Order(
      AccountId = orderAccount.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId(),
      Description = 'Missing external ID fixture'
    );
    insert orderRecord;
    insert new OrderItem(
      OrderId = orderRecord.Id,
      PricebookEntryId = pricebookEntry.Id,
      Quantity = 2,
      UnitPrice = 25
    );
  }

  @IsTest
  static void customerMissingExternalIdIsPermanentFailure() {
    Test.setMock(
      HttpCalloutMock.class,
      new MissingExternalIdMock('{"customer":{}}')
    );
    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name = 'Customer Missing Shopify ID'
      LIMIT 1
    ];

    Test.startTest();
    System.enqueueJob(new AccountingQueueable('customer', accountRecord.Id));
    Test.stopTest();
    ConnectorExecutionResult result = (ConnectorExecutionResult) JSON.deserialize(
      [SELECT Description FROM Account WHERE Id = :accountRecord.Id]
      .Description,
      ConnectorExecutionResult.class
    );

    assertPermanentFailure(result, 'customer');
  }

  @IsTest
  static void productMissingExternalIdIsPermanentFailure() {
    Test.setMock(
      HttpCalloutMock.class,
      new MissingExternalIdMock('{"product":{}}')
    );
    Product2 productRecord = [
      SELECT Id
      FROM Product2
      WHERE Name = 'Product Missing Shopify ID'
      LIMIT 1
    ];

    Test.startTest();
    System.enqueueJob(new AccountingQueueable('product', productRecord.Id));
    Test.stopTest();
    ConnectorExecutionResult result = (ConnectorExecutionResult) JSON.deserialize(
      [SELECT Description FROM Product2 WHERE Id = :productRecord.Id]
      .Description,
      ConnectorExecutionResult.class
    );

    assertPermanentFailure(result, 'product');
  }

  @IsTest
  static void orderMissingExternalIdIsPermanentFailure() {
    Test.setMock(
      HttpCalloutMock.class,
      new MissingExternalIdMock('{"order":{}}')
    );
    Order orderRecord = [
      SELECT Id
      FROM Order
      WHERE Account.Name = 'Order Missing Shopify ID Account'
      LIMIT 1
    ];

    Test.startTest();
    System.enqueueJob(new AccountingQueueable('order', orderRecord.Id));
    Test.stopTest();
    ConnectorExecutionResult result = (ConnectorExecutionResult) JSON.deserialize(
      [SELECT Description FROM Order WHERE Id = :orderRecord.Id].Description,
      ConnectorExecutionResult.class
    );

    assertPermanentFailure(result, 'order');
  }

  private static ConnectorExecutionRequest requestFor(
    String entityName,
    String salesforceObject
  ) {
    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = 'Shopify';
    request.operationKey = entityName;
    request.direction = 'Outbound';
    request.salesforceObject = salesforceObject;
    request.externalEntity = entityName;
    request.initialSync = true;
    request.scopeSize = 10;
    return request;
  }

  private static void assertPermanentFailure(
    ConnectorExecutionResult result,
    String entityName
  ) {
    System.assertEquals(1, result.processedCount);
    System.assertEquals(0, result.successfulCount);
    System.assertEquals(1, result.failedCount);
    System.assertEquals(false, result.retryable);
    System.assertEquals(0, result.retryRecordIds.size());
    System.assert(
      result.errorSummary.contains(entityName) &&
      result.errorSummary.contains('external ID'),
      result.errorSummary
    );
  }
}
