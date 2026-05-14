public with sharing class CarrierTrackingStatusBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {

    private String integrationFilter;

    public CarrierTrackingStatusBatch() {
        this.integrationFilter = null;
    }

    public CarrierTrackingStatusBatch(String integrationFilter) {
        this.integrationFilter = integrationFilter;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (String.isNotBlank(integrationFilter)) {
            return Database.getQueryLocator([
                SELECT Id, Integration_Type__c
                FROM Carrier_Shipment__c
                WHERE Master_Tracking_Number__c != null
                AND Is_Terminal__c = false
                AND Integration_Type__c = :integrationFilter
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id, Integration_Type__c
            FROM Carrier_Shipment__c
            WHERE Master_Tracking_Number__c != null
            AND Is_Terminal__c = false
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        for (SObject row : scope) {
            Id shipmentId;
            String integrationType;
            try {
                shipmentId = (Id) row.get('Id');
                integrationType = String.valueOf(row.get('Integration_Type__c'));
                CarrierOperationsService.syncTrackingStatus(shipmentId, integrationType);
            } catch (Exception e) {
                ErrorLogUtility.logException(
                    String.isBlank(integrationType) ? 'Carrier' : integrationType,
                    'CarrierTrackingStatusBatch.execute',
                    e,
                    'Carrier_Shipment__c',
                    shipmentId
                );
            }
        }
    }

    public void finish(Database.BatchableContext context) {
    }

    public void execute(SchedulableContext context) {
        try {
            Database.executeBatch(new CarrierTrackingStatusBatch(), 10);
        } catch (Exception e) {
            ErrorLogUtility.logException('Carrier', 'CarrierTrackingStatusBatch.executeSchedulable', e, null, null);
            throw e;
        }
    }

    @AuraEnabled
    public static String scheduleHourly() {
        String jobName = 'Carrier Tracking Status Sync';
        for (CronTrigger triggerRecord : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ]) {
            System.abortJob(triggerRecord.Id);
        }
        try {
            return System.schedule(jobName, '0 0 * * * ?', new CarrierTrackingStatusBatch());
        } catch (Exception e) {
            ErrorLogUtility.logException('Carrier', 'CarrierTrackingStatusBatch.scheduleHourly', e, null, null);
            throw e;
        }
    }

    @AuraEnabled
    public static String scheduleFedExHourly() {
        String jobName = 'FedEx Carrier Tracking Status Sync';
        for (CronTrigger triggerRecord : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ]) {
            System.abortJob(triggerRecord.Id);
        }
        try {
            return System.schedule(jobName, '0 0 * * * ?', new CarrierTrackingStatusBatch('fedex'));
        } catch (Exception e) {
            ErrorLogUtility.logException('FedEx', 'CarrierTrackingStatusBatch.scheduleFedExHourly', e, null, null);
            throw e;
        }
    }

    @AuraEnabled
    public static String scheduleUPSHourly() {
        String jobName = 'UPS Carrier Tracking Status Sync';
        for (CronTrigger triggerRecord : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ]) {
            System.abortJob(triggerRecord.Id);
        }
        try {
            return System.schedule(jobName, '0 30 * * * ?', new CarrierTrackingStatusBatch('ups'));
        } catch (Exception e) {
            ErrorLogUtility.logException('UPS', 'CarrierTrackingStatusBatch.scheduleUPSHourly', e, null, null);
            throw e;
        }
    }
}