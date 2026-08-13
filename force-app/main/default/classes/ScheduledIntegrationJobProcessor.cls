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
    Boolean legacyClaim = false;
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
      legacyClaim = true;
    }

    try {
      ConnectorScheduleDispatchResult dispatchResult =
        ScheduledOperationRouter.dispatch(job, leaseToken);
      if (dispatchResult == null) {
        persistLegacyClaim(job, legacyClaim);
        ConnectorScheduleService.completeFailure(
          scheduleId,
          leaseToken,
          'The scheduled operation returned no dispatch result.'
        );
      } else if (String.isNotBlank(dispatchResult.errorMessage)) {
        persistLegacyClaim(job, legacyClaim);
        ConnectorScheduleService.completeFailure(
          scheduleId,
          leaseToken,
          dispatchResult.errorMessage
        );
      } else if (dispatchResult.ownershipTransferred == true) {
        persistLegacyClaim(job, legacyClaim);
        if (
          !ConnectorScheduleService.markRunning(
            scheduleId,
            leaseToken,
            dispatchResult.asyncJobId
          )
        ) {
          ConnectorScheduleService.completeFailure(
            scheduleId,
            leaseToken,
            'Unable to transfer terminal ownership because the schedule lease changed.'
          );
        }
      } else {
        Id processorJobId = context == null ? null : context.getJobId();
        List<AsyncApexJob> childJobs =
          ConnectorAsyncJobMonitor.directProviderChildren(processorJobId);
        completeOrMonitorLegacyChildren(
          job,
          legacyClaim,
          processorJobId,
          childJobs
        );
      }
    } catch (Exception e) {
      try {
        persistLegacyClaim(job, legacyClaim);
        ConnectorScheduleService.completeFailure(
          scheduleId,
          leaseToken,
          e.getMessage()
        );
      } catch (Exception completionException) {
        System.debug(
          LoggingLevel.ERROR,
          'Unable to record scheduled operation failure for ' +
          scheduleId +
          ': ' +
          completionException.getMessage()
        );
      }
    }
  }

  @TestVisible
  private void completeOrMonitorLegacyChildren(
    Scheduled_Integration_Job__c job,
    Boolean legacyClaim,
    Id processorJobId,
    List<AsyncApexJob> childJobs
  ) {
    persistLegacyClaim(job, legacyClaim);
    if (childJobs == null || childJobs.isEmpty()) {
      ConnectorScheduleService.completeSuccess(scheduleId, leaseToken);
      return;
    }

    Id monitorJobId = System.enqueueJob(
      new ConnectorAsyncJobMonitor(
        scheduleId,
        leaseToken,
        processorJobId,
        Datetime.now(),
        0
      ),
      ConnectorAsyncJobMonitor.POLL_DELAY_MINUTES
    );
    if (
      !ConnectorScheduleService.markRunning(
        scheduleId,
        leaseToken,
        monitorJobId,
        ConnectorAsyncJobMonitor.POLL_DELAY_MINUTES * 60
      )
    ) {
      ConnectorScheduleService.completeFailure(
        scheduleId,
        leaseToken,
        'Unable to transfer terminal ownership to the legacy async monitor because the schedule lease changed.'
      );
    }
  }

  private void persistLegacyClaim(
    Scheduled_Integration_Job__c job,
    Boolean legacyClaim
  ) {
    if (legacyClaim != true) {
      return;
    }
    job.Status__c = 'Claimed';
    job.Lease_Token__c = leaseToken;
    job.Lease_Expires_At__c = GenericScheduleDispatcher.leaseExpiresAt(
      Datetime.now()
    );
    update job;
  }
}