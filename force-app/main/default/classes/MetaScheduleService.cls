public with sharing class MetaScheduleService {
    private static final String CAMPAIGN_SYNC_KEY = 'Meta.CampaignSync';
    private static final String INSIGHTS_SYNC_KEY = 'Meta.InsightsSync';

    public static Integer ensureDefaultSchedules() {
        return ensureDefaultSchedules(false);
    }

    public static Integer activateDefaultSchedules() {
        Integer updatedCount = ensureDefaultSchedules(true);
        ScheduledIntegrationHeartbeat.ensureScheduled();
        QuickBridgeAdminGuard.audit(
            'SCHEDULE_ACTIVATE',
            MetaConfigService.CONNECTOR_KEY,
            'Success',
            'Activated Meta campaign and insights schedules.',
            null
        );
        return updatedCount;
    }

    private static Integer ensureDefaultSchedules(Boolean activateNow) {
        Map<String, Scheduled_Integration_Job__c> existingByKey = new Map<String, Scheduled_Integration_Job__c>();
        for (Scheduled_Integration_Job__c scheduleRecord : [
            SELECT Id, Logical_Job_Key__c, Status__c, Next_Run_At__c
            FROM Scheduled_Integration_Job__c
            WHERE Logical_Job_Key__c IN :new Set<String>{ CAMPAIGN_SYNC_KEY, INSIGHTS_SYNC_KEY }
        ]) {
            existingByKey.put(scheduleRecord.Logical_Job_Key__c, scheduleRecord);
        }

        List<Scheduled_Integration_Job__c> upserts = new List<Scheduled_Integration_Job__c>();
        upserts.add(buildSchedule(existingByKey.get(CAMPAIGN_SYNC_KEY), CAMPAIGN_SYNC_KEY, 'Meta Campaign Sync', 'Campaign', activateNow));
        upserts.add(buildSchedule(existingByKey.get(INSIGHTS_SYNC_KEY), INSIGHTS_SYNC_KEY, 'Meta Insights Sync', 'Insights', activateNow));
        upsert upserts Logical_Job_Key__c;
        return upserts.size();
    }

    private static Scheduled_Integration_Job__c buildSchedule(
        Scheduled_Integration_Job__c existing,
        String logicalKey,
        String schedulerName,
        String sourceObject,
        Boolean activateNow
    ) {
        Scheduled_Integration_Job__c scheduleRecord = existing == null
            ? new Scheduled_Integration_Job__c(Logical_Job_Key__c = logicalKey)
            : new Scheduled_Integration_Job__c(Id = existing.Id, Logical_Job_Key__c = logicalKey);
        scheduleRecord.Scheduler_Name__c = schedulerName;
        scheduleRecord.Integration_Type__c = MetaConfigService.INTEGRATION_NAME;
        scheduleRecord.Source_Object__c = sourceObject;
        scheduleRecord.Direction__c = 'Inbound';
        scheduleRecord.Frequency_Value__c = 1;
        scheduleRecord.Frequency_Type__c = 'Hours';
        if (existing == null) {
            scheduleRecord.Status__c = activateNow ? 'Ready' : 'Paused';
            scheduleRecord.Next_Run_At__c = activateNow ? Datetime.now() : Datetime.now().addHours(1);
        } else if (activateNow && existing.Status__c == 'Paused') {
            scheduleRecord.Status__c = 'Ready';
            scheduleRecord.Next_Run_At__c = Datetime.now();
        }
        return scheduleRecord;
    }
}