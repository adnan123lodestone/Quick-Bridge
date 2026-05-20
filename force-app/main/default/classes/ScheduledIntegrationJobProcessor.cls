public with sharing class ScheduledIntegrationJobProcessor implements Queueable, Database.AllowsCallouts {
  private Id scheduleId;
  private String leaseToken;

  public ScheduledIntegrationJobProcessor(Id scheduleId) {
    this(scheduleId, null);
  }

  public ScheduledIntegrationJobProcessor(Id scheduleId, String leaseToken) {
    this.scheduleId = scheduleId;
    this.leaseToken = leaseToken;
  }

  public void execute(QueueableContext context) {
    List<Scheduled_Integration_Job__c> jobs = [
      SELECT
        Id,
        Integration_Type__c,
        Source_Object__c,
        Direction__c,
        Status__c,
        Lease_Token__c,
        Lease_Expires_At__c,
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
    if (String.isNotBlank(leaseToken)) {
      if (job.Status__c != 'Claimed' || job.Lease_Token__c != leaseToken) {
        return;
      }
    } else if (!GenericScheduleDispatcher.isRunnableStatus(job.Status__c)) {
      return;
    } else {
      leaseToken =
        'legacy-' +
        String.valueOf(job.Id) +
        '-' +
        String.valueOf(Datetime.now().getTime());
      job.Lease_Token__c = leaseToken;
      job.Lease_Expires_At__c = GenericScheduleDispatcher.leaseExpiresAt(
        Datetime.now()
      );
    }

    try {
      ScheduledOperationRouter.execute(job);
      GenericScheduleDispatcher.completeRun(scheduleId, leaseToken, true, null);
    } catch (Exception e) {
      GenericScheduleDispatcher.completeRun(
        scheduleId,
        leaseToken,
        false,
        e.getMessage()
      );
    }
  }
}