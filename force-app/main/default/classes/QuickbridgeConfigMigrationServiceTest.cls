@IsTest
private class QuickbridgeConfigMigrationServiceTest {
  // Inserts a minimal Integration_Product__c so the connector is resolvable.
  private static void insertTestConnector(String key) {
    insert new Integration_Product__c(
      Name = key,
      Product_Key__c = key,
      Connector_Key__c = key,
      Product_Label__c = key,
      Category__c = 'Test',
      Display_Order__c = 99,
      Enabled__c = true,
      Catalog_Active__c = true,
      Has_Config__c = true,
      Has_Reporting__c = false
    );
    ConnectorRegistryService.clearCache();
  }

  @IsTest
  static void migrateConnector_noExistingInstance_createsInstanceAndReturnsLegacyMessage() {
    insertTestConnector('migtest-new');

    Test.startTest();
    QuickbridgeConfigMigrationService.MigrationResult result = QuickbridgeConfigMigrationService.migrateConnector(
      'migtest-new'
    );
    Test.stopTest();

    System.assertEquals(true, result.success, result.message);
    System.assertEquals('migtest-new', result.connectorKey);
    System.assertNotEquals(
      null,
      result.connectorInstanceId,
      'Should have created a Connector_Instance__c'
    );
    System.assert(
      result.message.contains('Legacy'),
      'Expected legacy migration message, got: ' + result.message
    );
  }

  @IsTest
  static void migrateConnector_existingInstance_returnsAlreadyNormalizedMessage() {
    insertTestConnector('migtest-existing');

    Connector_Instance__c inst = new Connector_Instance__c(
      Name = 'migtest-existing',
      Connector_Key__c = 'migtest-existing',
      Connector_Label__c = 'migtest-existing',
      Active__c = true,
      Entitlement_Status__c = 'Active',
      Health_Status__c = 'Healthy'
    );
    insert inst;
    insert new Connector_Config_Value__c(
      Name = 'migtest-existing:storeUrl',
      Connector_Instance__c = inst.Id,
      Connector_Key__c = 'migtest-existing',
      Field_Key__c = 'storeUrl',
      Value__c = 'https://example.test'
    );
    ConnectorRegistryService.clearCache();

    Test.startTest();
    QuickbridgeConfigMigrationService.MigrationResult result = QuickbridgeConfigMigrationService.migrateConnector(
      'migtest-existing'
    );
    Test.stopTest();

    System.assertEquals(true, result.success, result.message);
    System.assertEquals(inst.Id, result.connectorInstanceId);
    System.assert(
      result.message.containsIgnoreCase('normalized'),
      'Expected normalized config message, got: ' + result.message
    );
  }

  @IsTest
  static void migrateConnector_unknownKey_returnsFailureWithoutThrowing() {
    ConnectorRegistryService.clearCache();

    Test.startTest();
    QuickbridgeConfigMigrationService.MigrationResult result = QuickbridgeConfigMigrationService.migrateConnector(
      'totally-unknown-connector-xyz'
    );
    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assertEquals('totally-unknown-connector-xyz', result.connectorKey);
    System.assert(String.isNotBlank(result.message));
  }

  @IsTest
  static void migrateAll_onlyProcessesConnectorsWithHasConfig() {
    // Insert one connector with Has_Config__c = true and one without.
    insert new Integration_Product__c(
      Name = 'migall-cfg',
      Product_Key__c = 'migall-cfg',
      Connector_Key__c = 'migall-cfg',
      Product_Label__c = 'migall-cfg',
      Category__c = 'Test',
      Display_Order__c = 98,
      Enabled__c = true,
      Catalog_Active__c = true,
      Has_Config__c = true,
      Has_Reporting__c = false
    );
    insert new Integration_Product__c(
      Name = 'migall-nocfg',
      Product_Key__c = 'migall-nocfg',
      Connector_Key__c = 'migall-nocfg',
      Product_Label__c = 'migall-nocfg',
      Category__c = 'Test',
      Display_Order__c = 97,
      Enabled__c = true,
      Catalog_Active__c = true,
      Has_Config__c = false,
      Has_Reporting__c = false
    );
    ConnectorRegistryService.clearCache();

    Test.startTest();
    List<QuickbridgeConfigMigrationService.MigrationResult> results = QuickbridgeConfigMigrationService.migrateAll();
    Test.stopTest();

    Boolean foundCfg = false;
    Boolean foundNoCfg = false;
    for (QuickbridgeConfigMigrationService.MigrationResult r : results) {
      if (r.connectorKey == 'migall-cfg') {
        foundCfg = true;
      }
      if (r.connectorKey == 'migall-nocfg') {
        foundNoCfg = true;
      }
    }
    System.assertEquals(
      true,
      foundCfg,
      'migrateAll should include connectors with hasConfig=true'
    );
    System.assertEquals(
      false,
      foundNoCfg,
      'migrateAll should skip connectors with hasConfig=false'
    );
  }
}