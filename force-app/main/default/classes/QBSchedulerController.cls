public with sharing class QBSchedulerController {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getScheduledJobs() {
        List<Map<String, Object>> jobList = new List<Map<String, Object>>();
        
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name, NextFireTime, PreviousFireTime, State, CreatedDate, CreatedBy.Name, CronExpression 
                                FROM CronTrigger WHERE CronJobDetail.Name LIKE 'QBO Sync%'
                                ORDER BY CreatedDate DESC 
                                LIMIT 50];
        
        for (CronTrigger job : jobs) {
            Map<String, Object> jobMap = new Map<String, Object>();
            jobMap.put('id', job.Id);
            jobMap.put('status', job.State);
            String fullName = job.CronJobDetail.Name;
            String syncObjectName = 'Unknown';
            if (String.isNotBlank(fullName) && fullName.contains(' - ')) {
                List<String> parts = fullName.split(' - ');
                if (parts.size() > 1 && String.isNotBlank(parts[1])) {
                    syncObjectName = parts[1];
                }
            }
            
            jobMap.put('syncObject', syncObjectName);
            jobMap.put('name', fullName);
            jobMap.put('nextRun', job.NextFireTime != null ? job.NextFireTime.format() : 'Not Scheduled');
            jobMap.put('lastRun', job.PreviousFireTime != null ? job.PreviousFireTime.format() : 'N/A');
            jobMap.put('createdBy', job.CreatedBy != null ? job.CreatedBy.Name : 'System');
            jobMap.put('createdDate', job.CreatedDate != null ? job.CreatedDate.format() : 'N/A');
            jobMap.put('frequencyText', decodeCron(job.CronExpression));
            jobList.add(jobMap);
        }
        return jobList;
    }
    
    @AuraEnabled
    public static String scheduleJob(String freqValue, String freqType, String selectedObject) {
        try {
            SchedulerEntitlementService.assertCanCreateSchedule();
            Integer safeValue = Integer.valueOf(freqValue.trim());
            QBSyncScheduler scheduler = new QBSyncScheduler(selectedObject);
            String uniqueJobName = 'QBO Sync - ' + selectedObject + ' - ' + Datetime.now().format('MM/dd/yyyy hh:mm a');
            Id newJobId;
            List<Id> cronJobIds = new List<Id>();

            if (freqType == 'Minutes') {
                for (Integer i = 0; i < 60; i += safeValue) {
                    String cronExp = '0 ' + i + ' * * * ?';
                    Id jobId = System.schedule(uniqueJobName + ' (' + i + 'm)', cronExp, scheduler);
                    cronJobIds.add(jobId);
                    if (newJobId == null) {
                        newJobId = jobId;
                    }
                }
            } else {
                String cronExp = '';
                if (freqType == 'Hours') cronExp = '0 0 0/' + safeValue + ' * * ?';
                else if (freqType == 'Days') cronExp = '0 0 0 1/' + safeValue + ' * ?';
                else if (freqType == 'Weeks') cronExp = '0 0 0 ? * MON'; 
                else if (freqType == 'Months') cronExp = '0 0 0 1 1/' + safeValue + ' ?';
                
                newJobId = System.schedule(uniqueJobName, cronExp, scheduler);
                cronJobIds.add(newJobId);
            }

            SchedulerEntitlementService.recordScheduleCreated(
                'QuickBooks',
                selectedObject,
                freqValue,
                freqType,
                uniqueJobName,
                cronJobIds
            );
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
            
            for (CronTrigger ct : existingJobs) {
                System.abortJob(ct.Id);
            }
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
            QBSyncScheduler scheduler = new QBSyncScheduler(selectedObject);
            String logicalJobName = SchedulerEntitlementService.normalizeLogicalJobName(jobName);
            List<Id> cronJobIds = new List<Id>();

            if (freqType == 'Minutes') {
                for (Integer i = 0; i < 60; i += safeValue) {
                    String cronExp = '0 ' + i + ' * * * ?';
                    cronJobIds.add(System.schedule(logicalJobName + ' (' + i + 'm)', cronExp, scheduler));
                }
                SchedulerEntitlementService.recordScheduleCreated('QuickBooks', selectedObject, freqValue, freqType, logicalJobName, cronJobIds);
                IntegrationUsageService.incrementTaskUsage('QuickBooks', 1);
                return 'Success: Job updated for every ' + safeValue + ' Minutes';
            } else {
                String cronExp = '';
                if (freqType == 'Hours') cronExp = '0 0 0/' + safeValue + ' * * ?';
                else if (freqType == 'Days') cronExp = '0 0 0 1/' + safeValue + ' * ?';
                else if (freqType == 'Weeks') cronExp = '0 0 0 ? * MON';
                else if (freqType == 'Months') cronExp = '0 0 0 1 1/' + safeValue + ' ?';

                cronJobIds.add(System.schedule(logicalJobName, cronExp, scheduler));
                SchedulerEntitlementService.recordScheduleCreated('QuickBooks', selectedObject, freqValue, freqType, logicalJobName, cronJobIds);
                IntegrationUsageService.incrementTaskUsage('QuickBooks', 1);
                return 'Success: Job updated for every ' + safeValue + ' ' + freqType;
            }
        } catch (Exception e) {
            logSchedulerException('QuickBooks', 'QBSchedulerController.editSpecificJob', e);
            throw new AuraHandledException('Error updating job: ' + e.getMessage());
        }
    }

    // ─── Shopify Scheduler Methods ───────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getShopifyScheduledJobs() {
        List<Map<String, Object>> jobList = new List<Map<String, Object>>();

        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name, NextFireTime, PreviousFireTime, State, CreatedDate, CreatedBy.Name, CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Shopify Sync%'
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];

        for (CronTrigger job : jobs) {
            Map<String, Object> jobMap = new Map<String, Object>();
            jobMap.put('id', job.Id);
            jobMap.put('status', job.State);
            String fullName = job.CronJobDetail.Name;
            String syncObjectName = 'Unknown';
            if (String.isNotBlank(fullName) && fullName.contains(' - ')) {
                List<String> parts = fullName.split(' - ');
                if (parts.size() > 1 && String.isNotBlank(parts[1])) {
                    syncObjectName = parts[1];
                }
            }
            jobMap.put('syncObject', syncObjectName);
            jobMap.put('name', fullName);
            jobMap.put('nextRun', job.NextFireTime != null ? job.NextFireTime.format() : 'Not Scheduled');
            jobMap.put('lastRun', job.PreviousFireTime != null ? job.PreviousFireTime.format() : 'N/A');
            jobMap.put('createdBy', job.CreatedBy != null ? job.CreatedBy.Name : 'System');
            jobMap.put('createdDate', job.CreatedDate != null ? job.CreatedDate.format() : 'N/A');
            jobMap.put('frequencyText', decodeCron(job.CronExpression));
            jobList.add(jobMap);
        }
        return jobList;
    }

    @AuraEnabled
    public static String scheduleShopifyJob(String freqValue, String freqType, String selectedObject, Boolean isSfToShopify) {
        try {
            SchedulerEntitlementService.assertCanCreateSchedule();
            Integer safeValue = Integer.valueOf(freqValue.trim());
            ShopifySyncScheduler scheduler = new ShopifySyncScheduler(selectedObject, isSfToShopify);
            String directionTag = (isSfToShopify == true) ? ' [Out]' : ' [In]';
            String uniqueJobName = 'Shopify Sync - ' + selectedObject + directionTag + ' - ' + Datetime.now().format('MM/dd/yyyy hh:mm a');
            Id newJobId;
            List<Id> cronJobIds = new List<Id>();

            if (freqType == 'Minutes') {
                for (Integer i = 0; i < 60; i += safeValue) {
                    String cronExp = '0 ' + i + ' * * * ?';
                    Id jobId = System.schedule(uniqueJobName + ' (' + i + 'm)', cronExp, scheduler);
                    cronJobIds.add(jobId);
                    if (newJobId == null) newJobId = jobId;
                }
            } else {
                String cronExp = '';
                if (freqType == 'Hours')  cronExp = '0 0 0/' + safeValue + ' * * ?';
                else if (freqType == 'Days')   cronExp = '0 0 0 1/' + safeValue + ' * ?';
                else if (freqType == 'Weeks')  cronExp = '0 0 0 ? * MON';
                else if (freqType == 'Months') cronExp = '0 0 0 1 1/' + safeValue + ' ?';
                newJobId = System.schedule(uniqueJobName, cronExp, scheduler);
                cronJobIds.add(newJobId);
            }

            SchedulerEntitlementService.recordScheduleCreated(
                'Shopify',
                selectedObject,
                freqValue,
                freqType,
                uniqueJobName,
                cronJobIds
            );
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
            ShopifySyncScheduler scheduler = new ShopifySyncScheduler(selectedObject, isSfToShopify);
            String logicalJobName = SchedulerEntitlementService.normalizeLogicalJobName(jobName);
            List<Id> cronJobIds = new List<Id>();

            if (freqType == 'Minutes') {
                for (Integer i = 0; i < 60; i += safeValue) {
                    String cronExp = '0 ' + i + ' * * * ?';
                    cronJobIds.add(System.schedule(logicalJobName + ' (' + i + 'm)', cronExp, scheduler));
                }
                SchedulerEntitlementService.recordScheduleCreated('Shopify', selectedObject, freqValue, freqType, logicalJobName, cronJobIds);
                IntegrationUsageService.incrementTaskUsage('Shopify', 1);
                return 'Success: Shopify job updated for every ' + safeValue + ' Minutes';
            } else {
                String cronExp = '';
                if (freqType == 'Hours')  cronExp = '0 0 0/' + safeValue + ' * * ?';
                else if (freqType == 'Days')   cronExp = '0 0 0 1/' + safeValue + ' * ?';
                else if (freqType == 'Weeks')  cronExp = '0 0 0 ? * MON';
                else if (freqType == 'Months') cronExp = '0 0 0 1 1/' + safeValue + ' ?';
                cronJobIds.add(System.schedule(logicalJobName, cronExp, scheduler));
                SchedulerEntitlementService.recordScheduleCreated('Shopify', selectedObject, freqValue, freqType, logicalJobName, cronJobIds);
                IntegrationUsageService.incrementTaskUsage('Shopify', 1);
                return 'Success: Shopify job updated for every ' + safeValue + ' ' + freqType;
            }
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