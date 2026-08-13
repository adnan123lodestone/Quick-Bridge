@IsTest
private class KlaviyoSharedRuntimeTest {
  private static Integer mockCallCount = 0;

  private class KlaviyoPageMock implements HttpCalloutMock {
    Integer statusCode;
    String body;
    String retryAfter;
    List<String> endpoints = new List<String>();

    KlaviyoPageMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
      endpoints.add(request.getEndpoint());
      mockCallCount++;
      Assert.isTrue(
        request.getEndpoint().startsWith('callout:Klaviyo_API/api/')
      );
      Assert.areEqual(
        KlaviyoAuthService.API_REVISION,
        request.getHeader('revision')
      );
      Assert.isNull(request.getHeader('Authorization'));
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(body);
      if (String.isNotBlank(retryAfter)) {
        response.setHeader('Retry-After', retryAfter);
      }
      return response;
    }
  }

  @IsTest
  static void legacyAndSharedProfilePathsUseTheSameNamedCredentialBoundary() {
    KlaviyoPageMock mock = new KlaviyoPageMock(
      200,
      '{"data":[],"links":{"next":null}}'
    );
    mockCallCount = 0;
    Test.setMock(HttpCalloutMock.class, mock);

    new KlaviyoProfilesBatch().execute(null, new List<Integer>{ 1 });
    ConnectorExecutionResult sharedResult = ConnectorExecutionService.executeInboundPage(
      profileRequest()
    );

    Assert.areEqual(2, mockCallCount);
    Assert.isFalse(
      sharedResult.hasFailures(),
      'Unexpected shared profile failure: ' +
      String.valueOf(sharedResult.errorSummary)
    );

    ConnectorOperationRegistry.OperationDefinition definition = ConnectorOperationRegistry.resolve(
      profileRequest()
    );
    Assert.areEqual(
      'ConnectorInboundOperationExecutor',
      definition.executorClassName
    );
    Assert.areEqual('Klaviyo_API', definition.namedCredential);
    Assert.areEqual('/api/profiles', definition.relativeEndpoint);
  }

  @IsTest
  static void sharedPathRejectsHostAndOperationPathChanges() {
    Test.setMock(
      HttpCalloutMock.class,
      new KlaviyoPageMock(
        200,
        '{"data":[],"links":{"next":"https://evil.example/api/profiles?page[cursor]=x"}}'
      )
    );
    ConnectorExecutionResult hostileNext = ConnectorExecutionService.executeInboundPage(
      profileRequest()
    );
    Assert.isTrue(hostileNext.hasFailures());
    Assert.isTrue(hostileNext.errorSummary.contains('approved'));

    ConnectorExecutionRequest changedPath = profileRequest();
    changedPath.cursor = '/api/lists?page[cursor]=x';
    ConnectorExecutionResult changedPathResult = ConnectorExecutionService.executeInboundPage(
      changedPath
    );
    Assert.isTrue(changedPathResult.hasFailures());
    Assert.isTrue(changedPathResult.errorSummary.contains('operation path'));
  }

  @IsTest
  static void sharedPathClassifiesRetryableHttpFailuresAndMalformedPayloads() {
    KlaviyoPageMock limited = new KlaviyoPageMock(429, '{"errors":[]}');
    limited.retryAfter = '17';
    Test.setMock(HttpCalloutMock.class, limited);
    ConnectorExecutionResult limitedResult = ConnectorExecutionService.executeInboundPage(
      profileRequest()
    );
    Assert.isTrue(limitedResult.hasFailures());
    Assert.isTrue(limitedResult.retryable, limitedResult.errorSummary);
    Assert.areEqual(17, limitedResult.retryDelaySeconds);

    Test.setMock(
      HttpCalloutMock.class,
      new KlaviyoPageMock(200, '{"links":{"next":null}}')
    );
    ConnectorExecutionResult missingRoot = ConnectorExecutionService.executeInboundPage(
      profileRequest()
    );
    Assert.isTrue(missingRoot.hasFailures());
    Assert.isTrue(missingRoot.errorSummary.contains('data collection'));
  }

  @IsTest
  static void sharedListPageReturnsDmlCountsAndApprovedCursor() {
    Test.setMock(
      HttpCalloutMock.class,
      new KlaviyoPageMock(
        200,
        '{"data":[{"id":"list-shared","attributes":{"name":"Shared List"},"relationships":{"profiles":{"links":{"self":"https://a.klaviyo.com/api/lists/list-shared/profiles"}}}}],"links":{"next":"https://a.klaviyo.com/api/lists?page[cursor]=next-list"}}'
      )
    );
    ConnectorExecutionResult result = ConnectorExecutionService.executeInboundPage(
      listRequest()
    );

    Assert.isFalse(
      result.hasFailures(),
      'Unexpected shared list failure: ' + String.valueOf(result.errorSummary)
    );
    Assert.areEqual(1, result.processedCount);
    Assert.areEqual(1, result.successfulCount);
    Assert.areEqual('/api/lists?page[cursor]=next-list', result.nextCursor);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Campaign WHERE Klaviyo_ID__c = 'list-shared']
    );
  }

  @IsTest
  static void sharedEventPagePreservesRelationshipAndPayloadBehavior() {
    insert new Account(
      Name = 'Klaviyo Event Account',
      Klaviyo_ID__c = 'profile-event'
    );
    Test.setMock(
      HttpCalloutMock.class,
      new KlaviyoPageMock(
        200,
        '{"data":[{"id":"event-shared","relationships":{"profile":{"data":{"id":"profile-event"}}},"attributes":{"event_properties":{"Subject":"Shared Event","method":"api"}}}],"links":{"next":null}}'
      )
    );
    Test.startTest();
    Database.executeBatch(new ConnectorInboundBatch(eventRequest()), 1);
    Test.stopTest();

    Event insertedEvent = [
      SELECT Subject, Description, Klaviyo_Event_Id__c
      FROM Event
      WHERE Klaviyo_Event_Id__c = 'event-shared'
      LIMIT 1
    ];
    Assert.areEqual('Shared Event', insertedEvent.Subject);
    Assert.isTrue(insertedEvent.Description.contains('method: api'));
  }

  @IsTest
  static void sharedProfilePageReturnsPartialDmlAccounting() {
    KlaviyoProfilesBatch.forceBusinessAccountTest = true;
    Test.setMock(
      HttpCalloutMock.class,
      new KlaviyoPageMock(
        200,
        '{"data":[{"id":"profile-shared","attributes":{"email":"shared@example.com","first_name":"Shared","last_name":"Profile","organization":"Shared Org","phone_number":"123","properties":{},"location":{"city":"Austin","region":"TX","country":"US","zip":"78701"}}}],"links":{"next":null}}'
      )
    );
    ConnectorExecutionResult result = ConnectorExecutionService.executeInboundPage(
      profileRequest()
    );
    KlaviyoProfilesBatch.forceBusinessAccountTest = false;

    Assert.isFalse(
      result.hasFailures(),
      'Unexpected shared profile DML failure: ' +
      String.valueOf(result.errorSummary)
    );
    Assert.areEqual(1, result.processedCount);
    Assert.areEqual(1, result.successfulCount);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Account WHERE Klaviyo_ID__c = 'profile-shared']
    );
  }

  @IsTest
  static void listAndEventHttpFailuresAreExplicit() {
    KlaviyoPageMock listFailure = new KlaviyoPageMock(503, '{"errors":[]}');
    listFailure.retryAfter = '9';
    Test.setMock(HttpCalloutMock.class, listFailure);
    ConnectorExecutionResult listResult = ConnectorExecutionService.executeInboundPage(
      listRequest()
    );
    Assert.isTrue(listResult.hasFailures());
    Assert.isTrue(listResult.retryable);
    Assert.areEqual(9, listResult.retryDelaySeconds);

    Test.setMock(
      HttpCalloutMock.class,
      new KlaviyoPageMock(422, '{"errors":[]}')
    );
    ConnectorExecutionResult eventResult = ConnectorExecutionService.executeInboundPage(
      eventRequest()
    );
    Assert.isTrue(eventResult.hasFailures());
    Assert.isFalse(eventResult.retryable);
  }

  @IsTest
  static void campaignMemberAsyncFacadeUsesSharedPaginatedRuntime() {
    Id personAccountRecordTypeId = Schema.SObjectType.Account
      .getRecordTypeInfosByDeveloperName()
      .get('PersonAccount')
      .getRecordTypeId();
    Account personAccount = new Account(
      RecordTypeId = personAccountRecordTypeId,
      FirstName = 'Shared',
      LastName = 'Member',
      Klaviyo_ID__c = 'profile-member'
    );
    insert personAccount;
    personAccount = [
      SELECT PersonContactId
      FROM Account
      WHERE Id = :personAccount.Id
    ];
    Campaign campaignValue = new Campaign(
      Name = 'Shared Campaign Members',
      Profile_s_URL__c = 'https://a.klaviyo.com/api/lists/list-shared/profiles/'
    );
    insert campaignValue;

    ConnectorExecutionRequest request = KlaviyoCampaignMembersAsync.buildSharedRequest(
      campaignValue.Id
    );
    Assert.areEqual('CampaignMemberSync', request.operationKey);
    Assert.areEqual('Campaign', request.salesforceObject);
    Assert.areEqual(campaignValue.Id, request.recordIds[0]);
    ConnectorOperationRegistry.OperationDefinition definition = ConnectorOperationRegistry.resolve(
      request
    );
    Assert.areEqual(
      'ConnectorInboundOperationExecutor',
      definition.executorClassName
    );
    Assert.areEqual('/api/lists', definition.relativeEndpoint);

    Test.setMock(
      HttpCalloutMock.class,
      new KlaviyoPageMock(
        200,
        '{"data":[{"id":"profile-member"}],"links":{"next":null}}'
      )
    );
    Test.startTest();
    new KlaviyoCampaignMembersAsync(campaignValue.Id).execute(null);
    Test.stopTest();

    CampaignMember memberValue = [
      SELECT CampaignId, ContactId
      FROM CampaignMember
      WHERE CampaignId = :campaignValue.Id
      LIMIT 1
    ];
    Assert.areEqual(personAccount.PersonContactId, memberValue.ContactId);
  }

  @IsTest
  static void campaignMemberSharedPathReturnsExplicitMissingEndpointFailure() {
    Campaign missingEndpointCampaign = new Campaign(
      Name = 'Campaign Members Missing Endpoint'
    );
    insert missingEndpointCampaign;
    ConnectorExecutionResult missingEndpointResult = ConnectorExecutionService.executeInboundPage(
      KlaviyoCampaignMembersAsync.buildSharedRequest(missingEndpointCampaign.Id)
    );
    Assert.isTrue(missingEndpointResult.hasFailures());
    Assert.isFalse(missingEndpointResult.retryable);
    Assert.isTrue(
      missingEndpointResult.errorSummary.contains('endpoint is missing')
    );
  }

  @IsTest
  static void campaignMemberSharedPathReturnsExplicitRateLimitFailure() {
    Id campaignId = Id.valueOf('701000000000001');
    ConnectorExecutionRequest request = KlaviyoCampaignMembersAsync.buildSharedRequest(
      campaignId
    );
    request.cursor = 'https://a.klaviyo.com/api/lists/list-limited/profiles/';
    KlaviyoPageMock limited = new KlaviyoPageMock(429, '{"errors":[]}');
    limited.retryAfter = '23';
    Test.setMock(HttpCalloutMock.class, limited);
    ConnectorExecutionResult limitedResult = ConnectorExecutionService.executeInboundPage(
      request
    );
    Assert.isTrue(limitedResult.hasFailures());
    Assert.isTrue(limitedResult.retryable, limitedResult.errorSummary);
    Assert.areEqual(23, limitedResult.retryDelaySeconds);
  }

  @IsTest
  static void compatibilityExecutorRejectsUnsupportedRuntimePaths() {
    ConnectorInboundOperationExecutor executor = new ConnectorInboundOperationExecutor();
    Assert.isTrue(
      executor.executeOutboundScope(profileRequest(), new List<SObject>())
        .hasFailures()
    );
    Assert.isTrue(executor.executeSingle(profileRequest()).hasFailures());
    Assert.isTrue(ConnectorInboundOperationExecutor.isRetryableStatus(503));
    Assert.isFalse(ConnectorInboundOperationExecutor.isRetryableStatus(422));

    HttpResponse invalidRetry = new HttpResponse();
    invalidRetry.setHeader('Retry-After', 'tomorrow');
    Assert.isNull(
      ConnectorInboundOperationExecutor.retryAfterSeconds(invalidRetry)
    );
  }

  @IsTest
  static void legacyAdapterEntryPointAndUnsupportedSourceRemainCompatible() {
    Test.setMock(
      HttpCalloutMock.class,
      new KlaviyoPageMock(200, '{"data":[],"links":{"next":null}}')
    );
    Test.startTest();
    new KlaviyoScheduledOperationAdapter()
      .execute(new Scheduled_Integration_Job__c(Source_Object__c = 'Profiles'));
    Test.stopTest();

    new KlaviyoScheduledOperationAdapter()
      .execute(
        new Scheduled_Integration_Job__c(Source_Object__c = 'Unsupported')
      );
  }

  @IsTest
  static void schedulerRoutesAliasesAndTransfersTerminalOwnership() {
    Scheduled_Integration_Job__c listJob = new Scheduled_Integration_Job__c(
      Source_Object__c = 'Lists',
      Direction__c = 'In'
    );
    ConnectorExecutionRequest listRequest = KlaviyoScheduledOperationAdapter.buildSharedRequest(
      listJob,
      'lease-list'
    );
    Assert.areEqual('Lists', listRequest.operationKey);
    Assert.areEqual('Campaign', listRequest.salesforceObject);

    Scheduled_Integration_Job__c eventJob = new Scheduled_Integration_Job__c(
      Source_Object__c = 'Event'
    );
    ConnectorExecutionRequest eventRequest = KlaviyoScheduledOperationAdapter.buildSharedRequest(
      eventJob,
      'lease-event'
    );
    Assert.areEqual('Events', eventRequest.operationKey);

    ConnectorScheduleDispatchResult wrongDirection = new KlaviyoScheduledOperationAdapter()
      .dispatch(
        new Scheduled_Integration_Job__c(
          Source_Object__c = 'Profiles',
          Direction__c = 'Out'
        ),
        'lease-out'
      );
    Assert.isTrue(wrongDirection.hasFailed());
    Assert.isFalse(wrongDirection.ownershipTransferred);

    Scheduled_Integration_Job__c schedule = claimedSchedule('lease-profile');
    insert schedule;
    Test.setMock(
      HttpCalloutMock.class,
      new KlaviyoPageMock(200, '{"data":[],"links":{"next":null}}')
    );

    Test.startTest();
    ConnectorScheduleDispatchResult dispatchResult = new KlaviyoScheduledOperationAdapter()
      .dispatch(schedule, 'lease-profile');
    Assert.isTrue(dispatchResult.ownershipTransferred);
    Assert.isNotNull(dispatchResult.asyncJobId);
    Test.stopTest();

    Scheduled_Integration_Job__c completed = [
      SELECT Status__c, Lease_Token__c, Last_Error__c, Next_Run_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Ready', completed.Status__c);
    Assert.isNull(completed.Lease_Token__c);
    Assert.isNull(completed.Last_Error__c);
    Assert.isNotNull(completed.Next_Run_At__c);
  }

  private static ConnectorExecutionRequest profileRequest() {
    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = 'klaviyo';
    request.operationKey = 'Profiles';
    request.direction = 'Inbound';
    request.salesforceObject = 'Account';
    request.externalEntity = 'Profile';
    request.scopeSize = 1;
    return request;
  }

  private static ConnectorExecutionRequest listRequest() {
    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = 'klaviyo';
    request.operationKey = 'Lists';
    request.direction = 'Inbound';
    request.salesforceObject = 'Campaign';
    request.externalEntity = 'List';
    request.scopeSize = 1;
    return request;
  }

  private static ConnectorExecutionRequest eventRequest() {
    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = 'klaviyo';
    request.operationKey = 'Events';
    request.direction = 'Inbound';
    request.salesforceObject = 'Event';
    request.externalEntity = 'Event';
    request.scopeSize = 1;
    return request;
  }

  private static Scheduled_Integration_Job__c claimedSchedule(
    String leaseToken
  ) {
    return new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = 'Klaviyo Shared Runtime - ' + leaseToken,
      Scheduler_Name__c = 'Klaviyo Shared Runtime - ' + leaseToken,
      Integration_Type__c = 'Klaviyo',
      Source_Object__c = 'Profiles',
      Direction__c = 'In',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Claimed',
      Lease_Token__c = leaseToken,
      Lease_Expires_At__c = System.now().addMinutes(5),
      Next_Run_At__c = System.now().addMinutes(-1)
    );
  }
}