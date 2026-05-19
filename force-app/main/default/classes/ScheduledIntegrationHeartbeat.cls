global with sharing class ScheduledIntegrationHeartbeat implements Schedulable {
    public static final String JOB_NAME = 'QuickBridge Integration Heartbeat';
    @TestVisible private static Boolean skipSchedulingForTests = true;

    global void execute(SchedulableContext context) {
        GenericScheduleDispatcher.dispatchDue();
    }

    public static void ensureScheduled() {
        if (Test.isRunningTest() && skipSchedulingForTests == true) {
            return;
        }
        List<CronTrigger> existing = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            AND State NOT IN ('DELETED', 'COMPLETE', 'ERROR')
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            System.schedule(JOB_NAME, '0 0 * * * ?', new ScheduledIntegrationHeartbeat());
        }
    }

    public static void dispatchDueSchedules() {
        GenericScheduleDispatcher.dispatchDue();
    }
}
