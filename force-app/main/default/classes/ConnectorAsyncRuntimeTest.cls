@IsTest
private class ConnectorAsyncRuntimeTest {
  private class StubExecutor implements ConnectorExecutionService.OperationExecutor {
    private ConnectorExecutionResult inboundResult;
    private ConnectorExecutionResult outboundResult;
    private Boolean throwInbound;
    private Boolean throwOutbound;

    StubExecutor(
      ConnectorExecutionResult inboundResult,
      ConnectorExecutionResult outboundResult
    ) {
      this.inboundResult = inboundResult;
      this.outboundResult = outboundResult;
    }

    StubExecutor throwInboundException() {
      throwInbound = true;
      return this;
    }

    StubExecutor throwOutboundException() {
      throwOutbound = true;
      return this;
    }

    public ConnectorExecutionResult executeInboundPage(
      ConnectorExecutionRequest request
    ) {
      if (throwInbound == true) {
        throw new StubExecutorException('inbound executor exception');
      }
      return inboundResult == null
        ? ConnectorExecutionResult.success()
        : inboundResult;
    }

    public ConnectorExecutionResult executeOutboundScope(
      ConnectorExecutionRequest request,
      List<SObject> scope
    ) {
      if (throwOutbound == true) {
        throw new StubExecutorException('outbound executor exception');
      }
      return outboundResult == null
        ? ConnectorExecutionResult.success()
        : outboundResult;
    }

    public ConnectorExecutionResult executeSingle(
      ConnectorExecutionRequest request
    ) {
      return ConnectorExecutionResult.success();
    }
  }

  private class StubExecutorException extends Exception {
  }

  private class NoopQueueable implements Queueable {
    public void execute(QueueableContext context) {
    }
  }

  @IsTest
  static void dispatchResultFactoriesExposeTerminalOwnership() {
    ConnectorScheduleDispatchResult synchronousResult = ConnectorScheduleDispatchResult.synchronous();
    System.assertEquals(false, synchronousResult.ownershipTransferred);
    System.assertEquals(false, synchronousResult.hasFailed());

    ConnectorScheduleDispatchResult invalidDeferred = ConnectorScheduleDispatchResult.deferred(
      null
    );
    System.assertEquals(false, invalidDeferred.ownershipTransferred);
    System.assertEquals(true, invalidDeferred.hasFailed());

    ConnectorScheduleDispatchResult failedResult = ConnectorScheduleDispatchResult.failed(
      null
    );
    System.assertEquals(true, failedResult.hasFailed());
    System.assertEquals(
      'Scheduled operation dispatch failed.',
      failedResult.errorMessage
    );

    Id asyncJobId = System.enqueueJob(new NoopQueueable());
    ConnectorScheduleDispatchResult deferredResult = ConnectorScheduleDispatchResult.deferred(
      asyncJobId
    );
    System.assertEquals(true, deferredResult.ownershipTransferred);
    System.assertEquals(asyncJobId, deferredResult.asyncJobId);
  }

  @IsTest
  static void scheduleServiceHandlesMissingContextAndNullResults() {
    System.assertEquals(
      false,
      ConnectorScheduleService.markRunning(null, null, null)
    );
    ConnectorScheduleService.completeSuccess(null, null);
    ConnectorScheduleService.completeFailure(null, null, null);

    Scheduled_Integration_Job__c schedule = claimedSchedule(
      'lease-null-result'
    );
    insert schedule;
    ConnectorScheduleService.complete(schedule.Id, 'lease-null-result', null);
    Scheduled_Integration_Job__c failed = scheduleById(schedule.Id);
    System.assertEquals('Failed', failed.Status__c);
    System.assert(failed.Last_Error__c.contains('no result'));

    Scheduled_Integration_Job__c successSchedule = claimedSchedule(
      'lease-result-success'
    );
    insert successSchedule;
    ConnectorScheduleService.complete(
      successSchedule.Id,
      'lease-result-success',
      ConnectorExecutionResult.success()
    );
    System.assertEquals('Ready', scheduleById(successSchedule.Id).Status__c);
  }

