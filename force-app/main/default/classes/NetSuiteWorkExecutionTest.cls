@IsTest
private class NetSuiteWorkExecutionTest {
  @IsTest
  static void customerSyncCompletesThroughIntegrationWorkProcessor() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    Integration_Work_Item__c item = insertProcessingItem('NetSuite', 'CustomerSync', 'Customer', 'CUSTOMER', 'netsuite:CustomerSync:CUSTOMER', 'token-customer');
    Test.setMock(HttpCalloutMock.class, new CustomerSuiteQLMock());

    Test.startTest();
    new IntegrationWorkProcessor(item.Id, 'token-customer').execute(null);
    Test.stopTest();

    Integration_Work_Item__c refreshed = [SELECT Status__c FROM Integration_Work_Item__c WHERE Id = :item.Id];
    System.assertEquals(IntegrationWorkService.STATUS_COMPLETED, refreshed.Status__c);
    System.assertEquals(1, [SELECT COUNT() FROM Account WHERE External_Id__c = 'netsuite:1001']);
    System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE External_Id__c = 'netsuite:contact:1001']);
  }

  @IsTest
  static void itemSyncCompletesThroughIntegrationWorkProcessor() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    Integration_Work_Item__c item = insertProcessingItem('NetSuite', 'ItemSync', 'Item', 'ITEM', 'netsuite:ItemSync:ITEM', 'token-item');
    Test.setMock(HttpCalloutMock.class, new ItemSuiteQLMock());

    Test.startTest();
    new IntegrationWorkProcessor(item.Id, 'token-item').execute(null);
    Test.stopTest();

    Integration_Work_Item__c refreshed = [SELECT Status__c FROM Integration_Work_Item__c WHERE Id = :item.Id];
    System.assertEquals(IntegrationWorkService.STATUS_COMPLETED, refreshed.Status__c);
    System.assertEquals(1, [SELECT COUNT() FROM Product2 WHERE External_Id__c = 'netsuite:2002']);
  }

  @IsTest
  static void unknownNetSuiteOperationMarksWorkFailed() {
    Integration_Work_Item__c item = insertProcessingItem('NetSuite', 'Unknown', 'ManualRun', 'UNKNOWN', 'netsuite:Unknown:UNKNOWN', 'token-unknown');

    Test.startTest();
    new IntegrationWorkProcessor(item.Id, 'token-unknown').execute(null);
    Test.stopTest();

    Integration_Work_Item__c refreshed = [
      SELECT Status__c, Last_Error__c
      FROM Integration_Work_Item__c
      WHERE Id = :item.Id
    ];
    System.assertEquals(IntegrationWorkService.STATUS_FAILED, refreshed.Status__c);
    System.assert(refreshed.Last_Error__c.contains('Unsupported'));
  }

  @IsTest
  static void salesOrderSyncCompletesThroughIntegrationWorkProcessor() {
    assertPhaseTwoOperationCompletes('SalesOrderSync', 'SalesOrder', 'SO', 'token-so');
  }

  @IsTest
  static void invoiceSyncCompletesThroughIntegrationWorkProcessor() {
    assertPhaseTwoOperationCompletes('InvoiceSync', 'Invoice', 'INV', 'token-inv');
  }

  @IsTest
  static void paymentSyncCompletesThroughIntegrationWorkProcessor() {
    assertPhaseTwoOperationCompletes('PaymentSync', 'Payment', 'PAY', 'token-pay');
  }

  @IsTest
  static void fulfillmentSyncCompletesThroughIntegrationWorkProcessor() {
    assertPhaseTwoOperationCompletes('FulfillmentSync', 'Fulfillment', 'FUL', 'token-ful');
  }

  private static void assertPhaseTwoOperationCompletes(String operation, String sourceObject, String sourceRecordId, String token) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.enableSalesOrderSync = true;
    config.enableInvoiceSync = true;
    config.enablePaymentSync = true;
    config.enableFulfillmentSync = true;
    NetSuiteConfigService.setTestConfig(config);
    Integration_Work_Item__c item = insertProcessingItem(
      'NetSuite',
      operation,
      sourceObject,
      sourceRecordId,
      'netsuite:' + operation + ':' + sourceRecordId,
      token
    );
    Test.setMock(HttpCalloutMock.class, new EmptySuiteQLMock());

    Test.startTest();
    new IntegrationWorkProcessor(item.Id, token).execute(null);
    Test.stopTest();

    Integration_Work_Item__c refreshed = [SELECT Status__c, Last_Error__c FROM Integration_Work_Item__c WHERE Id = :item.Id];
    System.assertEquals(IntegrationWorkService.STATUS_COMPLETED, refreshed.Status__c, 'Phase 2 work item should complete.');
  }

  private static Integration_Work_Item__c insertProcessingItem(
    String integration,
    String operation,
    String sourceObject,
    String sourceRecordId,
    String lockKey,
    String token
  ) {
    Integration_Work_Item__c item = new Integration_Work_Item__c(
      Unique_Key__c = integration + '|' + operation + '|' + sourceObject + '|' + sourceRecordId,
      Status__c = IntegrationWorkService.STATUS_PROCESSING,
      Integration__c = integration,
      Operation__c = operation,
      Source_Object__c = sourceObject,
      Source_Record_Id__c = sourceRecordId,
      Lock_Key__c = lockKey,
      Processor_Token__c = token,
      Payload__c = '{}',
      Attempt_Count__c = 0,
      Max_Attempts__c = 1
    );
    insert item;
    insert new Integration_Work_Lock__c(
      Name = lockKey.left(80),
      Lock_Key__c = lockKey,
      Status__c = 'Locked',
      Work_Item__c = item.Id,
      Processor_Token__c = token,
      Lease_Expires_At__c = System.now().addMinutes(10)
    );
    return item;
  }

  private class CustomerSuiteQLMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"items":[{"id":"1001","entityid":"CUST-1001","companyname":"Acme Industrial","firstname":"Ava","lastname":"Buyer","email":"ava@example.com","phone":"555-0100","billcity":"Detroit","lastmodifieddate":"2026-06-30T12:00:00Z"}],"hasMore":false}');
      return response;
    }
  }

  private class ItemSuiteQLMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"items":[{"id":"2002","itemid":"BW-2002","displayname":"Blue Widget","salesdescription":"Widget from NetSuite","isinactive":"F","lastmodifieddate":"2026-06-30T12:00:00Z"}],"hasMore":false}');
      return response;
    }
  }

  private class EmptySuiteQLMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"items":[],"hasMore":false}');
      return response;
    }
  }
}
