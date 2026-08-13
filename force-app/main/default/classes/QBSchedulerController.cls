public with sharing class QBSchedulerController {

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getScheduledJobs() {
        return GenericSchedulerController.getScheduledJobs('qbo');
    }

    @AuraEnabled
    public static String scheduleJob(String freqValue, String freqType, String selectedObject, Boolean isSfToQbo) {
        try {
            QuickBooksAuthHandler.validateConfiguration();
            return GenericSchedulerController.scheduleJob('qbo', freqValue, freqType, selectedObject, isSfToQbo == false ? 'In' : 'Out');

        } catch (Exception e) { throw schedulerException('QuickBooks', 'QBSchedulerController.scheduleJob', e, 'Error: '); }
    }

    @AuraEnabled
    public static String stopJob() {
        try {
            return GenericSchedulerController.stopConnectorSchedules('qbo');
        } catch (Exception e) { throw schedulerException('QuickBooks', 'QBSchedulerController.stopJob', e, 'Error stopping job: '); }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getSyncSettingsSummary() {
        Map<String, String> summary = new Map<String, String>();

        try {
            List<Field_Mapping__mdt> mappings = [
                SELECT SF_Object__c
                FROM Field_Mapping__mdt
                WHERE Integration__c = 'qbonline' AND Is_Active__c = true
            ];

            Set<String> uniqueObjects = new Set<String>();
            for (Field_Mapping__mdt fm : mappings) {
                if (String.isNotBlank(fm.SF_Object__c)) {
                    uniqueObjects.add(fm.SF_Object__c);
                }
            }

            List<String> objectNames = new List<String>(uniqueObjects);
            objectNames.sort();

            summary.put('objects', objectNames.isEmpty() ? 'No objects mapped' : String.join(objectNames, ', '));
            summary.put('direction', 'Salesforce ↔ QuickBooks Online');
            summary.put('type', 'Incremental Sync');

        } catch(Exception e) {
            System.debug('Error in getSyncSettingsSummary: ' + e.getMessage());
            logSchedulerException('QuickBooks', 'QBSchedulerController.getSyncSettingsSummary', e);
            summary.put('objects', 'Error loading objects');
            summary.put('direction', 'Salesforce ↔ QuickBooks Online');
            summary.put('type', 'Incremental Sync');
        }

        return summary;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getRecentRuns(String jobId) {
        List<Map<String, Object>> runList = new List<Map<String, Object>>();

        if (String.isBlank(jobId)) {
            return runList;
        }
        for (AsyncApexJob job : [SELECT Id, CompletedDate, Status, TotalJobItems, NumberOfErrors
                                 FROM AsyncApexJob
                                 WHERE JobType = 'BatchApex'
                                 AND CronTriggerId = :jobId
                                 AND CompletedDate != null
                                 ORDER BY CompletedDate DESC
                                 LIMIT 5]) {
            Map<String, Object> runMap = new Map<String, Object>();
            runMap.put('id', job.Id);
            runMap.put('date', job.CompletedDate.format());
            runMap.put('status', job.Status == 'Completed' ? 'Success' : job.Status);
            runMap.put('processed', job.TotalJobItems);
            runMap.put('failed', job.NumberOfErrors);
            runMap.put('icon', job.NumberOfErrors > 0 ? 'utility:warning' : 'utility:success');
            runMap.put('variant', job.NumberOfErrors > 0 ? 'warning' : 'success');

            runList.add(runMap);
        }
        return runList;
    }

    private static Id createLogicalSchedule(
        String integrationType,
        String selectedObject,
        String freqValue,
        String freqType,
        String logicalJobName,
        String direction
    ) {
        SchedulerEntitlementService.recordScheduleCreated(
            integrationType,
            selectedObject,
            freqValue,
            freqType,
            logicalJobName,
            new List<Id>()
        );

        ScheduledIntegrationHeartbeat.ensureScheduled();

        String logicalKey = SchedulerEntitlementService.normalizeLogicalJobName(logicalJobName);
        Scheduled_Integration_Job__c trackedJob = [
            SELECT Id, Direction__c
            FROM Scheduled_Integration_Job__c
            WHERE Logical_Job_Key__c = :logicalKey
            LIMIT 1
        ];
        if (String.isNotBlank(direction)) {
            trackedJob.Direction__c = direction;
            update trackedJob;
        }
        return trackedJob.Id;
    }

    @AuraEnabled
    public static void togglePauseStatus(Boolean pauseIt) {
        try {
            QuickBridgeAdminGuard.requireRunSync();
            Sync_Settings__c settings = Sync_Settings__c.getOrgDefaults();
            settings.Is_Paused__c = pauseIt;
            upsert settings;
            QuickBridgeAdminGuard.audit('SCHEDULE_PAUSE_TOGGLE', 'qbo', 'Success', 'paused=' + String.valueOf(pauseIt == true), null);
        } catch (Exception e) { throw schedulerException('QuickBooks', 'QBSchedulerController.togglePauseStatus', e, 'Setting update failed: '); }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean getPauseStatus() {
        QuickBridgeAdminGuard.requireView();
        Sync_Settings__c settings = Sync_Settings__c.getOrgDefaults();
        return settings.Is_Paused__c;
    }

    @AuraEnabled
    public static void deleteSpecificJob(String jobName) {
        try {
            GenericSchedulerController.deleteJob(jobName);
        } catch (Exception e) { throw schedulerException('QuickBooks', 'QBSchedulerController.deleteSpecificJob', e, 'Error deleting job: '); }
    }

    @AuraEnabled
    public static String editSpecificJob(String jobName, String freqValue, String freqType) {
        try {
            return GenericSchedulerController.editJob('qbo', jobName, freqValue, freqType);
        } catch (Exception e) { throw schedulerException('QuickBooks', 'QBSchedulerController.editSpecificJob', e, 'Error updating job: '); }
    }

    // ─── Shopify Scheduler Methods ───────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getShopifyScheduledJobs() {
        return GenericSchedulerController.getScheduledJobs('shopify');
    }

    @AuraEnabled
    public static String scheduleShopifyJob(String freqValue, String freqType, String selectedObject, Boolean isSfToShopify) {
        try {
            return GenericSchedulerController.scheduleJob('shopify', freqValue, freqType, selectedObject, isSfToShopify == true ? 'Out' : 'In');
        } catch (Exception e) { throw schedulerException('Shopify', 'QBSchedulerController.scheduleShopifyJob', e, 'Error scheduling Shopify job: '); }
    }

    @AuraEnabled
    public static String stopShopifyJob() {
        try {
            String response = GenericSchedulerController.stopConnectorSchedules('shopify');
            return response.startsWith('Success') ? 'Success: Shopify schedule stopped.' : 'Notice: No active Shopify schedule found.';
        } catch (Exception e) { throw schedulerException('Shopify', 'QBSchedulerController.stopShopifyJob', e, 'Error stopping Shopify job: '); }
    }

    @AuraEnabled
    public static void deleteShopifyJob(String jobName) {
        try {
            GenericSchedulerController.deleteJob(jobName);
        } catch (Exception e) { throw schedulerException('Shopify', 'QBSchedulerController.deleteShopifyJob', e, 'Error deleting job: '); }
    }

    @AuraEnabled
    public static String editShopifyJob(String jobName, String freqValue, String freqType) {
        try {
            GenericSchedulerController.deleteJob(jobName);
            List<String> nameParts = jobName.split(' - ');
            String objectAndDir = (nameParts.size() > 1) ? nameParts[1] : 'Customers [In]';
            Boolean isSfToShopify = objectAndDir.contains('[Out]');
            String selectedObject = objectAndDir.replace(' [Out]', '').replace(' [In]', '').trim();
            if (String.isBlank(selectedObject)) selectedObject = 'Customers';

            Integer safeValue = Integer.valueOf(freqValue.trim());
            String logicalJobName = SchedulerEntitlementService.normalizeLogicalJobName(jobName);
            createLogicalSchedule('Shopify', selectedObject, freqValue, freqType, logicalJobName, isSfToShopify ? 'Out' : 'In');
            QuickBridgeAdminGuard.audit('SCHEDULE_EDIT', 'shopify', 'Success', jobName, null);
            return 'Success: Shopify job updated for every ' + safeValue + ' ' + freqType;
        } catch (Exception e) { throw schedulerException('Shopify', 'QBSchedulerController.editShopifyJob', e, 'Error updating Shopify job: '); }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getShopifySyncSettingsSummary() {
        Map<String, String> summary = new Map<String, String>();
        try {
            List<Field_Mapping__mdt> mappings = [
                SELECT SF_Object__c
                FROM Field_Mapping__mdt
                WHERE Integration__c = 'shopify' AND Is_Active__c = true
            ];
            Set<String> uniqueObjects = new Set<String>();
            for (Field_Mapping__mdt fm : mappings) {
                if (String.isNotBlank(fm.SF_Object__c)) uniqueObjects.add(fm.SF_Object__c);
            }
            List<String> objectNames = new List<String>(uniqueObjects);
            objectNames.sort();
            summary.put('objects', objectNames.isEmpty() ? 'No objects mapped' : String.join(objectNames, ', '));
            summary.put('direction', 'Salesforce ↔ Shopify');
            summary.put('type', 'Incremental Sync');
        } catch (Exception e) {
            logSchedulerException('Shopify', 'QBSchedulerController.getShopifySyncSettingsSummary', e);
            summary.put('objects', 'Error loading objects');
            summary.put('direction', 'Salesforce ↔ Shopify');
            summary.put('type', 'Incremental Sync');
        }
        return summary;
    }

    private static void logSchedulerException(String gatewayName, String classMethodName, Exception exceptionRecord) {
        ErrorLogUtility.logException(gatewayName, classMethodName, exceptionRecord, null, null);
    }

    private static AuraHandledException schedulerException(String gatewayName, String classMethodName, Exception exceptionRecord, String prefix) {
        logSchedulerException(gatewayName, classMethodName, exceptionRecord);
        return new AuraHandledException(prefix + exceptionRecord.getMessage());
    }
}