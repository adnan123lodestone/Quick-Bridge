public with sharing class QBSchedulerController {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getScheduledJobs() {
        return GenericSchedulerController.getScheduledJobs('qbo');
    }
    
    @AuraEnabled
    public static String scheduleJob(String freqValue, String freqType, String selectedObject) {
        try {
            return GenericSchedulerController.scheduleJob('qbo', freqValue, freqType, selectedObject, null);
            
        } catch (Exception e) {
            logSchedulerException('QuickBooks', 'QBSchedulerController.scheduleJob', e);
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String stopJob() {
        try {
            return GenericSchedulerController.stopConnectorSchedules('qbo');
        } catch (Exception e) {
            logSchedulerException('QuickBooks', 'QBSchedulerController.stopJob', e);
            throw new AuraHandledException('Error stopping job: ' + e.getMessage());
        }
    }
    
    private static Boolean abortExistingJobs(String baseJobName) {
        String searchName = baseJobName + '%';
        List<CronTrigger> existingJobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :searchName];
        if (!existingJobs.isEmpty()) {
            for (CronTrigger ct : existingJobs) {
                System.abortJob(ct.Id);
            }
            return true;
        }
        List<Scheduled_Integration_Job__c> logicalJobs = [
            SELECT Id, Status__c, Deleted_DateTime__c
            FROM Scheduled_Integration_Job__c
            WHERE Logical_Job_Key__c LIKE :searchName
            AND Status__c = 'Active'
        ];
        for (Scheduled_Integration_Job__c logicalJob : logicalJobs) {
            logicalJob.Status__c = 'Deleted';
            logicalJob.Deleted_DateTime__c = Datetime.now();
        }
        if (!logicalJobs.isEmpty()) {
            update logicalJobs;
            return true;
        }
        return false;
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
            summary.put('direction', 'Salesforce to QuickBooks Online');
            summary.put('type', 'Incremental Sync');
            
        } catch(Exception e) {
            System.debug('Error in getSyncSettingsSummary: ' + e.getMessage());
            logSchedulerException('QuickBooks', 'QBSchedulerController.getSyncSettingsSummary', e);
            summary.put('objects', 'Error loading objects');
            summary.put('direction', 'Salesforce to QuickBooks Online');
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
    
    private static String decodeCron(String cronExp) {
        if (String.isBlank(cronExp)) return 'Dynamic Schedule';
        
        List<String> parts = cronExp.split(' ');
        if (parts.size() >= 6) {
            if (parts[2].contains('/')) return 'Every ' + parts[2].split('/')[1] + ' Hours';
            if (parts[3].contains('/')) return 'Every ' + parts[3].split('/')[1] + ' Days';
            if (parts[4].contains('/')) return 'Every ' + parts[4].split('/')[1] + ' Months';
            if (parts[5] != '?') return 'Every Week';
        }
        
        return 'Frequent Interval (Minutes)';
    }

    private static String formatFrequency(Decimal frequencyValue, String frequencyType) {
        Integer safeValue = frequencyValue == null ? 1 : frequencyValue.intValue();
        if (String.isBlank(frequencyType)) {
            return 'Dynamic Schedule';
        }
        return 'Every ' + safeValue + ' ' + frequencyType;
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
        } catch (Exception e) {
            logSchedulerException('QuickBooks', 'QBSchedulerController.togglePauseStatus', e);
            throw new AuraHandledException('Setting update failed: ' + e.getMessage());
        }
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
        } catch (Exception e) {
            logSchedulerException('QuickBooks', 'QBSchedulerController.deleteSpecificJob', e);
            throw new AuraHandledException('Error deleting job: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String editSpecificJob(String jobName, String freqValue, String freqType) {
        try {
            return GenericSchedulerController.editJob('qbo', jobName, freqValue, freqType);
        } catch (Exception e) {
            logSchedulerException('QuickBooks', 'QBSchedulerController.editSpecificJob', e);
            throw new AuraHandledException('Error updating job: ' + e.getMessage());
        }
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
        } catch (Exception e) {
            logSchedulerException('Shopify', 'QBSchedulerController.scheduleShopifyJob', e);
            throw new AuraHandledException('Error scheduling Shopify job: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String stopShopifyJob() {
        try {
            String response = GenericSchedulerController.stopConnectorSchedules('shopify');
            return response.startsWith('Success') ? 'Success: Shopify schedule stopped.' : 'Notice: No active Shopify schedule found.';
        } catch (Exception e) {
            logSchedulerException('Shopify', 'QBSchedulerController.stopShopifyJob', e);
            throw new AuraHandledException('Error stopping Shopify job: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteShopifyJob(String jobName) {
        try {
            GenericSchedulerController.deleteJob(jobName);
        } catch (Exception e) {
            logSchedulerException('Shopify', 'QBSchedulerController.deleteShopifyJob', e);
            throw new AuraHandledException('Error deleting Shopify job: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String editShopifyJob(String jobName, String freqValue, String freqType) {
        try {
            return GenericSchedulerController.editJob('shopify', jobName, freqValue, freqType).replace('Success: Job', 'Success: Shopify job');
        } catch (Exception e) {
            logSchedulerException('Shopify', 'QBSchedulerController.editShopifyJob', e);
            throw new AuraHandledException('Error updating Shopify job: ' + e.getMessage());
        }
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
}