  @IsTest
  static void scheduleServiceRequiresMatchingLeaseForTransitions() {
    Scheduled_Integration_Job__c schedule = claimedSchedule('lease-current');
    insert schedule;

    System.assertEquals(
      false,
      ConnectorScheduleService.markRunning(schedule.Id, 'lease-stale', null)
    );
    ConnectorScheduleService.completeSuccess(schedule.Id, 'lease-stale');

    Scheduled_Integration_Job__c unchanged = scheduleById(schedule.Id);
    System.assertEquals('Claimed', unchanged.Status__c);
    System.assertEquals('lease-current', unchanged.Lease_Token__c);

    System.assertEquals(
      true,
      ConnectorScheduleService.markRunning(
        schedule.Id,
        'lease-current',
        null,
        3600
      )
    );
    Scheduled_Integration_Job__c running = scheduleById(schedule.Id);
    System.assertEquals('Running', running.Status__c);
    System.assertNotEquals(null, running.Lease_Expires_At__c);
    System.assert(running.Lease_Expires_At__c > Datetime.now().addMinutes(30));

    ConnectorScheduleService.completeFailure(
      schedule.Id,
      'lease-current',
      'expected failure'
    );
    Scheduled_Integration_Job__c failed = scheduleById(schedule.Id);
    System.assertEquals('Failed', failed.Status__c);
    System.assertEquals(null, failed.Lease_Token__c);
    System.assertEquals('expected failure', failed.Last_Error__c);
  }

  @IsTest
  static void leaseRefreshCanBeSkippedWhenGovernorHeadroomIsExhausted() {
    ConnectorScheduleService.leaseRefreshCapacityOverride = false;
    try {
      System.assertEquals(false, ConnectorScheduleService.hasLeaseRefreshCapacity());
    } finally {
      ConnectorScheduleService.leaseRefreshCapacityOverride = null;
    }
    System.assertEquals(true, ConnectorScheduleService.hasLeaseRefreshCapacity());
  }

  @IsTest
  static void inboundBatchCompletesOnlyAfterTerminalPage() {
    ConnectorExecutionRequest request = registerOperation('Inbound');
    request.leaseToken = 'lease-inbound';
    Scheduled_Integration_Job__c schedule = claimedSchedule(request.leaseToken);
    insert schedule;
    request.scheduleId = schedule.Id;

    ConnectorExecutionResult executorResult = ConnectorExecutionResult.success();
    executorResult.processedCount = 2;
    executorResult.successfulCount = 2;
    ConnectorExecutionService.registerTestExecutor(
      request,
      new StubExecutor(executorResult, null)
    );

    ConnectorInboundBatch batchValue = new ConnectorInboundBatch(request);
    System.assertEquals(1, batchValue.start(null).iterator().next());
    batchValue.execute(null, new List<Integer>{ 1 });
    batchValue.finish(null);

    Scheduled_Integration_Job__c completed = scheduleById(schedule.Id);
    System.assertEquals('Ready', completed.Status__c);
    System.assertEquals(null, completed.Lease_Token__c);
    System.assertNotEquals(null, completed.Next_Run_At__c);
  }

  @IsTest
  static void inboundBatchRejectsRepeatedCursorAndKeepsFailure() {
    ConnectorExecutionRequest request = registerOperation('Inbound');
    request.cursor = 'same-cursor';
    request.leaseToken = 'lease-cursor';
    Scheduled_Integration_Job__c schedule = claimedSchedule(request.leaseToken);
    insert schedule;
    request.scheduleId = schedule.Id;

    ConnectorExecutionResult executorResult = ConnectorExecutionResult.success();
    executorResult.nextCursor = 'same-cursor';
    ConnectorExecutionService.registerTestExecutor(
      request,
      new StubExecutor(executorResult, null)
    );

    ConnectorInboundBatch batchValue = new ConnectorInboundBatch(request);
    batchValue.start(null);
    batchValue.execute(null, new List<Integer>{ 1 });
    batchValue.finish(null);

    Scheduled_Integration_Job__c failed = scheduleById(schedule.Id);
    System.assertEquals('Failed', failed.Status__c);
    System.assert(failed.Last_Error__c.contains('same cursor'));
  }

