public with sharing class SchedulerTrackingService {
    public static void recordScheduleCreated(
        String integrationType,
        String sourceObject,
        String frequencyValue,
        String frequencyType,
        String schedulerName,
        List<Id> cronJobIds
    ) {
        if (String.isBlank(schedulerName)) {
            return;
        }

        String logicalKey = normalizeLogicalJobName(schedulerName);
        List<String> cronIdStrings = new List<String>();
        for (Id cronJobId : cronJobIds == null ? new List<Id>() : cronJobIds) {
            if (cronJobId != null) {
                cronIdStrings.add(String.valueOf(cronJobId));
            }
        }

        List<Scheduled_Integration_Job__c> existingJobs = [
            SELECT Id
            FROM Scheduled_Integration_Job__c
            WHERE Logical_Job_Key__c = :logicalKey
            LIMIT 1
        ];

        Scheduled_Integration_Job__c trackedJob = existingJobs.isEmpty()
            ? new Scheduled_Integration_Job__c(Logical_Job_Key__c = logicalKey)
            : existingJobs[0];

        trackedJob.Integration_Type__c = integrationType;
        trackedJob.Source_Object__c = sourceObject;
        trackedJob.Frequency_Value__c = parseDecimal(frequencyValue);
        trackedJob.Frequency_Type__c = frequencyType;
        trackedJob.Scheduler_Name__c = logicalKey;
        trackedJob.Cron_Job_Ids__c = String.join(cronIdStrings, ',');
        trackedJob.Status__c = 'Active';
        trackedJob.Created_By_User__c = UserInfo.getUserId();
        trackedJob.Created_DateTime__c = Datetime.now();
        trackedJob.Deleted_DateTime__c = null;
        try {
            upsert trackedJob Logical_Job_Key__c;
        } catch (DmlException e) {
            for (Integer i = 0; i < e.getNumDml(); i++) {
                ErrorLogUtility.logDmlFailure(
                    'QuickBridge',
                    'SchedulerTrackingService.recordScheduleCreated',
                    'upsert',
                    'Scheduled_Integration_Job__c',
                    trackedJob.Id,
                    e.getDmlMessage(i),
                    null,
                    null
                );
            }
            throw e;
        }
    }

    public static void markScheduleDeleted(String schedulerName) {
        if (String.isBlank(schedulerName)) {
            return;
        }

        Set<String> logicalKeys = new Set<String>{
            normalizeLogicalJobName(schedulerName)
        };
        String searchName = normalizeLogicalJobName(schedulerName) + '%';

        for (CronTrigger triggerRecord : [
            SELECT CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :searchName
        ]) {
            logicalKeys.add(normalizeLogicalJobName(triggerRecord.CronJobDetail.Name));
        }

        List<Scheduled_Integration_Job__c> trackedJobs = [
            SELECT Id, Status__c, Deleted_DateTime__c
            FROM Scheduled_Integration_Job__c
            WHERE Logical_Job_Key__c IN :logicalKeys
            AND Status__c != 'Deleted'
        ];

        for (Scheduled_Integration_Job__c trackedJob : trackedJobs) {
            trackedJob.Status__c = 'Deleted';
            trackedJob.Deleted_DateTime__c = Datetime.now();
        }

        if (!trackedJobs.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(trackedJobs, false);
            ErrorLogUtility.logDmlResults(
                'QuickBridge',
                'SchedulerTrackingService.markScheduleDeleted',
                'update',
                trackedJobs,
                updateResults,
                null,
                null
            );
        }
    }

    public static String normalizeLogicalJobName(String jobName) {
        if (String.isBlank(jobName)) {
            return '';
        }

        return jobName.trim().replaceAll('\\s\\(\\d+m\\)$', '');
    }

    private static Decimal parseDecimal(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Decimal.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }
}
