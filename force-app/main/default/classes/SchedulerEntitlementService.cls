public with sharing class SchedulerEntitlementService {
    private static final Integer FALLBACK_LIMIT = 10;
    private static final Set<String> BILLABLE_JOB_PREFIXES = new Set<String>{
        'QBO Sync',
        'Shopify Sync',
        'Carrier Tracking Status Sync',
        'FedEx Carrier Tracking Status Sync',
        'UPS Carrier Tracking Status Sync'
    };
    private static final Set<String> INACTIVE_CRON_STATES = new Set<String>{ 'DELETED', 'COMPLETE', 'ERROR' };

    public class UsageSummary {
        @AuraEnabled public Integer activeCount { get; set; }
        @AuraEnabled public Integer maxActiveSchedules { get; set; }
        @AuraEnabled public Integer remaining { get; set; }
        @AuraEnabled public Boolean limitReached { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static UsageSummary getUsageSummary() {
        return buildUsageSummary();
    }

    public static void assertCanCreateSchedule() {
        UsageSummary summary = buildUsageSummary();
        if (summary.limitReached == true) {
            throw new AuraHandledException(summary.message);
        }
    }

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
                    'SchedulerEntitlementService.recordScheduleCreated',
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
                'SchedulerEntitlementService.markScheduleDeleted',
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

    private static UsageSummary buildUsageSummary() {
        Integer maxSchedules = getMaxActiveSchedules();
        Integer activeCount = countActiveLogicalSchedules();

        UsageSummary summary = new UsageSummary();
        summary.activeCount = activeCount;
        summary.maxActiveSchedules = maxSchedules;
        summary.remaining = Math.max(0, maxSchedules - activeCount);
        summary.limitReached = activeCount >= maxSchedules;
        summary.message = summary.limitReached
            ? 'Your current plan allows ' + maxSchedules + ' active schedules. Delete an existing schedule or upgrade your plan.'
            : summary.remaining + ' active schedule slot' + (summary.remaining == 1 ? '' : 's') + ' remaining.';
        return summary;
    }

    private static Integer getMaxActiveSchedules() {
        try {
            for (Scheduler_Plan_Limit__mdt planLimit : [
                SELECT Max_Active_Schedules__c
                FROM Scheduler_Plan_Limit__mdt
                WHERE Is_Default__c = true
                LIMIT 1
            ]) {
                if (planLimit.Max_Active_Schedules__c != null) {
                    return planLimit.Max_Active_Schedules__c.intValue();
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'SchedulerEntitlementService.getMaxActiveSchedules exception: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'SchedulerEntitlementService.getMaxActiveSchedules', e, null, null);
        }
        return FALLBACK_LIMIT;
    }

    private static Integer countActiveLogicalSchedules() {
        Set<String> activeKeys = new Set<String>();

        for (Scheduled_Integration_Job__c trackedJob : [
            SELECT Logical_Job_Key__c
            FROM Scheduled_Integration_Job__c
            WHERE Status__c = 'Active'
        ]) {
            if (String.isNotBlank(trackedJob.Logical_Job_Key__c)) {
                activeKeys.add(normalizeLogicalJobName(trackedJob.Logical_Job_Key__c));
            }
        }

        for (CronTrigger triggerRecord : [
            SELECT CronJobDetail.Name, State
            FROM CronTrigger
            WHERE State NOT IN :INACTIVE_CRON_STATES
            AND (
                CronJobDetail.Name LIKE 'QBO Sync%'
                OR CronJobDetail.Name LIKE 'Shopify Sync%'
                OR CronJobDetail.Name LIKE 'Carrier Tracking Status Sync%'
                OR CronJobDetail.Name LIKE 'FedEx Carrier Tracking Status Sync%'
                OR CronJobDetail.Name LIKE 'UPS Carrier Tracking Status Sync%'
            )
        ]) {
            String logicalName = normalizeLogicalJobName(triggerRecord.CronJobDetail.Name);
            if (isBillableJobName(logicalName)) {
                activeKeys.add(logicalName);
            }
        }

        return activeKeys.size();
    }

    private static Boolean isBillableJobName(String logicalName) {
        if (String.isBlank(logicalName)) {
            return false;
        }
        for (String prefix : BILLABLE_JOB_PREFIXES) {
            if (logicalName.startsWith(prefix)) {
                return true;
            }
        }
        return false;
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