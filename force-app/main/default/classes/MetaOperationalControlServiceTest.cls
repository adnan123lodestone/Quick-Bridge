@IsTest
private class MetaOperationalControlServiceTest {
  @IsTest
  static void metaReadinessReportsConfigMapsSchedulerAndRunHistory() {
    seedMetaConfig(new Map<String, String>());
    insertSchedule('Meta Campaign Schedule', 'Meta', 'Campaign');
    insert new Integration_Work_Item__c(
      Integration__c = 'Meta',
      Operation__c = 'LeadAd',
      Source_Object__c = 'ManualRun',
      Source_Record_Id__c = 'meta:lead:test',
      Lock_Key__c = 'meta:lead:test',
      Unique_Key__c = 'Meta|LeadAd|ManualRun|meta:lead:test',
      Status__c = IntegrationWorkService.STATUS_COMPLETED
    );

    Test.startTest();
    ConnectorOperationalControlService.ReadinessReport report =
      ConnectorOperationalControlService.getReadiness('meta');
    Test.stopTest();

    System.assertEquals('meta', report.connectorKey);
    System.assert(containsCheck(report.checks, 'Connector Catalog'));
    System.assert(containsCheck(report.checks, 'Work Routing'));
    System.assert(containsCheck(report.checks, 'Object Maps'));
    System.assert(containsCheck(report.checks, 'Scheduler'));
    System.assert(report.operationSummaries.size() > 0);
  }

  @IsTest
  static void metaReadinessWarnsForDisabledMetaToggles() {
    seedMetaConfig(new Map<String, String>{
      'leadAdsEnabled' => 'false',
      'commentAttributionEnabled' => 'false'
    });

    ConnectorOperationalControlService.ReadinessReport report =
      ConnectorOperationalControlService.getReadiness('meta');

    System.assertEquals(true, hasCheckStatus(report.checks, 'Object Enablement', 'Warning'));
  }

  @IsTest
  static void metaManualRunQueuesSupportedMetaOperationWithPayload() {
    seedMetaConfig(new Map<String, String>());

    Test.startTest();
    ConnectorOperationalControlService.ManualRunResponse response =
      ConnectorOperationalControlService.enqueueManualRun(
        'meta',
        'LeadAd',
        'Inbound',
        null,
        null,
        '{"batchSize":1}'
      );
    Test.stopTest();

    System.assertEquals(true, response.success);
    Integration_Work_Item__c item = [
      SELECT Integration__c, Operation__c, Source_Object__c, Lock_Key__c, Payload__c
      FROM Integration_Work_Item__c
      WHERE Id = :response.workItemId
      LIMIT 1
    ];
    System.assertEquals('Meta', item.Integration__c);
    System.assertEquals('LeadAd', item.Operation__c);
    System.assertEquals('ManualRun', item.Source_Object__c);
    System.assert(item.Lock_Key__c.contains('meta:LeadAd:Inbound'));
    System.assert(item.Payload__c.contains('"manual":true'));
  }

  private static void seedMetaConfig(Map<String, String> overrides) {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'Meta',
      Connector_Key__c = 'meta',
      Connector_Label__c = 'Meta',
      Active__c = true,
      Health_Status__c = 'Unknown',
      Entitlement_Status__c = 'Active',
      Named_Credential__c = 'Meta_Graph_API'
    );
    insert instanceRecord;

    Map<String, String> values = new Map<String, String>{
      'appId' => 'app-123',
      'webhookVerifyTokenRef' => 'verify-token',
      'appSecretRef' => 'meta-test-secret',
      'accessTokenRef' => 'Meta_Access_Token_QA',
      'adAccountId' => 'act_123',
      'pageId' => 'page-123',
      'instagramBusinessAccountId' => 'ig-123',
      'campaignSyncEnabled' => 'true',
      'insightsSyncEnabled' => 'true',
      'leadAdsEnabled' => 'true',
      'commentAttributionEnabled' => 'true',
      'defaultLeadSource' => 'Meta Lead Ad',
      'defaultCampaignMemberStatus' => 'Responded'
    };
    if (overrides != null) {
      values.putAll(overrides);
    }

    List<Connector_Config_Value__c> rows = new List<Connector_Config_Value__c>();
    for (String fieldKey : values.keySet()) {
      rows.add(configValue(instanceRecord.Id, fieldKey, values.get(fieldKey), isSecret(fieldKey)));
    }
    insert rows;
  }

  private static Connector_Config_Value__c configValue(Id instanceId, String fieldKey, String value, Boolean secretReference) {
    return new Connector_Config_Value__c(
      Name = 'meta:' + fieldKey,
      Connector_Instance__c = instanceId,
      Connector_Key__c = 'meta',
      Field_Key__c = fieldKey,
      Value__c = value,
      Is_Secret_Reference__c = secretReference
    );
  }

  private static Boolean isSecret(String fieldKey) {
    return new Set<String>{ 'webhookVerifyTokenRef', 'appSecretRef', 'accessTokenRef' }.contains(fieldKey);
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
      Next_Run_At__c = System.now().addMinutes(5),
      Created_DateTime__c = System.now()
    );
  }

  private static Boolean containsCheck(List<ConnectorOperationalControlService.ReadinessCheck> checks, String label) {
    for (ConnectorOperationalControlService.ReadinessCheck check : checks) {
      if (check.label == label) {
        return true;
      }
    }
    return false;
  }

  private static Boolean hasCheckStatus(
    List<ConnectorOperationalControlService.ReadinessCheck> checks,
    String label,
    String status
  ) {
    for (ConnectorOperationalControlService.ReadinessCheck check : checks) {
      if (check.label == label && check.status == status) {
        return true;
      }
    }
    return false;
  }
}
