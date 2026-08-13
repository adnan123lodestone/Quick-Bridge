@IsTest
private class QuickBooksSharedRuntimeTest {
  private static List<String> requestBodies = new List<String>();

  private class QuickBooksSharedMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      String endpoint = request.getEndpoint() == null
        ? ''
        : request.getEndpoint().toLowerCase();
      requestBodies.add(request.getBody());
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setHeader('Content-Type', 'application/json');
      if (endpoint.contains('/query?query=')) {
        if (endpoint.contains('from+customer')) {
          response.setBody(
            '{"QueryResponse":{"Customer":[{"Id":"C-SHARED","DisplayName":"Shared Customer","CompanyName":"Shared Company"}]}}'
          );
        } else if (endpoint.contains('from+vendor')) {
          response.setBody(
            '{"QueryResponse":{"Vendor":[{"Id":"V-SHARED","DisplayName":"Shared Vendor","CompanyName":"Shared Vendor Company"}]}}'
          );
        } else {
          response.setBody(
            '{"QueryResponse":{"Item":[{"Id":"I-SHARED","Name":"Shared Item","Active":true,"Type":"NonInventory","IncomeAccountRef":{"value":"79"}}]}}'
          );
        }
      } else if (endpoint.contains('/customer')) {
        response.setBody('{"Customer":{"Id":"C-OUT"}}');
      } else if (endpoint.contains('/item')) {
        response.setBody('{"Item":{"Id":"I-OUT"}}');
      } else if (endpoint.contains('/invoice')) {
        response.setBody(
          '{"Invoice":{"Id":"INV-ORDER","SyncToken":"2","Line":[{"Id":"LINE-1","DetailType":"SalesItemLineDetail","SalesItemLineDetail":{}}]}}'
        );
      } else if (endpoint.contains('/estimate')) {
        response.setBody(
          '{"Estimate":{"Id":"EST-ORDER","SyncToken":"2","Line":[{"Id":"LINE-1","DetailType":"SalesItemLineDetail","SalesItemLineDetail":{}}]}}'
        );
      } else if (endpoint.contains('/purchaseorder')) {
        response.setBody(
          '{"PurchaseOrder":{"Id":"PO-SHARED","SyncToken":"2","Line":[{"Id":"PO-LINE-1","DetailType":"ItemBasedExpenseLineDetail"}]}}'
        );
      } else {
        response.setBody('{}');
      }
      return response;
    }
  }

  private class RateLimitedQuickBooksMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(429);
      response.setBody('{"Fault":{"Error":[{"Message":"Rate limited"}]}}');
      return response;
    }
  }

  private class MixedAccountOutboundMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      String endpoint = request.getEndpoint().toLowerCase();
      if (endpoint.contains('/customer/c-fail')) {
        response.setStatusCode(503);
        response.setBody('{"Fault":{"Error":[{"Message":"Unavailable"}]}}');
      } else if (request.getMethod() == 'GET') {
        response.setStatusCode(200);
        response.setBody(
          '{"Customer":{"Id":"C-OK","SyncToken":"1","DisplayName":"Mixed Success"}}'
        );
      } else {
        response.setStatusCode(200);
        response.setBody('{"Customer":{"Id":"C-OK","SyncToken":"2"}}');
      }
      return response;
    }
  }

  private class FailedOrderOutboundMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(503);
      response.setBody('{"Fault":{"Error":[{"Message":"Unavailable"}]}}');
      return response;
    }
  }

  @TestSetup
  static void setupRecords() {
    QBTriggerHandler.isAccountProcessing = true;
    QBTriggerHandler.isProductProcessing = true;
    try {
      insert new Account(
        Name = 'Hydrated Shared Account',
        BillingCity = 'Chicago'
      );
      insert new Product2(
        Name = 'Hydrated Shared Product',
        IsActive = true,
        Sale_Price__c = 25
      );
    } finally {
      QBTriggerHandler.isAccountProcessing = false;
      QBTriggerHandler.isProductProcessing = false;
    }
  }

  @IsTest
  static void registryPrefersExecutorBearingQboDefinitions() {
    ConnectorOperationRegistry.OperationDefinition customerInbound = ConnectorOperationRegistry.resolve(
      requestFor('Customer', 'Inbound', 'Account', 'Customer')
    );
    ConnectorOperationRegistry.OperationDefinition customerOutbound = ConnectorOperationRegistry.resolve(
      requestFor('Customer', 'Outbound', 'Account', 'Customer')
    );
    ConnectorOperationRegistry.OperationDefinition itemInbound = ConnectorOperationRegistry.resolve(
      requestFor('Item', 'Inbound', 'Product2', 'Item')
    );
    ConnectorOperationRegistry.OperationDefinition itemOutbound = ConnectorOperationRegistry.resolve(
      requestFor('Item', 'Outbound', 'Product2', 'Item')
    );
    ConnectorOperationRegistry.OperationDefinition pluralCustomer = ConnectorOperationRegistry.resolve(
      requestFor('Customers', 'Outbound', 'Account', 'Customers')
    );
    ConnectorOperationRegistry.OperationDefinition pluralItem = ConnectorOperationRegistry.resolve(
      requestFor('Items', 'Inbound', 'Product2', 'Items')
    );
    ConnectorOperationRegistry.OperationDefinition pluralVendor = ConnectorOperationRegistry.resolve(
      requestFor('Vendors', 'Outbound', 'Account', 'Vendors')
    );
    ConnectorOperationRegistry.OperationDefinition orderOutbound = ConnectorOperationRegistry.resolve(
      requestFor('Orders', 'Outbound', 'Order', 'Invoice')
    );
    ConnectorOperationRegistry.OperationDefinition purchaseOrderOutbound = ConnectorOperationRegistry.resolve(
      requestFor(
        'Purchase Orders',
        'Outbound',
        'Purchase_Order__c',
        'Purchase Orders'
      )
    );
    ConnectorOperationRegistry.OperationDefinition quoteOutbound = ConnectorOperationRegistry.resolve(
      requestFor('Quotes', 'Outbound', 'Quote', 'Estimates')
    );

    System.assertEquals(
      'ConnectorInboundOperationExecutor',
      customerInbound.executorClassName
    );
    System.assertEquals(
      'ConnectorOutboundOperationExecutor',
      customerOutbound.executorClassName
    );
    System.assertEquals(
      'ConnectorInboundOperationExecutor',
      itemInbound.executorClassName
    );
    System.assertEquals(
      'ConnectorOutboundOperationExecutor',
      itemOutbound.executorClassName
    );
    System.assertEquals(
      'ConnectorOutboundOperationExecutor',
      pluralCustomer.executorClassName
    );
    System.assertEquals(
      'ConnectorInboundOperationExecutor',
      pluralItem.executorClassName
    );
    System.assertEquals(
      'ConnectorOutboundOperationExecutor',
      pluralVendor.executorClassName
    );
    System.assertEquals(
      'ConnectorOutboundOperationExecutor',
      orderOutbound.executorClassName
    );
    System.assertEquals(
      'ConnectorOutboundOperationExecutor',
      purchaseOrderOutbound.executorClassName
    );
    System.assertEquals(
      'ConnectorOutboundOperationExecutor',
      quoteOutbound.executorClassName
    );
  }

  @IsTest
  static void qboInboundRetryClassificationIsTypedAndBounded() {
    for (
      Integer retryableStatus : new List<Integer>{
        408,
        409,
        425,
        429,
        500,
        503,
        599
      }
    ) {
      System.assertEquals(
        true,
        ConnectorInboundOperationExecutor.isRetryableException(
          IntegrationRetryPolicy.exceptionForStatus(
            retryableStatus,
            'HTTP ' + retryableStatus
          )
        )
      );
    }
    for (
      Integer permanentStatus : new List<Integer>{ 400, 401, 403, 404, 422 }
    ) {
      System.assertEquals(
        false,
        ConnectorInboundOperationExecutor.isRetryableException(
          IntegrationRetryPolicy.exceptionForStatus(
            permanentStatus,
            'HTTP ' + permanentStatus
          )
        )
      );
    }
    System.assertEquals(
      true,
      ConnectorInboundOperationExecutor.isRetryableException(
        new ConnectorInboundOperationExecutor.ConnectorInboundOperationExecutorException(
          'Provider read timed out.'
        )
      )
    );
    System.assertEquals(
      false,
      ConnectorInboundOperationExecutor.isRetryableException(
        new ConnectorInboundOperationExecutor.ConnectorInboundOperationExecutorException(
          'Mapped field value was invalid.'
        )
      )
    );
  }

  @IsTest
  static void outboundSharedRuntimeHydratesLegacyAccountPayloadFields() {
    configureQuickBooks();
    requestBodies.clear();
    Test.setMock(HttpCalloutMock.class, new QuickBooksSharedMock());
    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name = 'Hydrated Shared Account'
      LIMIT 1
    ];
    ConnectorExecutionRequest accountRequest = requestFor(
      'Customer',
      'Outbound',
      'Account',
      'Customer'
    );
    accountRequest.initialSync = true;
    accountRequest.recordIds.add(accountRecord.Id);
    Test.startTest();
    ConnectorExecutionResult accountResult = ConnectorExecutionService.executeOutboundScope(
      accountRequest,
      new List<SObject>{ new Account(Id = accountRecord.Id) }
    );
    Test.stopTest();

    System.assertEquals(1, accountResult.successfulCount);
    String bodies = String.join(requestBodies, ' ');
    System.assert(
      bodies.contains('Hydrated Shared Account'),
      'Account payload must match the legacy hydrated scheduler payload.'
    );
    System.assertEquals(
      'C-OUT',
      [SELECT QuickbookID__c FROM Account WHERE Id = :accountRecord.Id]
      .QuickbookID__c
    );
  }

  @IsTest
  static void outboundSharedRuntimeHydratesLegacyProductPayloadFields() {
    configureQuickBooks();
    requestBodies.clear();
    Test.setMock(HttpCalloutMock.class, new QuickBooksSharedMock());
    Product2 productRecord = [
      SELECT Id
      FROM Product2
      WHERE Name = 'Hydrated Shared Product'
      LIMIT 1
    ];
    ConnectorExecutionRequest productRequest = requestFor(
      'Item',
      'Outbound',
      'Product2',
      'Item'
    );
    productRequest.initialSync = true;
    productRequest.recordIds.add(productRecord.Id);

    Test.startTest();
    ConnectorExecutionResult productResult = ConnectorExecutionService.executeOutboundScope(
      productRequest,
      new List<SObject>{ new Product2(Id = productRecord.Id) }
    );
    Test.stopTest();

    System.assertEquals(1, productResult.successfulCount);
    String bodies = String.join(requestBodies, ' ');
    System.assert(
      bodies.contains('Hydrated Shared Product'),
      'Product payload must retain the legacy service hydration behavior. Bodies: ' +
      bodies
    );
    System.assertEquals(
      'I-OUT',
      [SELECT QuickbookID__c FROM Product2 WHERE Id = :productRecord.Id]
      .QuickbookID__c
    );
  }

  @IsTest
  static void inboundCustomerSharedRuntimeUsesBoundedLegacyScope() {
    configureQuickBooks();
    Test.setMock(HttpCalloutMock.class, new QuickBooksSharedMock());
    ConnectorExecutionRequest customerRequest = requestFor(
      'Customer',
      'Inbound',
      'Account',
      'Customer'
    );
    customerRequest.sinceValue = Datetime.newInstance(2026, 5, 24, 0, 0, 0);
    customerRequest.scopeSize = 50;
    Test.startTest();
    ConnectorExecutionResult customerResult = ConnectorExecutionService.executeInboundPage(
      customerRequest
    );
    Test.stopTest();

    System.assertEquals(
      1,
      customerResult.successfulCount,
      'Unexpected shared customer failure: ' + customerResult.errorSummary
    );
    System.assertEquals(null, customerResult.nextCursor);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Account WHERE QuickbookID__c = 'C-SHARED']
    );
  }

  @IsTest
  static void inboundItemSharedRuntimeUsesBoundedLegacyScope() {
    configureQuickBooks();
    Test.setMock(HttpCalloutMock.class, new QuickBooksSharedMock());
    ConnectorExecutionRequest itemRequest = requestFor(
      'Item',
      'Inbound',
      'Product2',
      'Item'
    );
    itemRequest.sinceValue = Datetime.newInstance(2026, 5, 24, 0, 0, 0);
    itemRequest.scopeSize = 50;

    Test.startTest();
    ConnectorExecutionResult itemResult = ConnectorExecutionService.executeInboundPage(
      itemRequest
    );
    Test.stopTest();

    System.assertEquals(
      1,
      itemResult.successfulCount,
      'Unexpected shared item failure: ' + itemResult.errorSummary
    );
    System.assertEquals(null, itemResult.nextCursor);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Product2 WHERE QuickbookID__c = 'I-SHARED']
    );
  }

  @IsTest
  static void inboundVendorSharedRuntimeUsesBoundedLegacyScope() {
    configureQuickBooks();
    Test.setMock(HttpCalloutMock.class, new QuickBooksSharedMock());
    ConnectorExecutionRequest vendorRequest = requestFor(
      'Vendor',
      'Inbound',
      'Account',
      'Vendor'
    );
    vendorRequest.sinceValue = Datetime.newInstance(2026, 5, 24, 0, 0, 0);

    Test.startTest();
    ConnectorExecutionResult result = ConnectorExecutionService.executeInboundPage(
      vendorRequest
    );
    Test.stopTest();

    System.assertEquals(1, result.processedCount);
    System.assertEquals(
      1,
      result.successfulCount,
      'Vendor error: ' + result.errorSummary
    );
    System.assertEquals(0, result.failedCount);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Account WHERE QuickbookID__c = 'V-SHARED']
    );
  }

  @IsTest
  static void sharedVendorScopeSurfacesMalformedPayloadFailure() {
    configureQuickBooks();

    Test.startTest();
    ConnectorExecutionResult result = new QBVendorToAccountSyncBatch(
        '2026-05-24'
      )
      .executeSharedScope(new List<String>{ '{' });
    Test.stopTest();

    System.assertEquals(1, result.processedCount);
    System.assertEquals(0, result.successfulCount);
    System.assertEquals(1, result.failedCount);
  }

  @IsTest
  static void sharedCustomerScopeSurfacesMalformedPayloadFailure() {
    configureQuickBooks();

    Test.startTest();
    ConnectorExecutionResult result = new QBCustomerToAccountSyncBatch(
        '2026-05-24'
      )
      .executeSharedScope(new List<String>{ '{' });
    Test.stopTest();

    System.assertEquals(1, result.processedCount);
    System.assertEquals(0, result.successfulCount);
    System.assertEquals(1, result.failedCount);
    System.assertEquals(true, result.hasFailures());
  }

  @IsTest
  static void sharedItemScopeSurfacesMalformedPayloadFailure() {
    configureQuickBooks();

    Test.startTest();
    ConnectorExecutionResult result = new QBItemToProductSyncBatch('2026-05-24')
      .executeSharedScope(new List<String>{ '{' });
    Test.stopTest();

    System.assertEquals(1, result.processedCount);
    System.assertEquals(0, result.successfulCount);
    System.assertEquals(1, result.failedCount);
    System.assertEquals(true, result.hasFailures());
  }

  @IsTest
  static void quickBooksInboundPreservesRetryableStatus() {
    configureQuickBooks();
    Test.setMock(HttpCalloutMock.class, new RateLimitedQuickBooksMock());
    ConnectorExecutionRequest request = requestFor(
      'Customer',
      'Inbound',
      'Account',
      'Customer'
    );

    Test.startTest();
    ConnectorExecutionResult result = ConnectorExecutionService.executeInboundPage(
      request
    );
    Test.stopTest();

    System.assertEquals(true, result.hasFailures());
    System.assertEquals(true, result.retryable);
    System.assertEquals(60, result.retryDelaySeconds);
  }

  @IsTest
  static void outboundAccountScopeSurfacesMixedRetryableFailure() {
    configureQuickBooks();
    QBTriggerHandler.isAccountProcessing = true;
    List<Account> accounts = new List<Account>{
      new Account(Name = 'Mixed Success', QuickbookID__c = 'C-OK'),
      new Account(Name = 'Mixed Failure', QuickbookID__c = 'C-FAIL')
    };
    try {
      insert accounts;
    } finally {
      QBTriggerHandler.isAccountProcessing = false;
    }
    Test.setMock(HttpCalloutMock.class, new MixedAccountOutboundMock());

    Test.startTest();
    ConnectorExecutionResult result = QBAccountService.syncAccountsToQuickBooksShared(
      accounts,
      false
    );
    Test.stopTest();

    System.assertEquals(2, result.processedCount);
    System.assertEquals(1, result.successfulCount);
    System.assertEquals(1, result.failedCount);
    System.assertEquals(true, result.retryable);
    System.assertEquals(new List<Id>{ accounts[1].Id }, result.retryRecordIds);
  }

  @IsTest
  static void outboundOrderPreservesLinesAndSyncIdentifiers() {
    configureQuickBooks();
    Order orderRecord = createSharedOrder();
    ConnectorExecutionRequest request = requestFor(
      'Order',
      'Outbound',
      'Order',
      'Invoice'
    );
    request.initialSync = true;
    request.recordIds.add(orderRecord.Id);
    requestBodies.clear();
    Test.setMock(HttpCalloutMock.class, new QuickBooksSharedMock());

    Test.startTest();
    ConnectorExecutionResult result = ConnectorExecutionService.executeOutboundScope(
      request,
      new List<SObject>{ new Order(Id = orderRecord.Id) }
    );
    Test.stopTest();

    System.assertEquals(1, result.processedCount);
    System.assertEquals(
      1,
      result.successfulCount,
      'Order error: ' + result.errorSummary
    );
    System.assertEquals(0, result.failedCount);
    Order updatedOrder = [
      SELECT QuickbookID__c, SyncToken__c
      FROM Order
      WHERE Id = :orderRecord.Id
    ];
    System.assert(String.isNotBlank(updatedOrder.QuickbookID__c));
    System.assertEquals('2', updatedOrder.SyncToken__c);
    OrderItem updatedLine = [
      SELECT QB_LineiTemID__c
      FROM OrderItem
      WHERE OrderId = :orderRecord.Id
      LIMIT 1
    ];
    System.assert(
      updatedLine.QB_LineiTemID__c.endsWith(':LINE-1'),
      'The returned QBO line identifier must remain associated with its Salesforce line.'
    );
    System.assert(
      String.join(requestBodies, ' ').contains('I-LINE'),
      'The shared path must retain hydrated QBO item references.'
    );
  }

  @IsTest
  static void outboundOrderSurfacesRetryableProviderFailure() {
    configureQuickBooks();
    Order orderRecord = createSharedOrder();
    ConnectorExecutionRequest request = requestFor(
      'Order',
      'Outbound',
      'Order',
      'Invoice'
    );
    request.initialSync = true;
    request.recordIds.add(orderRecord.Id);
    Test.setMock(HttpCalloutMock.class, new FailedOrderOutboundMock());

    Test.startTest();
    ConnectorExecutionResult result = ConnectorExecutionService.executeOutboundScope(
      request,
      new List<SObject>{ new Order(Id = orderRecord.Id) }
    );
    Test.stopTest();

    System.assertEquals(1, result.processedCount);
    System.assertEquals(0, result.successfulCount);
    System.assertEquals(1, result.failedCount);
    System.assertEquals(true, result.retryable);
    System.assertEquals(new List<Id>{ orderRecord.Id }, result.retryRecordIds);
  }

  @IsTest
  static void outboundOrderWorkerDoesNotCompleteSwallowedFailure() {
    configureQuickBooks();
    Order orderRecord = createSharedOrder();
    Test.setMock(HttpCalloutMock.class, new FailedOrderOutboundMock());
    Integration_Work_Item__c workItem = new Integration_Work_Item__c(
      Integration__c = 'QuickBooks',
      Operation__c = 'InvoiceUpsert',
      Source_Object__c = 'Order',
      Source_Record_Id__c = String.valueOf(orderRecord.Id),
      Source_Salesforce_Id__c = String.valueOf(orderRecord.Id),
      Payload__c = '{"isInitialSync":true}'
    );

    Test.startTest();
    try {
      QBInvoiceWorker.process(workItem);
      System.assert(
        false,
        'The work item must not complete after an Order callout failure.'
      );
    } catch (QBInvoiceWorker.QBInvoiceWorkerException expected) {
      System.assert(expected.getMessage().contains('synchronization failed'));
    }
    Test.stopTest();
  }

  @IsTest
  static void outboundPurchaseOrderPreservesMappedNestedLines() {
    configureQuickBooks();
    Purchase_Order__c purchaseOrder = createSharedPurchaseOrder();
    ConnectorExecutionRequest request = requestFor(
      'PurchaseOrder',
      'Outbound',
      'Purchase_Order__c',
      'PurchaseOrder'
    );
    request.initialSync = true;
    request.recordIds.add(purchaseOrder.Id);
    requestBodies.clear();
    Test.setMock(HttpCalloutMock.class, new QuickBooksSharedMock());

    Test.startTest();
    ConnectorExecutionResult result = ConnectorExecutionService.executeOutboundScope(
      request,
      new List<SObject>{ new Purchase_Order__c(Id = purchaseOrder.Id) }
    );
    Test.stopTest();

    System.assertEquals(1, result.processedCount);
    System.assertEquals(
      1,
      result.successfulCount,
      'Purchase Order error: ' + result.errorSummary
    );
    System.assertEquals(0, result.failedCount);
    System.assertEquals(
      'PO-SHARED',
      [
        SELECT External_Id__c
        FROM Purchase_Order__c
        WHERE Id = :purchaseOrder.Id
      ]
      .External_Id__c
    );
    String bodies = String.join(requestBodies, ' ');
    System.assert(bodies.contains('QB-PO-PRODUCT'));
    System.assert(bodies.contains('ItemBasedExpenseLineDetail'));
  }

  @IsTest
  static void outboundPurchaseOrderSurfacesRetryableFailure() {
    configureQuickBooks();
    Purchase_Order__c purchaseOrder = createSharedPurchaseOrder();
    ConnectorExecutionRequest request = requestFor(
      'PurchaseOrder',
      'Outbound',
      'Purchase_Order__c',
      'PurchaseOrder'
    );
    request.initialSync = true;
    request.recordIds.add(purchaseOrder.Id);
    Test.setMock(HttpCalloutMock.class, new FailedOrderOutboundMock());

    Test.startTest();
    ConnectorExecutionResult result = ConnectorExecutionService.executeOutboundScope(
      request,
      new List<SObject>{ new Purchase_Order__c(Id = purchaseOrder.Id) }
    );
    Test.stopTest();

    System.assertEquals(0, result.successfulCount);
    System.assertEquals(1, result.failedCount);
    System.assertEquals(true, result.retryable);
    System.assertEquals(
      new List<Id>{ purchaseOrder.Id },
      result.retryRecordIds
    );
  }

  @IsTest
  static void purchaseOrderWorkerPropagatesSharedFailure() {
    configureQuickBooks();
    Purchase_Order__c purchaseOrder = createSharedPurchaseOrder();
    Test.setMock(HttpCalloutMock.class, new FailedOrderOutboundMock());
    Integration_Work_Item__c workItem = new Integration_Work_Item__c(
      Source_Record_Id__c = String.valueOf(purchaseOrder.Id),
      Source_Salesforce_Id__c = String.valueOf(purchaseOrder.Id),
      Payload__c = '{"isInitialSync":true}'
    );

    Test.startTest();
    try {
      QBPurchaseOrderWorker.process(workItem);
      System.assert(
        false,
        'Purchase Order work must not complete after a provider failure.'
      );
    } catch (QBPurchaseOrderWorker.QBPurchaseOrderWorkerException expected) {
      System.assert(expected.getMessage().contains('synchronization failed'));
    }
    Test.stopTest();
  }

  @IsTest
  static void schedulerBuildsSharedRequestsAndKeepsLegacyFallback() {
    Set<Id> accountIds = new Map<Id, Account>(
        [
          SELECT Id
          FROM Account
          WHERE Name = 'Hydrated Shared Account'
        ]
      )
      .keySet();
    Scheduled_Integration_Job__c accountJob = new Scheduled_Integration_Job__c(
      Source_Object__c = 'Accounts',
      Direction__c = 'Out'
    );
    ConnectorExecutionRequest accountRequest = QuickBooksScheduledOperationAdapter.buildSharedRequest(
      accountJob,
      'lease-account',
      accountIds
    );
    Scheduled_Integration_Job__c productJob = new Scheduled_Integration_Job__c(
      Source_Object__c = 'Product',
      Direction__c = 'In'
    );
    ConnectorExecutionRequest productRequest = QuickBooksScheduledOperationAdapter.buildSharedRequest(
      productJob,
      'lease-product',
      new Set<Id>()
    );
    Scheduled_Integration_Job__c vendorJob = new Scheduled_Integration_Job__c(
      Source_Object__c = 'Vendors',
      Direction__c = 'In'
    );
    ConnectorExecutionRequest vendorRequest = QuickBooksScheduledOperationAdapter.buildSharedRequest(
      vendorJob,
      'lease-vendor',
      new Set<Id>()
    );
    ConnectorExecutionRequest orderRequest = QuickBooksScheduledOperationAdapter.buildSharedRequest(
      new Scheduled_Integration_Job__c(
        Source_Object__c = 'Orders',
        Direction__c = 'Out'
      ),
      'lease-order',
      new Set<Id>()
    );
    ConnectorExecutionRequest purchaseOrderRequest = QuickBooksScheduledOperationAdapter.buildSharedRequest(
      new Scheduled_Integration_Job__c(
        Source_Object__c = 'Purchase Order',
        Direction__c = 'Out'
      ),
      'lease-purchase-order',
      new Set<Id>()
    );
    ConnectorExecutionRequest quoteRequest = QuickBooksScheduledOperationAdapter.buildSharedRequest(
      new Scheduled_Integration_Job__c(
        Source_Object__c = 'Quote',
        Direction__c = 'Out'
      ),
      'lease-quote',
      new Set<Id>()
    );

    System.assertEquals('Customer', accountRequest.operationKey);
    System.assertEquals('Outbound', accountRequest.direction);
    System.assertEquals(1, accountRequest.scopeSize);
    System.assertEquals(accountIds, new Set<Id>(accountRequest.recordIds));
    System.assertEquals('Item', productRequest.operationKey);
    System.assertEquals('Inbound', productRequest.direction);
    System.assertEquals(50, productRequest.scopeSize);
    System.assertNotEquals(null, productRequest.sinceValue);
    System.assertEquals('Vendor', vendorRequest.operationKey);
    System.assertEquals('Vendor', vendorRequest.externalEntity);
    System.assertEquals('Account', vendorRequest.salesforceObject);
    System.assertEquals('Order', orderRequest.operationKey);
    System.assertEquals('Invoice', orderRequest.externalEntity);
    System.assertEquals(1, orderRequest.scopeSize);
    System.assertEquals('PurchaseOrder', purchaseOrderRequest.operationKey);
    System.assertEquals(
      'Purchase_Order__c',
      purchaseOrderRequest.salesforceObject
    );
    System.assertEquals(1, purchaseOrderRequest.scopeSize);
    System.assertEquals('Quote', quoteRequest.operationKey);
    System.assertEquals('Estimate', quoteRequest.externalEntity);
    System.assertEquals(1, quoteRequest.scopeSize);

    try {
      QuickBooksScheduledOperationAdapter.buildSharedRequest(
        new Scheduled_Integration_Job__c(
          Source_Object__c = 'Order',
          Direction__c = 'In'
        ),
        'legacy-order-inbound',
        new Set<Id>()
      );
      System.assert(
        false,
        'Inbound Order must remain on the legacy scheduler path.'
      );
    } catch (QuickBooksScheduledOperationAdapter.QuickBooksScheduledOperationException expected) {
      System.assert(expected.getMessage().contains('supported QuickBooks'));
    }
    try {
      QuickBooksScheduledOperationAdapter.buildSharedRequest(
        new Scheduled_Integration_Job__c(
          Source_Object__c = 'Purchase Order',
          Direction__c = 'In'
        ),
        'legacy-purchase-order-inbound',
        new Set<Id>()
      );
      System.assert(
        false,
        'Inbound Purchase Order must remain on the legacy scheduler path.'
      );
    } catch (QuickBooksScheduledOperationAdapter.QuickBooksScheduledOperationException expected) {
      System.assert(expected.getMessage().contains('supported QuickBooks'));
    }
    try {
      QuickBooksScheduledOperationAdapter.buildSharedRequest(
        new Scheduled_Integration_Job__c(
          Source_Object__c = 'Quote',
          Direction__c = 'In'
        ),
        'legacy-estimate-inbound',
        new Set<Id>()
      );
      System.assert(
        false,
        'Inbound Estimate must remain on the legacy scheduler path.'
      );
    } catch (QuickBooksScheduledOperationAdapter.QuickBooksScheduledOperationException expected) {
      System.assert(expected.getMessage().contains('supported QuickBooks'));
    }

    for (
      String legacyTarget : new List<String>{
        'Invoice',
        'Credit Memo',
        'ItemSalesTax',
        'Item Sales Tax',
        'Tax Code',
        'OrderSummary',
        'OrderSummaries'
      }
    ) {
      try {
        QuickBooksScheduledOperationAdapter.buildSharedRequest(
          new Scheduled_Integration_Job__c(Source_Object__c = legacyTarget),
          'legacy-lease',
          new Set<Id>()
        );
        System.assert(
          false,
          legacyTarget + ' must remain on the legacy scheduler path.'
        );
      } catch (QuickBooksScheduledOperationAdapter.QuickBooksScheduledOperationException expected) {
        System.assert(expected.getMessage().contains('supported QuickBooks'));
      }
    }

    QuickBooksScheduledOperationAdapter.skipExecutionForTests = true;
    ConnectorScheduleDispatchResult skipped = new QuickBooksScheduledOperationAdapter()
      .dispatch(productJob, 'lease-product');
    System.assertEquals(false, skipped.ownershipTransferred);
    System.assertEquals(false, skipped.hasFailed());
  }

  @IsTest
  static void inboundScheduleTransfersOwnershipToSharedBatch() {
    configureQuickBooks();
    Test.setMock(HttpCalloutMock.class, new QuickBooksSharedMock());
    Scheduled_Integration_Job__c job = new Scheduled_Integration_Job__c(
      Source_Object__c = 'Account',
      Direction__c = 'In'
    );

    Test.startTest();
    ConnectorScheduleDispatchResult dispatchResult = new QuickBooksScheduledOperationAdapter()
      .dispatch(job, 'lease-qbo-inbound');
    Test.stopTest();

    System.assertEquals(true, dispatchResult.ownershipTransferred);
    System.assertNotEquals(null, dispatchResult.asyncJobId);
    System.assertEquals(false, dispatchResult.hasFailed());
  }

  private static ConnectorExecutionRequest requestFor(
    String operation,
    String direction,
    String salesforceObject,
    String externalEntity
  ) {
    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = 'qbo';
    request.operationKey = operation;
    request.direction = direction;
    request.salesforceObject = salesforceObject;
    request.externalEntity = externalEntity;
    request.scopeSize = 50;
    return request;
  }

  private static void configureQuickBooks() {
    QuickBooksAuthHandler.configureConnectionForTest(
      '12345',
      'QuickBooks_Test_Named_Credential',
      '70'
    );
  }

  private static Order createSharedOrder() {
    Account accountRecord = [
      SELECT Id, QuickbookID__c
      FROM Account
      WHERE Name = 'Hydrated Shared Account'
      LIMIT 1
    ];
    Product2 productRecord = [
      SELECT Id, QuickbookID__c
      FROM Product2
      WHERE Name = 'Hydrated Shared Product'
      LIMIT 1
    ];
    QBTriggerHandler.isAccountProcessing = true;
    QBTriggerHandler.isProductProcessing = true;
    try {
      accountRecord.QuickbookID__c = 'C-LINE';
      productRecord.QuickbookID__c = 'I-LINE';
      update accountRecord;
      update productRecord;
    } finally {
      QBTriggerHandler.isAccountProcessing = false;
      QBTriggerHandler.isProductProcessing = false;
    }
    Id standardPricebookId = Test.getStandardPricebookId();
    PricebookEntry entry = new PricebookEntry(
      Pricebook2Id = standardPricebookId,
      Product2Id = productRecord.Id,
      UnitPrice = 25,
      IsActive = true
    );
    insert entry;
    Order orderRecord = new Order(
      AccountId = accountRecord.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Pricebook2Id = standardPricebookId
    );
    QBTriggerHandler.isOrderProcessing = true;
    try {
      insert orderRecord;
      insert new OrderItem(
        OrderId = orderRecord.Id,
        PricebookEntryId = entry.Id,
        Quantity = 2,
        UnitPrice = 25
      );
    } finally {
      QBTriggerHandler.isOrderProcessing = false;
    }
    return orderRecord;
  }

  private static Purchase_Order__c createSharedPurchaseOrder() {
    Account supplier = new Account(
      Name = 'Shared PO Supplier',
      QuickbookID__c = 'QB-PO-SUPPLIER'
    );
    Product2 product = new Product2(
      Name = 'Shared PO Product',
      QuickbookID__c = 'QB-PO-PRODUCT',
      IsActive = true
    );
    QBTriggerHandler.isAccountProcessing = true;
    QBTriggerHandler.isProductProcessing = true;
    try {
      insert supplier;
      insert product;
    } finally {
      QBTriggerHandler.isAccountProcessing = false;
      QBTriggerHandler.isProductProcessing = false;
    }
    Purchase_Order__c purchaseOrder = new Purchase_Order__c(
      Account__c = supplier.Id,
      Supplier__c = supplier.Id
    );
    insert purchaseOrder;
    insert new Purchase_Order_Line__c(
      Purchase_Order__c = purchaseOrder.Id,
      Product__c = product.Id,
      Quantity__c = 3,
      Cost_Price__c = 12,
      Product_Description__c = 'Shared mapped line'
    );
    return purchaseOrder;
  }
}