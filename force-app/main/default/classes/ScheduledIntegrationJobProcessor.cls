public with sharing class ScheduledIntegrationJobProcessor implements Queueable, Database.AllowsCallouts {
    private Id scheduleId;

    public ScheduledIntegrationJobProcessor(Id scheduleId) {
        this.scheduleId = scheduleId;
    }

    public void execute(QueueableContext context) {
        Scheduled_Integration_Job__c job = [
            SELECT Id, Integration_Type__c, Source_Object__c, Direction__c
            FROM Scheduled_Integration_Job__c
            WHERE Id = :scheduleId
            LIMIT 1
        ];
        ScheduledOperationRouter.execute(job);
    }
}