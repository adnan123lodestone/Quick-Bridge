@IsTest
private class ConnectorOperationalControlServiceTest {
  @IsTest
  static void readinessReportsConnectorSetupAndRecentRuns() {
    insert new Integration_Work_Item__c(
      Integration__c = 'NetSuite',
      Operation__c = 'SalesOrderSync',
      Source_Object__c = 'ManualRun',
      Source_Record_Id__c = 'netsuite:SalesOrderSync:test',
      Lock_Key__c = 'netsuite:SalesOrderSync:test',
      Unique_Key__c = 'netsuite|SalesOrderSync|ManualRun|test',
      Status__c = IntegrationWorkService.STATUS_FAILED,
      Last_Error__c = 'Missing customer dependency'
    );

    Test.startTest();
    ConnectorOperationalControlService.ReadinessReport report =
      ConnectorOperationalControlService.getReadiness('netsuite');
    Test.stopTest();

    System.assertEquals('netsuite', report.connectorKey);
    System.assertNotEquals(null, report.status);
    System.assert(report.checks.size() > 0, 'Readiness should expose setup checks.');
    System.assert(report.operationSummaries.size() > 0, 'Readiness should expose run history summaries.');
    System.assert(
      containsCheck(report.checks, 'Object Maps'),
      'Object map readiness should be visible to admins.'
    );
    System.assert(
      containsCheck(report.checks, 'Scheduler'),
      'Scheduler readiness should be visible to admins.'
    );
  }

  @IsTest
  static void mappingPresetsCoverNetSuiteAndMetaOperationalObjects() {
    Test.startTest();
    List<ConnectorOperationalControlService.MappingPreset> netsuitePresets =
      ConnectorOperationalControlService.getMappingPresets('netsuite');
    List<ConnectorOperationalControlService.MappingPreset> metaPresets =
      ConnectorOperationalControlService.getMappingPresets('meta');
    Test.stopTest();

    System.assert(
      hasPreset(netsuitePresets, 'Order', 'SalesOrder', 'AccountId', 'entity'),
      'NetSuite sales order dependency guidance should be present.'
    );
    System.assert(
      hasPreset(netsuitePresets, 'Portal_Payment_Transaction__c', 'Payment', 'Gateway_Amount__c', 'payment'),
      'NetSuite payment guidance should be present.'
    );
    System.assert(
      hasPreset(metaPresets, 'Campaign', 'Campaign', 'Meta_Campaign_Id__c', 'id'),
      'Meta campaign guidance should be present.'
    );
    System.assert(
      hasPreset(metaPresets, 'Lead', 'LeadAd', 'Meta_Leadgen_Id__c', 'id'),
      'Meta lead ad guidance should be present.'
    );
  }

  @IsTest
  static void manualRunEnqueuesAllowlistedOperationWithPayloadAndAudit() {
    Test.startTest();
    ConnectorOperationalControlService.ManualRunResponse response =
      ConnectorOperationalControlService.enqueueManualRun(
        'netsuite',
        'SalesOrderSync',
        'Inbound',
        null,
        null,
        '{"batchSize":25}'
      );
    Test.stopTest();

    System.assertEquals(true, response.success);
    System.assertNotEquals(null, response.workItemId);

    Integration_Work_Item__c workItem = [
      SELECT Integration__c, Operation__c, Source_Object__c, Source_Record_Id__c, Lock_Key__c, Payload__c
      FROM Integration_Work_Item__c
      WHERE Id = :response.workItemId
      LIMIT 1
    ];
    System.assertEquals('NetSuite', workItem.Integration__c);
    System.assertEquals('SalesOrderSync', workItem.Operation__c);
    System.assertEquals('ManualRun', workItem.Source_Object__c);
    System.assert(workItem.Lock_Key__c.contains('netsuite:SalesOrderSync:Inbound'));
    System.assert(workItem.Payload__c.contains('"manual":true'));
    System.assert(workItem.Payload__c.contains('"direction":"Inbound"'));
  }

  @IsTest
  static void manualRunRejectsUnsupportedOperation() {
    try {
      ConnectorOperationalControlService.enqueueManualRun(
        'meta',
        'DeleteEverything',
        'Inbound',
        null,
        null,
        null
      );
      System.assert(false, 'Unsupported operations should not be enqueued.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected);
    }
  }

  private static Boolean containsCheck(
    List<ConnectorOperationalControlService.ReadinessCheck> checks,
    String label
  ) {
    for (ConnectorOperationalControlService.ReadinessCheck check : checks) {
      if (check.label == label) {
        return true;
      }
    }
    return false;
  }

  private static Boolean hasPreset(
    List<ConnectorOperationalControlService.MappingPreset> presets,
    String salesforceObject,
    String externalObject,
    String salesforceField,
    String externalField
  ) {
    for (ConnectorOperationalControlService.MappingPreset preset : presets) {
      if (
        preset.salesforceObject == salesforceObject &&
        preset.externalObject == externalObject &&
        preset.salesforceField == salesforceField &&
        preset.externalField == externalField
      ) {
        return true;
      }
    }
    return false;
  }
}