  @IsTest
  static void inboundBatchBoundsPagesAndCapturesExecutorExceptions() {
    ConnectorExecutionRequest request = registerOperation('Inbound');
    request.pageNumber = ConnectorHttpClient.DEFAULT_MAX_PAGES;
    request.leaseToken = 'lease-page-limit';
    Scheduled_Integration_Job__c schedule = claimedSchedule(request.leaseToken);
    insert schedule;
    request.scheduleId = schedule.Id;

    ConnectorExecutionResult pageResult = ConnectorExecutionResult.success();
    pageResult.nextCursor = 'next-after-limit';
    ConnectorExecutionService.registerTestExecutor(
      request,
      new StubExecutor(pageResult, null)
    );
    ConnectorInboundBatch pageBatch = new ConnectorInboundBatch(request);
    pageBatch.start(null);
    pageBatch.execute(null, new List<Integer>{ 1 });
    pageBatch.finish(null);
    System.assert(
      scheduleById(schedule.Id)
        .Last_Error__c.contains(
          'exceeded ' + ConnectorHttpClient.DEFAULT_MAX_PAGES + ' pages'
        )
    );

    ConnectorExecutionRequest exceptionRequest = registerOperation('Inbound');
    exceptionRequest.leaseToken = 'lease-inbound-exception';
    Scheduled_Integration_Job__c exceptionSchedule = claimedSchedule(
      exceptionRequest.leaseToken
    );
    insert exceptionSchedule;
    exceptionRequest.scheduleId = exceptionSchedule.Id;
    ConnectorExecutionService.registerTestExecutor(
      exceptionRequest,
      new StubExecutor(null, null).throwInboundException()
    );
    ConnectorInboundBatch exceptionBatch = new ConnectorInboundBatch(
      exceptionRequest
    );
    exceptionBatch.start(null);
    exceptionBatch.execute(null, new List<Integer>{ 1 });
    exceptionBatch.finish(null);
    System.assertEquals('Failed', scheduleById(exceptionSchedule.Id).Status__c);

    ConnectorInboundBatch invalidBatch = new ConnectorInboundBatch(null);
    System.assertEquals(false, invalidBatch.start(null).iterator().hasNext());
    invalidBatch.execute(null, new List<Integer>());
    invalidBatch.finish(null);
  }

  @IsTest
  static void inboundBatchChainsOnlyToANewBoundedCursor() {
    Integer jobsBefore = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE ApexClass.Name = 'ConnectorInboundBatch'
    ];
    ConnectorExecutionRequest request = registerOperation('Inbound');
    request.cursor = 'page-one';
    ConnectorExecutionResult pageResult = ConnectorExecutionResult.success();
    pageResult.nextCursor = 'page-two';
    ConnectorExecutionService.registerTestExecutor(
      request,
      new StubExecutor(pageResult, null)
    );

    ConnectorInboundBatch batchValue = new ConnectorInboundBatch(request);
    batchValue.start(null);
    batchValue.execute(null, new List<Integer>{ 1 });
    batchValue.finish(null);

