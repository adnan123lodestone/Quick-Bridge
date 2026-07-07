@IsTest
private class NetSuiteTransactionServiceTest {
  private static List<String> mockPaths = new List<String>();
  private static String mockLastMethod;

  @IsTest
  static void customerOutboundCreatesCustomerAndStoresExternalId() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.syncDirection = 'Bidirectional';
    config.enableCustomerSync = true;
    NetSuiteConfigService.setTestConfig(config);
    Test.setMock(HttpCalloutMock.class, new NetSuiteWriteMock('{"id":"9001"}'));

    Account accountRecord = new Account(Name = 'Outbound Customer', Phone = '555-0101');
    insert accountRecord;

    Test.startTest();
    NetSuiteCustomerService.exportCustomers(new Set<Id>{ accountRecord.Id });
    Test.stopTest();

    Account updatedAccount = [
      SELECT External_Id__c
      FROM Account
      WHERE Id = :accountRecord.Id
      LIMIT 1
    ];
    System.assertEquals('netsuite:9001', updatedAccount.External_Id__c);
    System.assertEquals('/services/rest/record/v1/customer', lastMockPath());
    System.assertEquals('POST', mockLastMethod);
  }

  @IsTest
  static void itemOutboundCreatesItemAndStoresExternalId() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.syncDirection = 'Bidirectional';
    config.enableItemSync = true;
    config.defaultItemRecordType = 'inventoryItem';
    NetSuiteConfigService.setTestConfig(config);
    Test.setMock(HttpCalloutMock.class, new NetSuiteWriteMock('{"id":"8002"}'));

    Product2 productRecord = new Product2(Name = 'Outbound Item', ProductCode = 'OUT-8002', IsActive = true);
    insert productRecord;

    Test.startTest();
    NetSuiteItemService.exportItems(new Set<Id>{ productRecord.Id });
    Test.stopTest();

    Product2 updatedProduct = [
      SELECT External_Id__c
      FROM Product2
      WHERE Id = :productRecord.Id
      LIMIT 1
    ];
    System.assertEquals('netsuite:8002', updatedProduct.External_Id__c);
    System.assertEquals('/services/rest/record/v1/inventoryItem', lastMockPath());
  }

  @IsTest
  static void salesOrderOutboundCreatesAndStoresExternalId() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.syncDirection = 'Bidirectional';
    config.enableSalesOrderSync = true;
    config.defaultSubsidiary = '2';
    config.defaultDepartment = '3';
    config.defaultClass = '4';
    config.defaultLocation = '5';
    NetSuiteConfigService.setTestConfig(config);

    Account accountRecord = new Account(Name = 'Sales Order Account', External_Id__c = 'netsuite:1201');
    insert accountRecord;
    Order orderRecord = new Order(
      AccountId = accountRecord.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId(),
      OrderReferenceNumber = 'SO-LOCAL-1'
    );
    insert orderRecord;

    Test.setMock(HttpCalloutMock.class, new NetSuiteWriteMock('{"id":"4301"}'));

    Test.startTest();
    NetSuiteSalesOrderService.SyncSummary summary =
      NetSuiteSalesOrderService.exportOrders(new Set<Id>{ orderRecord.Id });
    Test.stopTest();

    System.assertEquals(1, summary.recordsProcessed);
    System.assertEquals(0, summary.recordsFailed);
    Order updatedOrder = [SELECT External_Id__c FROM Order WHERE Id = :orderRecord.Id];
    System.assertEquals('netsuite:4301', updatedOrder.External_Id__c);
    System.assertEquals('/services/rest/record/v1/salesOrder', lastMockPath());
  }

  @IsTest
  static void inboundSalesOrderRowsAreCountedWithPartialFailure() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.enableSalesOrderSync = true;
    NetSuiteConfigService.setTestConfig(config);
    Test.setMock(HttpCalloutMock.class, new SuiteQLRowsMock(
      '{"items":[{"id":"4302","tranid":"SO-4302","trandate":"2026-07-01","status":"Draft"}],"hasMore":false}'
    ));

    Test.startTest();
    NetSuiteSalesOrderService.SyncSummary summary =
      NetSuiteSalesOrderService.syncSalesOrders(null, 10);
    Test.stopTest();

    System.assertEquals(0, summary.recordsProcessed);
    System.assertEquals(1, summary.recordsFailed);
    System.assert(summary.message.contains('processed'));
  }

  @IsTest
  static void transactionServicesUseExpectedNetSuiteRecordPaths() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.syncDirection = 'Bidirectional';
    config.enableSalesOrderSync = true;
    config.enableInvoiceSync = true;
    config.enablePaymentSync = true;
    config.enableFulfillmentSync = true;
    NetSuiteConfigService.setTestConfig(config);

    Account accountRecord = new Account(Name = 'Transaction Account', External_Id__c = 'netsuite:1001');
    insert accountRecord;
    Order orderRecord = new Order(
      AccountId = accountRecord.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId(),
      External_Id__c = 'netsuite:4001'
    );
    insert orderRecord;
    Invoice__c invoiceRecord = new Invoice__c(
      Related_Account__c = accountRecord.Id,
      Amount__c = 50,
      External_Id__c = 'netsuite:5001'
    );
    insert invoiceRecord;
    Portal_Payment_Transaction__c paymentRecord = new Portal_Payment_Transaction__c(
      Payment_Type__c = 'Unknown',
      Gateway_Amount__c = 50,
      Gateway_Reference_Number__c = 'PAY-50'
    );
    insert paymentRecord;
    Order unexportedOrder = new Order(
      AccountId = accountRecord.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert unexportedOrder;
    Carrier_Shipment__c shipmentRecord = new Carrier_Shipment__c(
      Source_Object__c = 'Order',
      Source_Record_Id__c = String.valueOf(unexportedOrder.Id),
      Integration_Type__c = 'netsuite'
    );
    insert shipmentRecord;

    NetSuiteWriteMock mock = new NetSuiteWriteMock('{"id":"7001"}');
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    NetSuiteSalesOrderService.exportOrders(new Set<Id>{ orderRecord.Id });
    NetSuiteInvoiceService.exportInvoices(new Set<Id>{ invoiceRecord.Id });
    NetSuitePaymentService.exportPayments(new Set<Id>{ paymentRecord.Id });
    try {
      NetSuiteFulfillmentService.exportFulfillments(new Set<Id>{ shipmentRecord.Id });
      System.assert(false, 'Fulfillment without a NetSuite sales order reference should be blocked.');
    } catch (NetSuiteFulfillmentService.NetSuiteFulfillmentException expected) {
      System.assert(expected.getMessage().contains('NetSuite sales order'));
    }
    Test.stopTest();

    System.assert(hasMockPathStartingWith('/services/rest/record/v1/salesOrder'));
    System.assert(hasMockPathStartingWith('/services/rest/record/v1/invoice'));
    System.assert(mockPaths.contains('/services/rest/record/v1/customerPayment'));
  }

  @IsTest
  static void workerDispatchesPhaseTwoOperations() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.enableSalesOrderSync = true;
    config.enableInvoiceSync = true;
    config.enablePaymentSync = true;
    config.enableFulfillmentSync = true;
    NetSuiteConfigService.setTestConfig(config);
    Test.setMock(HttpCalloutMock.class, new EmptySuiteQLMock());

    Test.startTest();
    new NetSuiteIntegrationWorker().handle(new Integration_Work_Item__c(Operation__c = 'SalesOrderSync'));
    new NetSuiteIntegrationWorker().handle(new Integration_Work_Item__c(Operation__c = 'InvoiceSync'));
    new NetSuiteIntegrationWorker().handle(new Integration_Work_Item__c(Operation__c = 'PaymentSync'));
    new NetSuiteIntegrationWorker().handle(new Integration_Work_Item__c(Operation__c = 'FulfillmentSync'));
    Test.stopTest();

    System.assert(true, 'Phase 2 operations route without unsupported-operation errors.');
  }

  @IsTest
  static void disabledServicesReturnEarlyWithoutCallouts() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.enableSalesOrderSync = false;
    config.enableInvoiceSync = false;
    config.enablePaymentSync = false;
    config.enableFulfillmentSync = false;
    NetSuiteConfigService.setTestConfig(config);

    System.assert(NetSuiteSalesOrderService.syncSalesOrders(null, null).message.contains('disabled'));
    System.assert(NetSuiteInvoiceService.syncInvoices(null, null).message.contains('disabled'));
    System.assert(NetSuitePaymentService.syncPayments(null, null).message.contains('disabled'));
    System.assert(NetSuiteFulfillmentService.syncFulfillments(null, null).message.contains('disabled'));
    System.assert(NetSuiteSalesOrderService.exportOrders(new Set<Id>()).message.contains('skipped'));
    System.assert(NetSuiteInvoiceService.exportInvoices(new Set<Id>()).message.contains('skipped'));
    System.assert(NetSuitePaymentService.exportPayments(new Set<Id>()).message.contains('skipped'));
    System.assert(NetSuiteFulfillmentService.exportFulfillments(new Set<Id>()).message.contains('skipped'));
  }

  @IsTest
  static void inboundInvoiceRowsUseRecordMapper() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.enableInvoiceSync = true;
    NetSuiteConfigService.setTestConfig(config);
    Test.setMock(HttpCalloutMock.class, new SuiteQLRowsMock(
      '{"items":[{"id":"8801","tranid":"INV-8801","total":88.01,"status":"Open"}],"hasMore":false}'
    ));

    Test.startTest();
    NetSuiteInvoiceService.SyncSummary summary = NetSuiteInvoiceService.syncInvoices(Datetime.now().addDays(-1), 5);
    Test.stopTest();

    System.assertEquals(1, summary.recordsProcessed);
    Invoice__c invoiceRecord = [
      SELECT External_Id__c, Reference_number__c, Amount__c, Status__c
      FROM Invoice__c
      WHERE External_Id__c = 'netsuite:8801'
      LIMIT 1
    ];
    System.assertEquals('INV-8801', invoiceRecord.Reference_number__c);
  }

  @IsTest
  static void inboundPaymentRowsCreatePortalTransactions() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.enablePaymentSync = true;
    NetSuiteConfigService.setTestConfig(config);
    Test.setMock(HttpCalloutMock.class, new SuiteQLRowsMock(
      '{"items":[{"id":"7701","tranid":"PAY-7701","payment":77.01}],"hasMore":false}'
    ));

    Test.startTest();
    NetSuitePaymentService.SyncSummary summary = NetSuitePaymentService.syncPayments(null, 10);
    Test.stopTest();

    System.assertEquals(1, summary.recordsProcessed);
    System.assertEquals(
      1,
      [SELECT count() FROM Portal_Payment_Transaction__c WHERE Gateway_Event_Id__c = 'netsuite:7701']
    );
  }

  @IsTest
  static void inboundFulfillmentRowsInsertAndUpdateShipments() {
    Carrier_Shipment__c existingShipment = new Carrier_Shipment__c(
      External_Shipment_Id__c = 'netsuite:6601',
      Integration_Type__c = 'netsuite',
      Shipment_Status__c = 'Pending'
    );
    insert existingShipment;

    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.enableFulfillmentSync = true;
    NetSuiteConfigService.setTestConfig(config);
    Test.setMock(HttpCalloutMock.class, new SuiteQLRowsMock(
      '{"items":[' +
      '{"id":"6601","trackingnumbers":"1Z6601","status":"Shipped"},' +
      '{"id":"6602","trackingnumbers":"1Z6602","status":"Packed"}' +
      '],"hasMore":false}'
    ));

    Test.startTest();
    NetSuiteFulfillmentService.SyncSummary summary = NetSuiteFulfillmentService.syncFulfillments(null, 10);
    Test.stopTest();

    System.assertEquals(2, summary.recordsProcessed);
    System.assertEquals(
      2,
      [SELECT count() FROM Carrier_Shipment__c WHERE Integration_Type__c = 'netsuite']
    );
  }

  @IsTest
  static void fulfillmentExportWritesWhenOrderHasNetSuiteId() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.enableFulfillmentSync = true;
    config.defaultFulfillmentLocation = '10';
    NetSuiteConfigService.setTestConfig(config);

    Account accountRecord = new Account(Name = 'Fulfillment Account');
    insert accountRecord;
    Order orderRecord = new Order(
      AccountId = accountRecord.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId(),
      External_Id__c = 'netsuite:SO500'
    );
    insert orderRecord;
    Carrier_Shipment__c shipmentRecord = new Carrier_Shipment__c(
      Source_Object__c = 'Order',
      Source_Record_Id__c = String.valueOf(orderRecord.Id),
      Integration_Type__c = 'netsuite',
      Master_Tracking_Number__c = 'TRACK-500'
    );
    insert shipmentRecord;

    Test.setMock(HttpCalloutMock.class, new NetSuiteWriteMock('{"internalId":"9901"}'));

    Test.startTest();
    NetSuiteFulfillmentService.SyncSummary summary =
      NetSuiteFulfillmentService.exportFulfillments(new Set<Id>{ shipmentRecord.Id });
    Test.stopTest();

    System.assertEquals(1, summary.recordsProcessed);
    System.assert(mockPaths.contains('/services/rest/record/v1/itemFulfillment'));
  }

  @IsTest
  static void contactExportCreatesCustomerPayload() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.enableCustomerSync = true;
    NetSuiteConfigService.setTestConfig(config);

    Account accountRecord = new Account(Name = 'Contact Parent');
    insert accountRecord;
    Contact contactRecord = new Contact(
      AccountId = accountRecord.Id,
      FirstName = 'Nora',
      LastName = 'NetSuite',
      Email = 'nora@example.com'
    );
    insert contactRecord;

    Test.setMock(HttpCalloutMock.class, new NetSuiteWriteMock('{"id":"4401"}'));

    Test.startTest();
    NetSuiteCustomerService.SyncSummary summary =
      NetSuiteCustomerService.exportContacts(new Set<Id>{ contactRecord.Id });
    Test.stopTest();

    System.assertEquals(1, summary.recordsProcessed);
    Contact updatedContact = [SELECT External_Id__c FROM Contact WHERE Id = :contactRecord.Id];
    System.assertEquals('netsuite:contact:4401', updatedContact.External_Id__c);
  }

  @IsTest
  static void transactionUtilityCoversReferencesPatchAndErrors() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    NetSuiteWriteMock mock = new NetSuiteWriteMock('{"internalId":"321"}');
    Test.setMock(HttpCalloutMock.class, mock);

    Map<String, Object> payload = new Map<String, Object>();
    NetSuiteTransactionUtil.putReference(payload, 'entity', '123');
    System.assertEquals('123', ((Map<String, Object>) payload.get('entity')).get('id'));

    Test.startTest();
    String internalId = NetSuiteTransactionUtil.writeRecord('customer', 'netsuite:123', payload);
    Test.stopTest();

    System.assertEquals('321', internalId);
    System.assertEquals('PATCH', mockLastMethod);
    System.assert(lastMockPath().startsWith('/services/rest/record/v1/customer/123'));

    try {
      NetSuiteTransactionUtil.writeRecord(null, null, payload);
      System.assert(false, 'Blank NetSuite record type should fail.');
    } catch (NetSuiteTransactionUtil.NetSuiteTransactionException expected) {
      System.assert(expected.getMessage().contains('record type'));
    }
  }

  private class NetSuiteWriteMock implements HttpCalloutMock {
    private String body;

    NetSuiteWriteMock(String body) {
      this.body = body;
      mockPaths.clear();
      mockLastMethod = null;
    }

    public HttpResponse respond(HttpRequest request) {
      mockLastMethod = request.getMethod();
      mockPaths.add(extractPath(request.getEndpoint()));
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody(body);
      return response;
    }

  }

  private static String lastMockPath() {
    return mockPaths.isEmpty() ? null : mockPaths[mockPaths.size() - 1];
  }

  private static Boolean hasMockPathStartingWith(String expectedPrefix) {
    for (String path : mockPaths) {
      if (path != null && path.startsWith(expectedPrefix)) {
        return true;
      }
    }
    return false;
  }

  private static String extractPath(String endpoint) {
    Integer marker = endpoint == null ? -1 : endpoint.indexOf('/services/');
    return marker >= 0 ? endpoint.substring(marker) : endpoint;
  }

  private class EmptySuiteQLMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"items":[],"hasMore":false}');
      return response;
    }
  }

  private class SuiteQLRowsMock implements HttpCalloutMock {
    private String body;

    SuiteQLRowsMock(String body) {
      this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody(body);
      return response;
    }
  }
}