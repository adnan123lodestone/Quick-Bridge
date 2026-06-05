global with sharing class ScheduledIntegrationHeartbeat implements Schedulable {
  public static final String JOB_NAME = 'QuickBridge Integration Heartbeat';
  private static final Integer INTERVAL_MINUTES = 1;

  @TestVisible
  private static Boolean skipSchedulingForTests = true;

  global void execute(SchedulableContext context) {
    try {
      GenericScheduleDispatcher.dispatchDue();
    } catch (Exception e) {
      ErrorLogUtility.logException(
        'QuickBridge',
        'ScheduledIntegrationHeartbeat.execute',
        e,
        null,
        null
      );
    } finally {
      System.abortJob(context.getTriggerId());
      scheduleNextRun();
    }
  }

  public static void ensureScheduled() {
    if (Test.isRunningTest() && skipSchedulingForTests == true) {
      return;
    }
    List<CronTrigger> existing = [
      SELECT Id
      FROM CronTrigger
      WHERE
        CronJobDetail.Name = :JOB_NAME
        AND State NOT IN ('DELETED', 'COMPLETE', 'ERROR')
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      scheduleNextRun();
    }
  }

  public static void dispatchDueSchedules() {
    GenericScheduleDispatcher.dispatchDue();
  }

  private static void scheduleNextRun() {
    DateTime nextRun = DateTime.now().addMinutes(INTERVAL_MINUTES);
    String cronExp = nextRun.format('s m H d M ? yyyy');
    System.schedule(JOB_NAME, cronExp, new ScheduledIntegrationHeartbeat());
  }
}