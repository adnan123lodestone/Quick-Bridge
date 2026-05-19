global with sharing class GenericScheduleDispatcher implements Schedulable {
    global void execute(SchedulableContext context) {
        dispatchDue();
    }

    public static void dispatchDue() {
        Datetime nowValue = Datetime.now();
        List<Scheduled_Integration_Job__c> dueJobs = [
            SELECT Id, Integration_Type__c, Source_Object__c, Direction__c, Frequency_Value__c, Frequency_Type__c,
                Logical_Job_Key__c, Next_Run_At__c
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
