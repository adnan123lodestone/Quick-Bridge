@IsTest
private class MetaSchedulerRoutingTest {
  @IsTest
  static void scheduledRouterResolvesMetaAdapter() {
    System.assert(ScheduledOperationRouter.adapterFor('Meta', 'Campaign') instanceof MetaScheduledOperationAdapter);
    System.assert(ScheduledOperationRouter.adapterFor('instagram', 'Insights') instanceof MetaScheduledOperationAdapter);
  }

  @IsTest
  static void heartbeatDispatchesDueMetaCampaignAndInsightsSchedules() {
    insertSchedule('Meta Campaign Due', 'Meta', 'Campaign');
    insertSchedule('Meta Insights Due', 'Meta', 'Insights');

    Test.startTest();
    ScheduledIntegrationHeartbeat.dispatchDueSchedules();
    Test.stopTest();

    System.assertEquals(1, [SELECT COUNT() FROM Integration_Work_Item__c WHERE Integration__c = 'Meta' AND Operation__c = 'CampaignSync']);
    System.assertEquals(1, [SELECT COUNT() FROM Integration_Work_Item__c WHERE Integration__c = 'Meta' AND Operation__c = 'InsightsSync']);
  }

  @IsTest
  static void scheduledAdapterMapsNullAndInsightsSources() {
    Test.startTest();
    new MetaScheduledOperationAdapter().execute(null);
    new MetaScheduledOperationAdapter().execute(new Scheduled_Integration_Job__c(Source_Object__c = 'InsightsSync'));
    Test.stopTest();

    System.assertEquals(1, [SELECT COUNT() FROM Integration_Work_Item__c WHERE Operation__c = 'CampaignSync']);
    System.assertEquals(1, [SELECT COUNT() FROM Integration_Work_Item__c WHERE Operation__c = 'InsightsSync']);
  }

  private static void insertSchedule(String keyValue, String integrationType, String sourceObject) {
    insert new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = keyValue,
      Scheduler_Name__c = keyValue,
      Integration_Type__c = integrationType,
      Source_Object__c = sourceObject,
      Direction__c = 'Inbound',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Ready',
      Next_Run_At__c = System.now().addMinutes(-1),
      Created_DateTime__c = System.now()
    );
  }
}