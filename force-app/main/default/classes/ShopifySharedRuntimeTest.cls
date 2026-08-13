@IsTest
private class ShopifySharedRuntimeTest {
  private class ShopifyMock implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;
    private String linkHeader;
    private String retryAfter;

    ShopifyMock(Integer statusCode, String responseBody) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(responseBody);
      if (String.isNotBlank(linkHeader))
        response.setHeader('link', linkHeader);
      if (String.isNotBlank(retryAfter))
        response.setHeader('Retry-After', retryAfter);
      return response;
    }
  }

  private class WorkerQueueable implements Queueable, Database.AllowsCallouts {
    private Id accountId;

    WorkerQueueable(Id accountId) {
      this.accountId = accountId;
    }

    public void execute(QueueableContext context) {
      ShopifyIntegrationWorker.process(
        new Integration_Work_Item__c(
          Integration__c = 'Shopify',
          Operation__c = 'CustomerUpsert',
          Source_Object__c = 'Account',
          Source_Salesforce_Id__c = accountId,
          Payload__c = '{"isInitialSync":true}'
        )
      );
    }
  }

  private class ResultQueueable implements Queueable, Database.AllowsCallouts {
    private Id accountId;

    ResultQueueable(Id accountId) {
      this.accountId = accountId;
    }

    public void execute(QueueableContext context) {
      ConnectorExecutionRequest request = requestFor(
        'Customer',
        'Outbound',
        'Account',
        'Customer'
      );
      request.recordIds = new List<Id>{ accountId };
      ConnectorExecutionResult result = ConnectorExecutionService.executeSingle(
        request
      );
      update new Account(Id = accountId, Description = JSON.serialize(result));
    }
  }

  @IsTest
  static void productionRegistryPrefersSharedShopifyDefinitions() {
    ConnectorOperationRegistry.OperationDefinition inbound = ConnectorOperationRegistry.resolve(
      requestFor('Products', 'Inbound', 'Product2', 'Product')
    );
    ConnectorOperationRegistry.OperationDefinition outbound = ConnectorOperationRegistry.resolve(
      requestFor('Customer', 'Outbound', 'Account', 'Customer')
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
      'https://mock-shopify.com/admin/api/2024-04/products.json',
      inbound.approvedBaseUrl
    );
  }

  @IsTest
  static void inboundUsesSharedLinkPaginationAndRejectsHostChanges() {
    ShopifyProductsBatch.bypassAuthCheckForTest = true;
    ShopifyMock successMock = new ShopifyMock(200, '{"products":[]}');
    successMock.linkHeader = '<https://mock-shopify.com/admin/api/2024-04/products.json?page_info=NEXT>; rel="next"';
    Test.setMock(HttpCalloutMock.class, successMock);

    ConnectorExecutionResult firstPage = ConnectorExecutionService.executeInboundPage(
      requestFor('Products', 'Inbound', 'Product2', 'Product')
    );
    System.assertEquals(
      false,
      firstPage.hasFailures(),
      String.isBlank(firstPage.errorSummary)
        ? 'Expected the first Shopify product page to succeed.'
        : firstPage.errorSummary
    );
    System.assertEquals(
      '/admin/api/2024-04/products.json?page_info=NEXT',
      firstPage.nextCursor
    );
    System.assertEquals(0, firstPage.failedCount);

    ShopifyMock hostileMock = new ShopifyMock(200, '{"products":[]}');
    hostileMock.linkHeader = '<https://evil.example/admin/api/2024-04/products.json?page_info=NEXT>; rel="next"';
    Test.setMock(HttpCalloutMock.class, hostileMock);
    ConnectorExecutionResult hostilePage = ConnectorExecutionService.executeInboundPage(
      requestFor('Products', 'Inbound', 'Product2', 'Product')
    );
    System.assert(hostilePage.hasFailures());
    System.assert(hostilePage.errorSummary.contains('approved API boundary'));
    ShopifyProductsBatch.bypassAuthCheckForTest = false;
  }

  @IsTest
  static void inboundRateLimitCarriesRetryAfterIntoSharedResult() {
    ShopifyProductsBatch.bypassAuthCheckForTest = true;
    ShopifyMock rateLimitMock = new ShopifyMock(429, '{}');
    rateLimitMock.retryAfter = '75';
    Test.setMock(HttpCalloutMock.class, rateLimitMock);

    ConnectorExecutionResult result = ConnectorExecutionService.executeInboundPage(
      requestFor('Product', 'Inbound', 'Product2', 'Product')
    );

    System.assertEquals(true, result.retryable);
    System.assertEquals(75, result.retryDelaySeconds);
    System.assertEquals(1, result.failedCount);
    System.assert(result.errorSummary.contains('HTTP 429'));
    ShopifyProductsBatch.bypassAuthCheckForTest = false;
  }

  @IsTest
  static void outboundSingleRecordRunsInsideWorkProcessorPath() {
    ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
    ShopifyCustomersOutboundBatch.testFieldMap = new Map<String, String>{
      'Name' => 'last_name'
    };
    ShopifyMock mockValue = new ShopifyMock(
      201,
      '{"customer":{"id":"SHOP-CUSTOMER-1"}}'
    );
    Test.setMock(HttpCalloutMock.class, mockValue);
    Account accountRecord = new Account(Name = 'Shared Shopify Customer');
    insert accountRecord;

    Test.startTest();
    Id workerJobId = System.enqueueJob(new WorkerQueueable(accountRecord.Id));
    Test.stopTest();
    List<AsyncApexJob> childBatchJobs = [
      SELECT Id, ApexClass.Name, JobType, Status, ParentJobId
      FROM AsyncApexJob
      WHERE
        ParentJobId = :workerJobId
        AND ApexClass.Name IN (
          'ShopifyCustomersOutboundBatch',
          'ConnectorOutboundBatch'
        )
    ];

    Account synchronizedAccount = [
      SELECT Shopify_ID__c
      FROM Account
      WHERE Id = :accountRecord.Id
    ];
    System.assertEquals('SHOP-CUSTOMER-1', synchronizedAccount.Shopify_ID__c);
    System.assertEquals(
      0,
      childBatchJobs.size(),
      JSON.serialize(childBatchJobs)
    );
    ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = false;
    ShopifyCustomersOutboundBatch.testFieldMap = null;
  }

  @IsTest
  static void outboundReturnsOnlyRateLimitedRecordsForRetry() {
    ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
    ShopifyCustomersOutboundBatch.testFieldMap = new Map<String, String>{
      'Name' => 'last_name'
    };
    ShopifyMock mockValue = new ShopifyMock(429, '{}');
    mockValue.retryAfter = '120';
    Test.setMock(HttpCalloutMock.class, mockValue);
    Account accountRecord = new Account(Name = 'Rate Limited Customer');
    insert accountRecord;

    Test.startTest();
    System.enqueueJob(new ResultQueueable(accountRecord.Id));
    Test.stopTest();
    ConnectorExecutionResult result = (ConnectorExecutionResult) JSON.deserialize(
      [SELECT Description FROM Account WHERE Id = :accountRecord.Id]
      .Description,
      ConnectorExecutionResult.class
    );

    System.assertEquals(true, result.retryable);
    System.assertEquals(120, result.retryDelaySeconds);
    System.assertEquals(
      new List<Id>{ accountRecord.Id },
      result.retryRecordIds
    );
    ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = false;
    ShopifyCustomersOutboundBatch.testFieldMap = null;
  }

  @IsTest
  static void scheduledProductInboundTransfersTerminalOwnership() {
    Scheduled_Integration_Job__c job = new Scheduled_Integration_Job__c(
      Source_Object__c = 'Products',
      Direction__c = 'In'
    );
    ConnectorScheduleDispatchResult result = new ShopifyScheduledOperationAdapter()
      .dispatch(job, 'lease-token');

    System.assertEquals(true, result.ownershipTransferred);
    System.assertNotEquals(null, result.asyncJobId);
    System.assertEquals(null, result.errorMessage);
  }

  private static ConnectorExecutionRequest requestFor(
    String operation,
    String direction,
    String salesforceObject,
    String externalEntity
  ) {
    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = 'Shopify';
    request.operationKey = operation;
    request.direction = direction;
    request.salesforceObject = salesforceObject;
    request.externalEntity = externalEntity;
    request.initialSync = direction == 'Outbound';
    request.scopeSize = direction == 'Outbound' ? 10 : 1;
    return request;
  }
}