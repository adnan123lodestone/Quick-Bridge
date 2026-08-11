@IsTest
private class ConnectorAsyncJobMonitorTest {
  @IsTest
  static void failedOrErroredChildrenFailTheLogicalRun() {
    Id jobId = Id.valueOf('707000000000001AAA');
    ConnectorAsyncJobMonitor.PollDecision failed = ConnectorAsyncJobMonitor.evaluateSnapshots(
      new List<ConnectorAsyncJobMonitor.JobSnapshot>{
        new ConnectorAsyncJobMonitor.JobSnapshot(
          jobId,
          'Failed',
          1,
          'Provider child failed.'
        )
      },
      true
    );
    Assert.isTrue(failed.failed);
    Assert.isFalse(failed.complete);
    Assert.isTrue(failed.errorMessage.contains('Provider child failed'));

    ConnectorAsyncJobMonitor.PollDecision completedWithErrors = ConnectorAsyncJobMonitor.evaluateSnapshots(
      new List<ConnectorAsyncJobMonitor.JobSnapshot>{
        new ConnectorAsyncJobMonitor.JobSnapshot(jobId, 'Completed', 2, null)
      },
      true
    );
    Assert.isTrue(completedWithErrors.failed);
  }

  @IsTest
  static void everyDiscoveredDescendantMustCompleteCleanly() {
    ConnectorAsyncJobMonitor.PollDecision pending = ConnectorAsyncJobMonitor.evaluateSnapshots(
      new List<ConnectorAsyncJobMonitor.JobSnapshot>{
        snapshot('707000000000001AAA', 'Completed'),
        snapshot('707000000000002AAA', 'Processing')
      },
      true
    );
    Assert.isFalse(pending.complete);
    Assert.isFalse(pending.failed);

    ConnectorAsyncJobMonitor.PollDecision complete = ConnectorAsyncJobMonitor.evaluateSnapshots(
      new List<ConnectorAsyncJobMonitor.JobSnapshot>{
        snapshot('707000000000001AAA', 'Completed'),
        snapshot('707000000000002AAA', 'Completed')
      },
      true
    );
    Assert.isTrue(complete.complete);
    Assert.isFalse(complete.failed);

    ConnectorAsyncJobMonitor.PollDecision overflow = ConnectorAsyncJobMonitor.evaluateSnapshots(
      new List<ConnectorAsyncJobMonitor.JobSnapshot>(),
      false
    );
    Assert.isTrue(overflow.failed);
  }

  @IsTest
  static void staleLeaseMonitorIsANoOp() {
    Assert.areEqual(
      0,
      ConnectorAsyncJobMonitor.directProviderChildren(null).size()
    );
    Scheduled_Integration_Job__c schedule = runningSchedule(
      'Async Monitor Stale Lease',
      'current-token'
    );
    insert schedule;

    new ConnectorAsyncJobMonitor(
        schedule.Id,
        'stale-token',
        Id.valueOf('707000000000001AAA'),
        Datetime.now(),
        0
      )
      .execute(null);

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
  static void pollingWindowIsBounded() {
    Datetime nowValue = Datetime.now();
    Assert.isFalse(ConnectorAsyncJobMonitor.hasTimedOut(nowValue, 0, nowValue));
    Assert.isTrue(
      ConnectorAsyncJobMonitor.hasTimedOut(
        nowValue.addMinutes(-181),
        1,
        nowValue
      )
    );
    Assert.isTrue(
      ConnectorAsyncJobMonitor.hasTimedOut(nowValue, 120, nowValue)
    );
  }

  @IsTest
  static void timedOutPendingMonitorFailsLogicalSchedule() {
    Scheduled_Integration_Job__c schedule = runningSchedule(
      'Async Monitor Bounded Timeout',
      'timeout-token'
    );
    insert schedule;

    new ConnectorAsyncJobMonitor(
        schedule.Id,
        'timeout-token',
        Id.valueOf('707000000000001AAA'),
        Datetime.now().addMinutes(-181),
        1
      )
      .execute(null);

    Scheduled_Integration_Job__c failed = [
      SELECT Status__c, Lease_Token__c, Last_Error__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Failed', failed.Status__c);
    Assert.isNull(failed.Lease_Token__c);
    Assert.isTrue(failed.Last_Error__c.contains('bounded monitoring window'));
  }

  @IsTest
  static void pendingMonitorRenewsLeaseAndEnqueuesBoundedPoll() {
    Scheduled_Integration_Job__c schedule = runningSchedule(
      'Async Monitor Pending Poll',
      'pending-token'
    );
    insert schedule;

    new ConnectorAsyncJobMonitor(
        schedule.Id,
        'pending-token',
        Id.valueOf('707000000000001AAA'),
        Datetime.now(),
        0
      )
      .execute(null);

    Scheduled_Integration_Job__c pending = [
      SELECT
        Status__c,
        Lease_Token__c,
        Processor_Job_Id__c,
        Lease_Expires_At__c,
        Last_Dispatched_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual('Running', pending.Status__c);
    Assert.areEqual('pending-token', pending.Lease_Token__c);
    Assert.isNotNull(pending.Processor_Job_Id__c);
    Assert.isTrue(pending.Lease_Expires_At__c > System.now());
    Assert.isNull(pending.Last_Dispatched_At__c);
  }

  private static ConnectorAsyncJobMonitor.JobSnapshot snapshot(
    String jobId,
    String status
  ) {
    return new ConnectorAsyncJobMonitor.JobSnapshot(
      Id.valueOf(jobId),
      status,
      0,
      null
    );
  }

  private static Scheduled_Integration_Job__c runningSchedule(
    String logicalKey,
    String leaseToken
  ) {
    return new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = logicalKey,
      Scheduler_Name__c = logicalKey,
      Integration_Type__c = 'Noop',
      Source_Object__c = 'Account',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Running',
      Next_Run_At__c = System.now().addMinutes(-1),
      Created_DateTime__c = System.now(),
      Lease_Token__c = leaseToken,
      Lease_Expires_At__c = System.now().addMinutes(5)
    );
  }
}
