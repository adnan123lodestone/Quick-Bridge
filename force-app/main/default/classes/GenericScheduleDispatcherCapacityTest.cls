@IsTest
private class GenericScheduleDispatcherCapacityTest {
  private class SynchronousTestAdapter implements ScheduledOperationAdapter {
    public void execute(Scheduled_Integration_Job__c job) {}
  }

  private class DeferredTestAdapter
    implements ScheduledOperationAdapter, DeferredScheduledOperationAdapter {
    private ConnectorScheduleDispatchResult dispatchResult;

    DeferredTestAdapter(ConnectorScheduleDispatchResult dispatchResult) {
      this.dispatchResult = dispatchResult;
    }

    public void execute(Scheduled_Integration_Job__c job) {}

    public ConnectorScheduleDispatchResult dispatch(
      Scheduled_Integration_Job__c job,
      String leaseToken
    ) {
      return dispatchResult;
    }
  }

  private class ThrowingTestAdapter implements ScheduledOperationAdapter {
    public void execute(Scheduled_Integration_Job__c job) {
      throw new SchedulerTestException('Expected adapter exception.');
    }
  }

  private class SchedulerTestException extends Exception {}

  @IsTest
  static void dispatchesMultipleDueSchedulesWhenCapacityExists() {
    insert new List<Scheduled_Integration_Job__c>{
      dueNoopSchedule(
        'Noop Scheduled Context - Older',
        System.now().addMinutes(-2)
      ),
      dueNoopSchedule(
        'Noop Scheduled Context - Newer',
        System.now().addMinutes(-1)
      )
    };

    Test.startTest();
    GenericScheduleDispatcher.dispatchDue();

    List<Scheduled_Integration_Job__c> dispatched = [
      SELECT Processor_Job_Id__c
      FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c LIKE 'Noop Scheduled Context%'
    ];
    Assert.areEqual(2, dispatched.size());
    for (Scheduled_Integration_Job__c job : dispatched) {
      Assert.isNotNull(
        job.Processor_Job_Id__c,
        'The dispatcher should enqueue every due schedule within the available capacity.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void limitsClaimsToAvailableQueueableCapacity() {
    insert new List<Scheduled_Integration_Job__c>{
      dueNoopSchedule(
        'Noop Queueable Context - Older',
        System.now().addMinutes(-2)
      ),
      dueNoopSchedule(
        'Noop Queueable Context - Newer',
        System.now().addMinutes(-1)
      )
    };

    Test.startTest();
    GenericScheduleDispatcher.dispatchDue(1);

    Integer dispatchedCount = 0;
    Integer readyCount = 0;
    for (Scheduled_Integration_Job__c job : [
      SELECT Processor_Job_Id__c, Status__c
      FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c LIKE 'Noop Queueable Context%'
    ]) {
      if (job.Processor_Job_Id__c != null) {
        dispatchedCount++;
      } else if (job.Status__c == 'Ready') {
        readyCount++;
      }
    }
    Assert.areEqual(1, dispatchedCount);
    Assert.areEqual(1, readyCount);
    Test.stopTest();
  }

  @IsTest
  static void zeroQueueableCapacityLeavesScheduleReady() {
    insert dueNoopSchedule(
      'Noop Exhausted Queueable Context',
      System.now().addMinutes(-1)
    );

    Test.startTest();
    GenericScheduleDispatcher.dispatchDue(0);

    Scheduled_Integration_Job__c untouched = [
      SELECT Processor_Job_Id__c, Status__c, Lease_Token__c
      FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c = 'Noop Exhausted Queueable Context'
      LIMIT 1
    ];
    Assert.isNull(untouched.Processor_Job_Id__c);
    Assert.areEqual('Ready', untouched.Status__c);
    Assert.isNull(untouched.Lease_Token__c);
    Test.stopTest();
  }

  @IsTest
  static void reclaimsExpiredRunningSchedule() {
    Scheduled_Integration_Job__c schedule = dueNoopSchedule(
      'Noop Expired Running Context',
      System.now().addMinutes(-20)
    );
    schedule.Status__c = 'Running';
    schedule.Lease_Token__c = 'expired-running-token';
    schedule.Lease_Expires_At__c = System.now().addMinutes(-10);
    insert schedule;

    Test.startTest();
    GenericScheduleDispatcher.dispatchDue(1);
    Scheduled_Integration_Job__c reclaimed = [
      SELECT Status__c, Lease_Token__c, Lease_Expires_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Claimed', reclaimed.Status__c);
    Assert.areNotEqual(
      'expired-running-token',
      reclaimed.Lease_Token__c,
      'A reclaimed run must receive a new token so the stale child cannot complete it.'
    );
    Assert.isTrue(reclaimed.Lease_Expires_At__c > System.now());
    Test.stopTest();
  }

  @IsTest
  static void staleLeaseCannotCompleteNewerRun() {
    Scheduled_Integration_Job__c schedule = dueNoopSchedule(
      'Noop Stale Completion Context',
      System.now().addMinutes(-1)
    );
    schedule.Status__c = 'Running';
    schedule.Lease_Token__c = 'current-token';
    schedule.Lease_Expires_At__c = System.now().addMinutes(5);
    insert schedule;

    GenericScheduleDispatcher.completeRun(
      schedule.Id,
      'stale-token',
      true,
      null
    );

    Scheduled_Integration_Job__c unchanged = [
      SELECT Status__c, Lease_Token__c, Last_Dispatched_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Running', unchanged.Status__c);
    Assert.areEqual('current-token', unchanged.Lease_Token__c);
    Assert.isNull(unchanged.Last_Dispatched_At__c);
  }

  @IsTest
  static void scheduleResultContractsAreBoundedAndComposable() {
    ConnectorScheduleDispatchResult synchronousResult =
      ConnectorScheduleDispatchResult.synchronous();
    Assert.isFalse(synchronousResult.ownershipTransferred);
    Assert.isFalse(synchronousResult.hasFailed());
    Assert.isTrue(
      ConnectorScheduleDispatchResult.deferred(null).hasFailed()
    );
    Assert.isTrue(ConnectorScheduleDispatchResult.failed(null).hasFailed());

    ConnectorExecutionResult aggregate = ConnectorExecutionResult.success();
    aggregate.processedCount = 1;
    aggregate.successfulCount = 1;
    ConnectorExecutionResult failure = ConnectorExecutionResult.failed(
      'authorization: Bearer secret-value',
      true,
      90000
    );
    failure.retryRecordIds.add(UserInfo.getUserId());
    aggregate.mergeFrom(failure);

    Assert.areEqual(2, aggregate.processedCount);
    Assert.areEqual(1, aggregate.failedCount);
    Assert.areEqual(86400, aggregate.retryDelaySeconds);
    Assert.isTrue(aggregate.retryable);
    Assert.isTrue(aggregate.hasFailures());
    Assert.isFalse(aggregate.errorSummary.contains('secret-value'));
    Assert.areEqual(1, aggregate.retryRecordIds.size());
    Assert.isNull(ConnectorExecutionResult.sanitizeError(null));
  }

  @IsTest
  static void scheduleServiceHandlesInvalidAndTerminalResults() {
    Assert.isFalse(ConnectorScheduleService.markRunning(null, null, null));
    ConnectorScheduleService.completeSuccess(null, null);
    ConnectorScheduleService.completeFailure(null, null, null);

    Scheduled_Integration_Job__c successfulSchedule = dueNoopSchedule(
      'Noop Service Success Context',
      System.now().addMinutes(-1)
    );
    successfulSchedule.Status__c = 'Claimed';
    successfulSchedule.Lease_Token__c = 'service-success-token';
    successfulSchedule.Lease_Expires_At__c = System.now().addMinutes(5);
    insert successfulSchedule;
    Assert.isFalse(
      ConnectorScheduleService.markRunning(
        successfulSchedule.Id,
        'stale-token',
        null
      )
    );
    Assert.isTrue(
      ConnectorScheduleService.markRunning(
        successfulSchedule.Id,
        'service-success-token',
        UserInfo.getUserId()
      )
    );
    ConnectorScheduleService.complete(
      successfulSchedule.Id,
      'service-success-token',
      ConnectorExecutionResult.success()
    );
    Assert.areEqual(
      'Ready',
      [
        SELECT Status__c
        FROM Scheduled_Integration_Job__c
        WHERE Id = :successfulSchedule.Id
      ].Status__c
    );

    Scheduled_Integration_Job__c failedSchedule = dueNoopSchedule(
      'Noop Service Failure Context',
      System.now().addMinutes(-1)
    );
    failedSchedule.Status__c = 'Claimed';
    failedSchedule.Lease_Token__c = 'service-failure-token';
    failedSchedule.Lease_Expires_At__c = System.now().addMinutes(5);
    insert failedSchedule;
    ConnectorScheduleService.complete(
      failedSchedule.Id,
      'service-failure-token',
      null
    );
    Assert.areEqual(
      'Failed',
      [
        SELECT Status__c
        FROM Scheduled_Integration_Job__c
        WHERE Id = :failedSchedule.Id
      ].Status__c
    );
  }

  @IsTest
  static void legacyAdapterCompletesSynchronously() {
    Scheduled_Integration_Job__c schedule = dueNoopSchedule(
      'Noop Legacy Adapter Context',
      System.now().addMinutes(-1)
    );
    schedule.Status__c = 'Claimed';
    schedule.Lease_Token__c = 'legacy-adapter-token';
    schedule.Lease_Expires_At__c = System.now().addMinutes(5);
    insert schedule;
    ScheduledOperationRouter.testAdapter = new SynchronousTestAdapter();

    new ScheduledIntegrationJobProcessor(
      schedule.Id,
      'legacy-adapter-token'
    ).execute(null);

    Scheduled_Integration_Job__c completed = [
      SELECT Status__c, Lease_Token__c, Next_Run_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Ready', completed.Status__c);
    Assert.isNull(completed.Lease_Token__c);
    Assert.isNotNull(completed.Next_Run_At__c);
  }

  @IsTest
  static void legacyAsyncChildrenTransferOwnershipToMonitor() {
    Scheduled_Integration_Job__c schedule = dueNoopSchedule(
      'Noop Legacy Async Child Context',
      System.now().addMinutes(-1)
    );
    schedule.Status__c = 'Claimed';
    schedule.Lease_Token__c = 'legacy-child-token';
    schedule.Lease_Expires_At__c = System.now().addMinutes(5);
    insert schedule;

    new ScheduledIntegrationJobProcessor(
      schedule.Id,
      'legacy-child-token'
    ).completeOrMonitorLegacyChildren(
      schedule,
      false,
      Id.valueOf('707000000000001AAA'),
      new List<AsyncApexJob>{ new AsyncApexJob() }
    );

    Scheduled_Integration_Job__c running = [
      SELECT Status__c, Lease_Token__c, Processor_Job_Id__c,
        Lease_Expires_At__c, Last_Dispatched_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Running', running.Status__c);
    Assert.areEqual('legacy-child-token', running.Lease_Token__c);
    Assert.isNotNull(running.Processor_Job_Id__c);
    Assert.isTrue(running.Lease_Expires_At__c > System.now());
    Assert.isNull(running.Last_Dispatched_At__c);
  }

  @IsTest
  static void legacyExecuteEntryPointRemainsAvailable() {
    ScheduledOperationRouter.testAdapter = new SynchronousTestAdapter();
    ScheduledOperationRouter.execute(
      dueNoopSchedule('Noop Router Compatibility Context', System.now())
    );
  }

  @IsTest
  static void missingAdapterFailsClosed() {
    ScheduledOperationRouter.testAdapter = null;
    ConnectorScheduleDispatchResult result = ScheduledOperationRouter.dispatch(
      dueNoopSchedule('Noop Missing Adapter Context', System.now()),
      'noop-token'
    );
    Assert.isFalse(result.ownershipTransferred);
    Assert.isTrue(result.hasFailed());
    Assert.isTrue(result.errorMessage.contains('No scheduled operation adapter'));

    Scheduled_Integration_Job__c schedule = dueNoopSchedule(
      'Noop Missing Adapter Terminal Context',
      System.now().addMinutes(-1)
    );
    schedule.Status__c = 'Claimed';
    schedule.Lease_Token__c = 'missing-adapter-token';
    schedule.Lease_Expires_At__c = System.now().addMinutes(5);
    insert schedule;

    new ScheduledIntegrationJobProcessor(
      schedule.Id,
      'missing-adapter-token'
    ).execute(null);

    Scheduled_Integration_Job__c failedSchedule = [
      SELECT Status__c, Lease_Token__c, Last_Error__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Failed', failedSchedule.Status__c);
    Assert.isNull(failedSchedule.Lease_Token__c);
    Assert.isTrue(
      failedSchedule.Last_Error__c.contains(
        'No scheduled operation adapter'
      )
    );
  }

  @IsTest
  static void deferredAdapterTransfersTerminalOwnership() {
    Scheduled_Integration_Job__c schedule = dueNoopSchedule(
      'Noop Deferred Adapter Context',
      System.now().addMinutes(-1)
    );
    schedule.Status__c = 'Claimed';
    schedule.Lease_Token__c = 'deferred-adapter-token';
    schedule.Lease_Expires_At__c = System.now().addMinutes(5);
    insert schedule;
    ScheduledOperationRouter.testAdapter = new DeferredTestAdapter(
      ConnectorScheduleDispatchResult.deferred(UserInfo.getUserId())
    );

    new ScheduledIntegrationJobProcessor(
      schedule.Id,
      'deferred-adapter-token'
    ).execute(null);

    Scheduled_Integration_Job__c running = [
      SELECT
        Status__c,
        Lease_Token__c,
        Lease_Expires_At__c,
        Processor_Job_Id__c,
        Last_Dispatched_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Running', running.Status__c);
    Assert.areEqual('deferred-adapter-token', running.Lease_Token__c);
    Assert.isTrue(running.Lease_Expires_At__c > System.now());
    Assert.areEqual(String.valueOf(UserInfo.getUserId()), running.Processor_Job_Id__c);
    Assert.isNull(
      running.Last_Dispatched_At__c,
      'A deferred run is not complete until its terminal async owner reports completion.'
    );
  }

  @IsTest
  static void deferredDispatchFailureMarksScheduleFailed() {
    Scheduled_Integration_Job__c schedule = dueNoopSchedule(
      'Noop Deferred Failure Context',
      System.now().addMinutes(-1)
    );
    schedule.Status__c = 'Claimed';
    schedule.Lease_Token__c = 'deferred-failure-token';
    schedule.Lease_Expires_At__c = System.now().addMinutes(5);
    insert schedule;
    ScheduledOperationRouter.testAdapter = new DeferredTestAdapter(
      ConnectorScheduleDispatchResult.failed('Child dispatch failed safely.')
    );

    new ScheduledIntegrationJobProcessor(
      schedule.Id,
      'deferred-failure-token'
    ).execute(null);

    Scheduled_Integration_Job__c failed = [
      SELECT Status__c, Lease_Token__c, Last_Error__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Failed', failed.Status__c);
    Assert.isNull(failed.Lease_Token__c);
    Assert.areEqual('Child dispatch failed safely.', failed.Last_Error__c);
  }

  @IsTest
  static void nullDeferredResultFailsClosed() {
    ScheduledOperationRouter.testAdapter = new DeferredTestAdapter(null);
    ConnectorScheduleDispatchResult result = ScheduledOperationRouter.dispatch(
      dueNoopSchedule('Noop Null Deferred Context', System.now()),
      'null-result-token'
    );
    Assert.isTrue(result.hasFailed());
    Assert.areEqual(
      'The scheduled operation adapter returned no dispatch result.',
      result.errorMessage
    );
  }

  @IsTest
  static void adapterExceptionMarksClaimedScheduleFailed() {
    Scheduled_Integration_Job__c schedule = dueNoopSchedule(
      'Noop Adapter Exception Context',
      System.now().addMinutes(-1)
    );
    schedule.Status__c = 'Claimed';
    schedule.Lease_Token__c = 'adapter-exception-token';
    schedule.Lease_Expires_At__c = System.now().addMinutes(5);
    insert schedule;
    ScheduledOperationRouter.testAdapter = new ThrowingTestAdapter();

    new ScheduledIntegrationJobProcessor(
      schedule.Id,
      'adapter-exception-token'
    ).execute(null);

    Scheduled_Integration_Job__c failed = [
      SELECT Status__c, Lease_Token__c, Last_Error__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Failed', failed.Status__c);
    Assert.isNull(failed.Lease_Token__c);
    Assert.areEqual('Expected adapter exception.', failed.Last_Error__c);
  }

  @IsTest
  static void legacyConstructorPersistsItsLeaseBeforeCompletion() {
    Scheduled_Integration_Job__c schedule = dueNoopSchedule(
      'Noop Direct Processor Context',
      System.now().addMinutes(-1)
    );
    insert schedule;
    ScheduledOperationRouter.testAdapter = new SynchronousTestAdapter();

    new ScheduledIntegrationJobProcessor(schedule.Id).execute(null);

    Scheduled_Integration_Job__c completed = [
      SELECT Status__c, Lease_Token__c, Last_Dispatched_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Ready', completed.Status__c);
    Assert.isNull(completed.Lease_Token__c);
    Assert.isNotNull(completed.Last_Dispatched_At__c);
  }

  private static Scheduled_Integration_Job__c dueNoopSchedule(
    String logicalKey,
    Datetime nextRunAt
  ) {
    return new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = logicalKey,
      Scheduler_Name__c = logicalKey,
      Integration_Type__c = 'Noop',
      Source_Object__c = 'Account',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Ready',
      Next_Run_At__c = nextRunAt,
      Created_DateTime__c = System.now()
    );
  }
}