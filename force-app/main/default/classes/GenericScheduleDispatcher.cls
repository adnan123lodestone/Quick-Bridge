global with sharing class GenericScheduleDispatcher implements Schedulable {
  private static final Integer DEFAULT_LEASE_MINUTES = 10;

  global void execute(SchedulableContext context) {
    dispatchDue();
  }

  public static void dispatchDue() {
    Datetime nowValue = Datetime.now();
    String leaseToken = generateLeaseToken();
    Datetime leaseExpiresAt = nowValue.addMinutes(DEFAULT_LEASE_MINUTES);
    List<Scheduled_Integration_Job__c> dueJobs = [
      SELECT
        Id,
        Integration_Type__c,
        Source_Object__c,
        Direction__c,
        Frequency_Value__c,
        Frequency_Type__c,
        Logical_Job_Key__c,
        Next_Run_At__c,
        Status__c,
        Lease_Token__c,
        Lease_Expires_At__c
      FROM Scheduled_Integration_Job__c
      WHERE
        (Status__c IN ('Ready', 'Active')
        AND (Next_Run_At__c = NULL
        OR Next_Run_At__c <= :nowValue))
        OR (Status__c = 'Claimed'
        AND Lease_Expires_At__c < :nowValue)
      LIMIT 20
      FOR UPDATE
    ];
    if (dueJobs.isEmpty()) {
      return;
    }

    for (Scheduled_Integration_Job__c job : dueJobs) {
      job.Status__c = 'Claimed';
      job.Lease_Token__c = leaseToken;
      job.Lease_Expires_At__c = leaseExpiresAt;
      job.Last_Claimed_At__c = nowValue;
      job.Last_Run_At__c = nowValue;
    }
    update dueJobs;

    List<Scheduled_Integration_Job__c> processorUpdates = new List<Scheduled_Integration_Job__c>();
    for (Scheduled_Integration_Job__c job : dueJobs) {
      Id processorJobId = System.enqueueJob(
        new ScheduledIntegrationJobProcessor(job.Id, leaseToken)
      );
      processorUpdates.add(
        new Scheduled_Integration_Job__c(
          Id = job.Id,
          Processor_Job_Id__c = String.valueOf(processorJobId)
        )
      );
    }
    update processorUpdates;
  }

  private static String generateLeaseToken() {
    String seed =
      UserInfo.getOrganizationId() +
      ':' +
      UserInfo.getUserId() +
      ':' +
      String.valueOf(Datetime.now().getTime()) +
      ':' +
      String.valueOf(Math.random());
    return EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(seed))
      )
      .substring(0, 64);
  }

  public static Boolean isRunnableStatus(String statusValue) {
    return statusValue == 'Ready' || statusValue == 'Active';
  }

  public static Datetime leaseExpiresAt(Datetime baseTime) {
    return (baseTime == null ? Datetime.now() : baseTime)
      .addMinutes(DEFAULT_LEASE_MINUTES);
  }

  public static void completeRun(
    Id scheduleId,
    String leaseToken,
    Boolean success,
    String errorMessage
  ) {
    Datetime nowValue = Datetime.now();
    List<Scheduled_Integration_Job__c> jobs = [
      SELECT
        Id,
        Status__c,
        Lease_Token__c,
        Frequency_Value__c,
        Frequency_Type__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :scheduleId
      LIMIT 1
      FOR UPDATE
    ];
    if (jobs.isEmpty()) {
      return;
    }

    Scheduled_Integration_Job__c job = jobs[0];
    if (job.Status__c != 'Claimed' && job.Status__c != 'Running') {
      return;
    }
    if (job.Lease_Token__c != leaseToken) {
      return;
    }

    job.Lease_Token__c = null;
    job.Lease_Expires_At__c = null;
    if (success) {
      job.Status__c = 'Ready';
      job.Last_Dispatched_At__c = nowValue;
      job.Last_Run_At__c = nowValue;
      job.Last_Error__c = null;
      job.Next_Run_At__c = SchedulerEntitlementService.calculateNextRun(
        job.Frequency_Value__c,
        job.Frequency_Type__c,
        nowValue
      );
    } else {
      job.Status__c = 'Failed';
      job.Last_Error__c = String.isBlank(errorMessage)
        ? 'Scheduled operation failed.'
        : errorMessage.left(32768);
    }
    update job;
  }
}