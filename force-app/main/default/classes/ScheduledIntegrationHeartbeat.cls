global with sharing class ScheduledIntegrationHeartbeat implements Schedulable {
    public static final String JOB_NAME = 'QuickBridge Integration Heartbeat';

    global void execute(SchedulableContext context) {
        dispatchDueSchedules();
    }

    public static void ensureScheduled() {
        if (Test.isRunningTest()) {
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
            System.schedule(JOB_NAME, '0 0/5 * * * ?', new ScheduledIntegrationHeartbeat());
        }
    }

    public static void dispatchDueSchedules() {
        Datetime nowValue = Datetime.now();
        List<Scheduled_Integration_Job__c> dueJobs = [
            SELECT Id, Integration_Type__c, Source_Object__c, Frequency_Value__c, Frequency_Type__c,
                Logical_Job_Key__c, Direction__c, Next_Run_At__c
            FROM Scheduled_Integration_Job__c
            WHERE Status__c = 'Active'
            AND (Next_Run_At__c = null OR Next_Run_At__c <= :nowValue)
            ORDER BY Next_Run_At__c ASC
            LIMIT 20
        ];
        for (Scheduled_Integration_Job__c job : dueJobs) {
            Id processorJobId = System.enqueueJob(new ScheduledIntegrationJobProcessor(job.Id));
            job.Processor_Job_Id__c = String.valueOf(processorJobId);
            job.Last_Run_At__c = nowValue;
            job.Next_Run_At__c = SchedulerEntitlementService.calculateNextRun(job.Frequency_Value__c, job.Frequency_Type__c, nowValue);
        }
        if (!dueJobs.isEmpty()) {
            update dueJobs;
        }
    }
}