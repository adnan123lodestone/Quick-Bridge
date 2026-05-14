public with sharing class FedExTrackingStatusBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id
            FROM FedEx_Shipment__c
            WHERE Master_Tracking_Number__c != null
            AND Is_Terminal__c = false
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        for (SObject row : scope) {
            FedExOperationsService.syncTrackingStatus((Id) row.get('Id'));
        }
    }

    public void finish(Database.BatchableContext context) {
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new FedExTrackingStatusBatch(), 10);
    }

    @AuraEnabled
    public static String scheduleHourly() {
        String jobName = 'FedEx Tracking Status Sync';
        for (CronTrigger triggerRecord : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ]) {
            System.abortJob(triggerRecord.Id);
        }
        return System.schedule(jobName, '0 0 * * * ?', new FedExTrackingStatusBatch());
    }
}