    Integer jobsAfter = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE ApexClass.Name = 'ConnectorInboundBatch'
    ];
    System.assertEquals(jobsBefore + 1, jobsAfter);
  }

  @IsTest
  static void inboundBatchRetriesOnlyRetryablePagesAndBoundsAttempts() {
    ConnectorExecutionRequest request = registerOperation('Inbound');
    request.leaseToken = 'lease-inbound-retry';
    Scheduled_Integration_Job__c schedule = claimedSchedule(request.leaseToken);
    insert schedule;
    request.scheduleId = schedule.Id;

    ConnectorExecutionResult retryableResult = ConnectorExecutionResult.failed(
      'temporarily unavailable HTTP 503',
      true,
      60
    );
    ConnectorExecutionService.registerTestExecutor(
      request,
      new StubExecutor(retryableResult, null)
    );

    ConnectorInboundBatch retryBatch = new ConnectorInboundBatch(request);
    retryBatch.start(null);
    retryBatch.execute(null, new List<Integer>{ 1 });
    retryBatch.finish(null);
    Scheduled_Integration_Job__c running = scheduleById(schedule.Id);
    System.assertEquals('Running', running.Status__c);
    System.assertEquals(request.leaseToken, running.Lease_Token__c);

    ConnectorExecutionRequest exhaustedRequest = registerOperation('Inbound');
    exhaustedRequest.retryAttempt = 5;
    exhaustedRequest.leaseToken = 'lease-inbound-exhausted';
    Scheduled_Integration_Job__c exhaustedSchedule = claimedSchedule(
      exhaustedRequest.leaseToken
    );
    insert exhaustedSchedule;
    exhaustedRequest.scheduleId = exhaustedSchedule.Id;
    ConnectorExecutionService.registerTestExecutor(
      exhaustedRequest,
      new StubExecutor(retryableResult, null)
    );
    ConnectorInboundBatch exhaustedBatch = new ConnectorInboundBatch(
      exhaustedRequest
    );
    exhaustedBatch.start(null);
    exhaustedBatch.execute(null, new List<Integer>{ 1 });
    exhaustedBatch.finish(null);
    System.assertEquals('Failed', scheduleById(exhaustedSchedule.Id).Status__c);
  }

  @IsTest
  static void sharedBatchesAbortBeforeWorkWhenLeaseIsStale() {
    Scheduled_Integration_Job__c inboundSchedule = claimedSchedule(
      'current-inbound-lease'
    );
    insert inboundSchedule;
    ConnectorExecutionRequest inboundRequest = registerOperation('Inbound');
    inboundRequest.scheduleId = inboundSchedule.Id;
    inboundRequest.leaseToken = 'stale-inbound-lease';
    ConnectorInboundBatch inboundBatch = new ConnectorInboundBatch(
      inboundRequest
    );
    System.assertEquals(false, inboundBatch.start(null).iterator().hasNext());
    inboundBatch.finish(null);
    System.assertEquals('Claimed', scheduleById(inboundSchedule.Id).Status__c);

    Scheduled_Integration_Job__c outboundSchedule = claimedSchedule(
      'current-outbound-lease'
    );
    insert outboundSchedule;
    ConnectorExecutionRequest outboundRequest = registerOperation('Outbound');
    outboundRequest.scheduleId = outboundSchedule.Id;
    outboundRequest.leaseToken = 'stale-outbound-lease';
    outboundRequest.initialSync = true;
    ConnectorOutboundBatch outboundBatch = new ConnectorOutboundBatch(
      outboundRequest
    );
    outboundBatch.start(null);
    outboundBatch.finish(null);
    System.assertEquals('Claimed', scheduleById(outboundSchedule.Id).Status__c);
  }

  @IsTest
  static void outboundBatchExecutesValidatedScopeAndCompletes() {
    Account accountValue = new Account(Name = 'Shared outbound test');
    insert accountValue;

    ConnectorExecutionRequest request = registerOperation('Outbound');
    request.recordIds.add(accountValue.Id);
    request.leaseToken = 'lease-outbound';
    Scheduled_Integration_Job__c schedule = claimedSchedule(request.leaseToken);
    insert schedule;
    request.scheduleId = schedule.Id;

    ConnectorExecutionResult executorResult = ConnectorExecutionResult.success();
    executorResult.processedCount = 1;
    executorResult.successfulCount = 1;
    ConnectorExecutionService.registerTestExecutor(
      request,
      new StubExecutor(null, executorResult)
    );

    ConnectorOutboundBatch batchValue = new ConnectorOutboundBatch(request);
    System.assertNotEquals(null, batchValue.start(null));
    batchValue.execute(null, new List<SObject>{ accountValue });
    batchValue.finish(null);

    Scheduled_Integration_Job__c completed = scheduleById(schedule.Id);
    System.assertEquals('Ready', completed.Status__c);
    System.assertEquals(null, completed.Last_Error__c);
  }

  @IsTest
  static void outboundRetryLimitFailsWithoutReplayingSuccessfulRecords() {
    Account accountValue = new Account(Name = 'Shared retry test');
    insert accountValue;

    ConnectorExecutionRequest request = registerOperation('Outbound');
    request.recordIds.add(accountValue.Id);
    request.retryAttempt = 5;
    request.leaseToken = 'lease-retry';
    Scheduled_Integration_Job__c schedule = claimedSchedule(request.leaseToken);
    insert schedule;
    request.scheduleId = schedule.Id;

    ConnectorExecutionResult executorResult = ConnectorExecutionResult.failed(
      'rate limited',
      true,
      60
    );
    executorResult.retryRecordIds.add(accountValue.Id);
    ConnectorExecutionService.registerTestExecutor(
      request,
      new StubExecutor(null, executorResult)
    );

    ConnectorOutboundBatch batchValue = new ConnectorOutboundBatch(request);
    batchValue.start(null);
    batchValue.execute(null, new List<SObject>{ accountValue });
    batchValue.finish(null);

    Scheduled_Integration_Job__c failed = scheduleById(schedule.Id);
    System.assertEquals('Failed', failed.Status__c);
    System.assert(failed.Last_Error__c.contains('retry attempts'));
  }

  @IsTest
  static void outboundBatchCapturesInvalidAndPermanentFailures() {
    ConnectorOutboundBatch invalidBatch = new ConnectorOutboundBatch(null);
    System.assertNotEquals(null, invalidBatch.start(null));
    invalidBatch.execute(null, new List<SObject>());
    invalidBatch.finish(null);

    Account accountValue = new Account(Name = 'Shared permanent failure');
    insert accountValue;
    ConnectorExecutionRequest request = registerOperation('Outbound');
    request.recordIds.add(accountValue.Id);
    request.leaseToken = 'lease-permanent';
    Scheduled_Integration_Job__c schedule = claimedSchedule(request.leaseToken);
    insert schedule;
    request.scheduleId = schedule.Id;

    ConnectorExecutionService.registerTestExecutor(
      request,
      new StubExecutor(null, null).throwOutboundException()
    );
    ConnectorOutboundBatch exceptionBatch = new ConnectorOutboundBatch(request);
    exceptionBatch.start(null);
    exceptionBatch.execute(null, new List<SObject>{ accountValue });
    exceptionBatch.finish(null);
    System.assertEquals('Failed', scheduleById(schedule.Id).Status__c);
  }

  @IsTest
  static void outboundBatchSchedulesOnlyExplicitRetryIds() {
    Account firstAccount = new Account(Name = 'Explicit retry one');
    Account secondAccount = new Account(Name = 'Successful record');
    insert new List<Account>{ firstAccount, secondAccount };

    ConnectorExecutionRequest request = registerOperation('Outbound');
    request.recordIds.add(firstAccount.Id);
    request.recordIds.add(secondAccount.Id);
    request.scopeSize = 500;
    request.leaseToken = 'lease-explicit-retry';
    Scheduled_Integration_Job__c schedule = claimedSchedule(request.leaseToken);
    insert schedule;
    request.scheduleId = schedule.Id;

    ConnectorExecutionResult retryResult = ConnectorExecutionResult.failed(
      'retry this record',
      true,
      1
    );
    retryResult.retryRecordIds.add(firstAccount.Id);
    ConnectorExecutionService.registerTestExecutor(
      request,
      new StubExecutor(null, retryResult)
    );

    ConnectorOutboundBatch batchValue = new ConnectorOutboundBatch(request);
    batchValue.start(null);
    batchValue.execute(null, new List<SObject>{ firstAccount, secondAccount });
    batchValue.finish(null);

    Scheduled_Integration_Job__c running = scheduleById(schedule.Id);
    System.assertEquals('Running', running.Status__c);
    System.assertEquals('lease-explicit-retry', running.Lease_Token__c);
  }

  private static ConnectorExecutionRequest registerOperation(String direction) {
    ConnectorOperationRegistry.OperationDefinition definition = new ConnectorOperationRegistry.OperationDefinition();
    definition.connectorKey = 'qbo';
    definition.operationKey = 'SharedAccountSync';
    definition.direction = direction;
    definition.salesforceObject = 'Account';
    definition.externalEntity = 'Customer';
    ConnectorOperationRegistry.registerTestOperation(definition);

    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = 'qbo';
    request.operationKey = definition.operationKey;
    request.direction = direction;
    request.salesforceObject = 'Account';
    request.externalEntity = 'Customer';
    request.scopeSize = 10;
    return request;
  }

  private static Scheduled_Integration_Job__c claimedSchedule(
    String leaseToken
  ) {
    return new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = 'Shared Runtime ' + leaseToken,
      Scheduler_Name__c = 'Shared Runtime ' + leaseToken,
      Integration_Type__c = 'QuickBooks',
      Source_Object__c = 'Account',
      Direction__c = 'Inbound',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Claimed',
      Lease_Token__c = leaseToken,
      Lease_Expires_At__c = Datetime.now().addMinutes(5),
      Next_Run_At__c = Datetime.now().addMinutes(-1)
    );
  }

  private static Scheduled_Integration_Job__c scheduleById(Id scheduleId) {
    return [
      SELECT
        Status__c,
        Lease_Token__c,
        Lease_Expires_At__c,
        Last_Error__c,
        Next_Run_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :scheduleId
    ];
  }
}