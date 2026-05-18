public with sharing class QBSchedulerController {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getScheduledJobs() {
        List<Map<String, Object>> jobList = new List<Map<String, Object>>();
        
        List<Scheduled_Integration_Job__c> jobs = [
            SELECT Id, Logical_Job_Key__c, Scheduler_Name__c, Source_Object__c, Status__c, Next_Run_At__c,
                Last_Run_At__c, Created_DateTime__c, Created_By_User__r.Name, Frequency_Value__c, Frequency_Type__c
            FROM Scheduled_Integration_Job__c
            WHERE Integration_Type__c = 'QuickBooks'
            AND Status__c = 'Active'
            ORDER BY Created_DateTime__c DESC
            LIMIT 50
        ];

        for (Scheduled_Integration_Job__c job : jobs) {
            Map<String, Object> jobMap = new Map<String, Object>();
            String fullName = String.isBlank(job.Scheduler_Name__c) ? job.Logical_Job_Key__c : job.Scheduler_Name__c;
            String syncObjectName = String.isBlank(job.Source_Object__c) ? 'Unknown' : job.Source_Object__c;
            jobMap.put('id', job.Id);
            jobMap.put('status', job.Status__c);
            jobMap.put('syncObject', syncObjectName);
            jobMap.put('name', fullName);
            jobMap.put('nextRun', job.Next_Run_At__c != null ? job.Next_Run_At__c.format() : 'Not Scheduled');
            jobMap.put('lastRun', job.Last_Run_At__c != null ? job.Last_Run_At__c.format() : 'N/A');
            jobMap.put('createdBy', job.Created_By_User__r != null ? job.Created_By_User__r.Name : 'System');
            jobMap.put('createdDate', job.Created_DateTime__c != null ? job.Created_DateTime__c.format() : 'N/A');
            jobMap.put('frequencyText', formatFrequency(job.Frequency_Value__c, job.Frequency_Type__c));
            jobList.add(jobMap);
        }
        return jobList;
    }
    
    @AuraEnabled
    public static String scheduleJob(String freqValue, String freqType, String selectedObject) {
        try {
            SchedulerEntitlementService.assertCanCreateSchedule();
            Integer safeValue = Integer.valueOf(freqValue.trim());
            String uniqueJobName = 'QBO Sync - ' + selectedObject + ' - ' + Datetime.now().format('MM/dd/yyyy hh:mm a');
            Id newJobId = createLogicalSchedule('QuickBooks', selectedObject, freqValue, freqType, uniqueJobName, null);
            IntegrationUsageService.incrementTaskUsage('QuickBooks', 1);
            
            return (String)newJobId; 
            
        } catch (Exception e) {
            logSchedulerException('QuickBooks', 'QBSchedulerController.scheduleJob', e);
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String stopJob() {
        try {
            Boolean aborted = abortExistingJobs('QBO Sync - Dynamic');
            if(aborted) {
                return 'Success: Schedule stopped successfully.';
            } else {
                return 'Notice: No active schedule found to stop.';
            }
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
            Sync_Settings__c settings = Sync_Settings__c.getOrgDefaults();
            settings.Is_Paused__c = pauseIt;
            upsert settings;
        } catch (Exception e) {
            logSchedulerException('QuickBooks', 'QBSchedulerController.togglePauseStatus', e);
            throw new AuraHandledException('Setting update failed: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Boolean getPauseStatus() {
        Sync_Settings__c settings = Sync_Settings__c.getOrgDefaults();
        return settings.Is_Paused__c;
    }

    @AuraEnabled
    public static void deleteSpecificJob(String jobName) {
        try {
            SchedulerEntitlementService.markScheduleDeleted(jobName);
            String searchName = SchedulerEntitlementService.normalizeLogicalJobName(jobName) + '%';
            List<CronTrigger> existingJobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :searchName];
            for (CronTrigger ct : existingJobs) System.abortJob(ct.Id);
        } catch (Exception e) {
            logSchedulerException('QuickBooks', 'QBSchedulerController.deleteSpecificJob', e);
            throw new AuraHandledException('Error deleting job: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String editSpecificJob(String jobName, String freqValue, String freqType) {
        try {
            deleteSpecificJob(jobName);
            List<String> nameParts = jobName.split(' - ');
            String selectedObject = (nameParts.size() > 1) ? nameParts[1] : 'Account';

            Integer safeValue = Integer.valueOf(freqValue.trim());
            String logicalJobName = SchedulerEntitlementService.normalizeLogicalJobName(jobName);
            createLogicalSchedule('QuickBooks', selectedObject, freqValue, freqType, logicalJobName, null);
            IntegrationUsageService.incrementTaskUsage('QuickBooks', 1);
            return 'Success: Job updated for every ' + safeValue + ' ' + freqType;
        } catch (Exception e) {
            logSchedulerException('QuickBooks', 'QBSchedulerController.editSpecificJob', e);
            throw new AuraHandledException('Error updating job: ' + e.getMessage());
        }
    }

    // ─── Shopify Scheduler Methods ───────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getShopifyScheduledJobs() {
        List<Map<String, Object>> jobList = new List<Map<String, Object>>();

        List<Scheduled_Integration_Job__c> jobs = [
            SELECT Id, Logical_Job_Key__c, Scheduler_Name__c, Source_Object__c, Status__c, Next_Run_At__c,
                Last_Run_At__c, Created_DateTime__c, Created_By_User__r.Name, Frequency_Value__c, Frequency_Type__c
            FROM Scheduled_Integration_Job__c
            WHERE Integration_Type__c = 'Shopify'
            AND Status__c = 'Active'
            ORDER BY Created_DateTime__c DESC
            LIMIT 50
        ];

        for (Scheduled_Integration_Job__c job : jobs) {
            Map<String, Object> jobMap = new Map<String, Object>();
            String fullName = String.isBlank(job.Scheduler_Name__c) ? job.Logical_Job_Key__c : job.Scheduler_Name__c;
            String syncObjectName = String.isBlank(job.Source_Object__c) ? 'Unknown' : job.Source_Object__c;
            jobMap.put('id', job.Id);
            jobMap.put('status', job.Status__c);
            jobMap.put('syncObject', syncObjectName);
            jobMap.put('name', fullName);
            jobMap.put('nextRun', job.Next_Run_At__c != null ? job.Next_Run_At__c.format() : 'Not Scheduled');
            jobMap.put('lastRun', job.Last_Run_At__c != null ? job.Last_Run_At__c.format() : 'N/A');
            jobMap.put('createdBy', job.Created_By_User__r != null ? job.Created_By_User__r.Name : 'System');
            jobMap.put('createdDate', job.Created_DateTime__c != null ? job.Created_DateTime__c.format() : 'N/A');
            jobMap.put('frequencyText', formatFrequency(job.Frequency_Value__c, job.Frequency_Type__c));
            jobList.add(jobMap);
        }
        return jobList;
    }

    @AuraEnabled
    public static String scheduleShopifyJob(String freqValue, String freqType, String selectedObject, Boolean isSfToShopify) {
        try {
            SchedulerEntitlementService.assertCanCreateSchedule();
            Integer safeValue = Integer.valueOf(freqValue.trim());
            String directionTag = (isSfToShopify == true) ? ' [Out]' : ' [In]';
            String uniqueJobName = 'Shopify Sync - ' + selectedObject + directionTag + ' - ' + Datetime.now().format('MM/dd/yyyy hh:mm a');
            Id newJobId = createLogicalSchedule('Shopify', selectedObject, freqValue, freqType, uniqueJobName, isSfToShopify == true ? 'Out' : 'In');
            IntegrationUsageService.incrementTaskUsage('Shopify', 1);

            return (String) newJobId;
        } catch (Exception e) {
            logSchedulerException('Shopify', 'QBSchedulerController.scheduleShopifyJob', e);
            throw new AuraHandledException('Error scheduling Shopify job: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String stopShopifyJob() {
        try {
            Boolean aborted = abortExistingJobs('Shopify Sync');
            return aborted ? 'Success: Shopify schedule stopped.' : 'Notice: No active Shopify schedule found.';
        } catch (Exception e) {
            logSchedulerException('Shopify', 'QBSchedulerController.stopShopifyJob', e);
            throw new AuraHandledException('Error stopping Shopify job: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteShopifyJob(String jobName) {
        try {
            SchedulerEntitlementService.markScheduleDeleted(jobName);
            String searchName = SchedulerEntitlementService.normalizeLogicalJobName(jobName) + '%';
            List<CronTrigger> existingJobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :searchName];
            for (CronTrigger ct : existingJobs) {
                System.abortJob(ct.Id);
            }
        } catch (Exception e) {
            logSchedulerException('Shopify', 'QBSchedulerController.deleteShopifyJob', e);
            throw new AuraHandledException('Error deleting Shopify job: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String editShopifyJob(String jobName, String freqValue, String freqType) {
        try {
            deleteShopifyJob(jobName);
            List<String> nameParts = jobName.split(' - ');
            String objectAndDir = (nameParts.size() > 1) ? nameParts[1] : 'Customers [In]';
            Boolean isSfToShopify = objectAndDir.contains('[Out]');
            String selectedObject = objectAndDir.replace(' [Out]', '').replace(' [In]', '').trim();
            if (String.isBlank(selectedObject)) selectedObject = 'Customers';

            Integer safeValue = Integer.valueOf(freqValue.trim());
            String logicalJobName = SchedulerEntitlementService.normalizeLogicalJobName(jobName);
            createLogicalSchedule('Shopify', selectedObject, freqValue, freqType, logicalJobName, isSfToShopify ? 'Out' : 'In');
            IntegrationUsageService.incrementTaskUsage('Shopify', 1);
            return 'Success: Shopify job updated for every ' + safeValue + ' ' + freqType;
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