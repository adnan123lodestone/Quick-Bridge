@IsTest
private class ShopifyOrderSharedRuntimeTest {
  private class OrderMock implements HttpCalloutMock {
    private Integer statusCode;
    private String body;
    String capturedRequestBody;

    OrderMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
      capturedRequestBody = request.getBody();
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(body);
      return response;
    }
  }

  private class OrderWorkerQueueable implements Queueable, Database.AllowsCallouts {
    private Id orderId;

    OrderWorkerQueueable(Id orderId) {
      this.orderId = orderId;
    }

    public void execute(QueueableContext context) {
      ShopifyIntegrationWorker.process(
        new Integration_Work_Item__c(
          Integration__c = 'Shopify',
          Operation__c = 'OrderUpsert',
          Source_Object__c = 'Order',
          Source_Salesforce_Id__c = orderId,
          Payload__c = '{"isInitialSync":true}'
        )
      );
    }
  }

  @IsTest
  static void outboundOrderWorkerSendsParentAndLinesWithoutChildBatch() {
    ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
    ShopifyOrdersOutboundBatch.testFieldMap = new Map<String, String>();
    ShopifyOrdersOutboundBatch.testLineItemFieldMap = new Map<String, String>{
      'Quantity' => 'quantity',
      'UnitPrice' => 'price'
    };
    OrderMock mockValue = new OrderMock(201, '{"order":{"id":"800001"}}');
    Test.setMock(HttpCalloutMock.class, mockValue);
    Order orderRecord = createOrderWithLine();

    Test.startTest();
    Id workerJobId = System.enqueueJob(
      new OrderWorkerQueueable(orderRecord.Id)
    );
    Test.stopTest();

    Order synchronizedOrder = [
      SELECT Shopify_ID__c
      FROM Order
      WHERE Id = :orderRecord.Id
    ];
    System.assertEquals('800001', synchronizedOrder.Shopify_ID__c);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE
          ParentJobId = :workerJobId
          AND ApexClass.Name IN (
            'ShopifyOrdersOutboundBatch',
            'ConnectorOutboundBatch'
          )
      ]
    );
    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      mockValue.capturedRequestBody
    );
    Map<String, Object> orderNode = (Map<String, Object>) payload.get('order');
    List<Object> lines = (List<Object>) orderNode.get('line_items');
    System.assertEquals(1, lines.size());
    Map<String, Object> firstLine = (Map<String, Object>) lines[0];
    System.assertEquals(2, firstLine.get('quantity'));
    System.assertEquals('ORDER-SKU', firstLine.get('sku'));
    ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = false;
    ShopifyOrdersOutboundBatch.testFieldMap = null;
    ShopifyOrdersOutboundBatch.testLineItemFieldMap = null;
  }

  @IsTest
  static void inboundSharedBatchCreatesOrderAndLineRelationship() {
    ShopifyOrdersBatch.bypassAuthCheckForTest = true;
    insert new Integration_Entitlement__c(
      Name = 'Shared Order Entitlement',
      Cache_Key__c = 'checkout',
      Product_Key__c = 'checkout',
      Status__c = 'Active',
      Raw_Response__c = '{"status":"Success","activeGateways":["Shopify"]}',
      Active_Gateways_JSON__c = '["Shopify"]',
      Last_Refreshed_At__c = System.now(),
      Expires_At__c = System.now().addDays(1),
      TTL_Minutes__c = 1440,
      Refresh_Status__c = 'Success',
      Fail_Policy__c = 'Fail Open'
    );
    Id personAccountRecordTypeId = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND Name = 'Person Account'
      LIMIT 1
    ]
    .Id;
    insert new Account(
      RecordTypeId = personAccountRecordTypeId,
      FirstName = 'Jane',
      LastName = 'Doe',
      PersonEmail = 'jane.doe@shopify.test',
      Shopify_ID__c = '777001'
    );
    Product2 productRecord = new Product2(
      Name = 'Inbound Shopify Product',
      IsActive = true,
      Shopify_ID__c = '99001'
    );
    insert productRecord;
    update new Pricebook2(Id = Test.getStandardPricebookId(), IsActive = true);
    insert new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = productRecord.Id,
      UnitPrice = 49.99,
      IsActive = true
    );
    String responseBody =
      '{"orders":[{' +
      '"id":500001,"created_at":"2024-01-15T10:30:00Z",' +
      '"financial_status":"paid","total_price":99.99,' +
      '"buyer_accepts_marketing":false,"estimated_taxes":false,' +
      '"tax_exempt":false,"taxes_included":false,' +
      '"customer":{"id":777001,"email":"jane.doe@shopify.test",' +
      '"first_name":"Jane","last_name":"Doe"},' +
      '"line_items":[{"id":111,"product_id":99001,' +
      '"sku":"ORDER-SKU","quantity":2,"price":49.99}]' +
      '}]}';
    Test.setMock(HttpCalloutMock.class, new OrderMock(200, responseBody));
    ConnectorExecutionRequest request = orderRequest('Inbound');

    Test.startTest();
    Id inboundJobId = Database.executeBatch(
      new ConnectorInboundBatch(request),
      1
    );
    Test.stopTest();

    List<Order> synchronizedOrders = [
      SELECT Id, Shopify_ID__c
      FROM Order
      WHERE Shopify_ID__c = '500001'
      LIMIT 1
    ];
    AsyncApexJob inboundJob = [
      SELECT Status, NumberOfErrors, ExtendedStatus
      FROM AsyncApexJob
      WHERE Id = :inboundJobId
    ];
    List<Error_Log__c> errorLogs = [
      SELECT Class_Method_Name__c, Error_Message__c
      FROM Error_Log__c
      WHERE
        Gateway_Name__c = 'Shopify'
        AND Class_Method_Name__c != 'ShopifyOrdersBatch.mapOrderFields'
    ];
    System.assertEquals(
      1,
      synchronizedOrders.size(),
      JSON.serialize(inboundJob) + ' | ' + JSON.serialize(errorLogs)
    );
    Order synchronizedOrder = synchronizedOrders[0];
    OrderItem synchronizedLine = [
      SELECT OrderId, Shopify_ID__c, Quantity, UnitPrice
      FROM OrderItem
      WHERE Shopify_ID__c = '111'
      LIMIT 1
    ];
    System.assertEquals(synchronizedOrder.Id, synchronizedLine.OrderId);
    System.assertEquals(2, synchronizedLine.Quantity);
    System.assertEquals(49.99, synchronizedLine.UnitPrice);
    ShopifyOrdersBatch.bypassAuthCheckForTest = false;
  }

  @IsTest
  static void registryRoutesOrderAliasesToSharedExecutors() {
    ConnectorOperationRegistry.OperationDefinition inbound = ConnectorOperationRegistry.resolve(
      orderRequest('Inbound')
    );
    ConnectorOperationRegistry.OperationDefinition outbound = ConnectorOperationRegistry.resolve(
      orderRequest('Outbound')
    );
    System.assertEquals(
      'ConnectorInboundOperationExecutor',
      inbound.executorClassName
    );
    System.assertEquals(
      'ConnectorOutboundOperationExecutor',
      outbound.executorClassName
    );
    System.assertEquals(
      'https://mock-shopify.com/admin/api/2024-04/orders.json',
      inbound.approvedBaseUrl
    );
  }

  private static Order createOrderWithLine() {
    Account accountRecord = new Account(
      Name = 'Shared Order Account',
      Shopify_ID__c = '710001'
    );
    insert accountRecord;
    Product2 productRecord = new Product2(
      Name = 'Shared Order Product',
      StockKeepingUnit = 'ORDER-SKU',
      IsActive = true
    );
    insert productRecord;
    PricebookEntry pricebookEntry = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = productRecord.Id,
      UnitPrice = 25,
      IsActive = true
    );
    insert pricebookEntry;
    Order orderRecord = new Order(
      AccountId = accountRecord.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert orderRecord;
    insert new OrderItem(
      OrderId = orderRecord.Id,
      PricebookEntryId = pricebookEntry.Id,
      Quantity = 2,
      UnitPrice = 25
    );
    return orderRecord;
  }

  private static ConnectorExecutionRequest orderRequest(String direction) {
    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = 'Shopify';
    request.operationKey = 'Orders';
    request.direction = direction;
    request.salesforceObject = 'Order';
    request.externalEntity = 'Order';
    request.initialSync = direction == 'Outbound';
    request.scopeSize = direction == 'Outbound' ? 10 : 1;
    return request;
  }
}
