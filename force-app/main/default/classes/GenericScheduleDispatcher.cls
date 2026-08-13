global with sharing class GenericScheduleDispatcher implements Schedulable {
  private static final Integer DEFAULT_LEASE_MINUTES = 10;
  private static final Integer MAX_DISPATCH_SIZE = 20;

  global void execute(SchedulableContext context) {
    dispatchDue();
  }

  public static void dispatchDue() {
    Integer availableQueueableJobs =
      Limits.getLimitQueueableJobs() - Limits.getQueueableJobs();
    dispatchDue(availableQueueableJobs);
  }

  @TestVisible
  private static void dispatchDue(Integer availableQueueableJobs) {
    if (availableQueueableJobs <= 0) {
      return;
    }

    Integer dispatchSize = Math.min(MAX_DISPATCH_SIZE, availableQueueableJobs);
    Datetime nowValue = Datetime.now();
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
        OR (Status__c IN ('Claimed', 'Running')
        AND Lease_Expires_At__c < :nowValue)
      LIMIT :dispatchSize
      FOR UPDATE
    ];
    if (dueJobs.isEmpty()) {
      return;
    }

    for (Scheduled_Integration_Job__c job : dueJobs) {
      job.Status__c = 'Claimed';
      job.Lease_Token__c = generateLeaseToken();
      job.Lease_Expires_At__c = leaseExpiresAt;
      job.Last_Claimed_At__c = nowValue;
      job.Last_Run_At__c = nowValue;
    }
    update dueJobs;

    for (Scheduled_Integration_Job__c job : dueJobs) {
      try {
        Id processorJobId = System.enqueueJob(
          new ScheduledIntegrationJobProcessor(job.Id, job.Lease_Token__c)
        );
        job.Processor_Job_Id__c = String.valueOf(processorJobId);
      } catch (Exception enqueueException) {
        job.Status__c = 'Failed';
        job.Lease_Token__c = null;
        job.Lease_Expires_At__c = null;
        job.Processor_Job_Id__c = null;
        job.Last_Error__c = boundedError(
          'Unable to enqueue the scheduled operation: ' +
          enqueueException.getMessage()
        );
      }
    }
    update dueJobs;
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

  private static String boundedError(String message) {
    return String.isBlank(message)
      ? 'Scheduled operation failed.'
      : message.left(32768);
  }
}