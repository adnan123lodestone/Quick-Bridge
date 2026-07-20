@IsTest
private class MetaScheduleServiceTest {
    @IsTest
    static void defaultSchedulesArePausedUntilExplicitActivation() {
        Test.startTest();
        Integer seededCount = MetaScheduleService.ensureDefaultSchedules();
        Test.stopTest();

        System.assertEquals(2, seededCount);
        List<Scheduled_Integration_Job__c> schedules = [
            SELECT Logical_Job_Key__c, Source_Object__c, Status__c, Frequency_Value__c, Frequency_Type__c
            FROM Scheduled_Integration_Job__c
            WHERE Logical_Job_Key__c IN ('Meta.CampaignSync', 'Meta.InsightsSync')
            ORDER BY Logical_Job_Key__c
        ];
        System.assertEquals(2, schedules.size());
        System.assertEquals('Paused', schedules[0].Status__c);
        System.assertEquals('Paused', schedules[1].Status__c);
        System.assertEquals(Decimal.valueOf('1'), schedules[0].Frequency_Value__c);
        System.assertEquals('Hours', schedules[0].Frequency_Type__c);
    }

    @IsTest
    static void activationMakesPausedSchedulesRunnableWithoutDuplicates() {
        MetaScheduleService.ensureDefaultSchedules();

        Test.startTest();
        Integer activatedCount = MetaScheduleService.activateDefaultSchedules();
        Test.stopTest();

        System.assertEquals(2, activatedCount);
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Scheduled_Integration_Job__c WHERE Logical_Job_Key__c IN ('Meta.CampaignSync', 'Meta.InsightsSync')]
        );
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Scheduled_Integration_Job__c WHERE Logical_Job_Key__c IN ('Meta.CampaignSync', 'Meta.InsightsSync') AND Status__c = 'Ready']
        );
    }
}