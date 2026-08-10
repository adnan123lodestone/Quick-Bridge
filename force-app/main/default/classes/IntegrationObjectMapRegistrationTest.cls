@IsTest
private class IntegrationObjectMapRegistrationTest {
  @IsTest
  static void buildsDeterministicQuickBooksRegistration() {
    IntegrationObjectMapRegistrationService.testObjectMaps = new List<Integration_Object_Map__mdt>();
    Metadata.DeployContainer container = new Metadata.DeployContainer();

    Boolean added = IntegrationObjectMapRegistrationService.addMissingPair(
      container,
      'qbo',
      'Invoice',
      'Invoice'
    );
    Metadata.CustomMetadata record = IntegrationObjectMapRegistrationService.lastBuiltMetadata;

    Assert.isTrue(added);
    Assert.isNotNull(record);
    Assert.isTrue(
      record.fullName.substringAfter('.')
        .startsWith('Auto_qbo_Invoice_Invoice_')
    );
    Assert.isTrue(record.fullName.substringAfter('.').length() <= 40);
    assertValue(record, 'Connector_Key__c', 'qbonline');
    assertValue(record, 'Salesforce_Object__c', 'Invoice');
    assertValue(record, 'External_Object__c', 'Invoice');
    assertValue(record, 'Operation_Key__c', 'fieldMapping');
    assertValue(record, 'Direction__c', 'Bidirectional');
    assertValue(record, 'Active__c', true);

    Assert.areEqual(
      record.fullName.substringAfter('.'),
      IntegrationObjectMapRegistrationService.buildDeveloperName(
        'qbo',
        'Invoice',
        'Invoice'
      )
    );
  }

  @IsTest
  static void reusesActivePairAndReactivatesInactiveNamespacedPair() {
    IntegrationObjectMapRegistrationService.testNamespacePrefix = 'QuickBridgeTLG__';
    IntegrationObjectMapRegistrationService.testObjectMaps = new List<Integration_Object_Map__mdt>{
      objectMap(
        'Existing_Active',
        'Existing Active',
        'qbonline',
        'Account',
        'Customer',
        'fieldMapping',
        'Bidirectional',
        true
      )
    };

    Boolean activeAdded = IntegrationObjectMapRegistrationService.addMissingPair(
      new Metadata.DeployContainer(),
      'qbonline',
      'Account',
      'Customer'
    );
    Assert.isFalse(activeAdded);
    Assert.isNull(IntegrationObjectMapRegistrationService.lastBuiltMetadata);

    IntegrationObjectMapRegistrationService.testObjectMaps = new List<Integration_Object_Map__mdt>{
      objectMap(
        'Existing_Inactive',
        'Existing Inactive',
        'qbonline',
        'Invoice__c',
        'Invoice',
        'fieldMapping',
        'Bidirectional',
        false
      )
    };
    Boolean inactiveAdded = IntegrationObjectMapRegistrationService.addMissingPair(
      new Metadata.DeployContainer(),
      'qbonline',
      'QuickBridgeTLG__Invoice__c',
      'Invoice'
    );
    Metadata.CustomMetadata reactivated = IntegrationObjectMapRegistrationService.lastBuiltMetadata;

    Assert.isTrue(inactiveAdded);
    Assert.areEqual(
      'QuickBridgeTLG__Integration_Object_Map__mdt.Existing_Inactive',
      reactivated.fullName
    );
    Assert.areEqual('Existing Inactive', reactivated.label);
    assertValue(reactivated, 'QuickBridgeTLG__Active__c', true);
  }

  @IsTest
  static void inheritsMetaTemplateAndRejectsMissingTemplate() {
    IntegrationObjectMapRegistrationService.testObjectMaps = new List<Integration_Object_Map__mdt>{
      objectMap(
        'Meta_Campaign',
        'Meta Campaign',
        'meta',
        'Campaign',
        'campaign',
        'CampaignSync',
        'Inbound',
        true
      )
    };

    Boolean added = IntegrationObjectMapRegistrationService.addMissingPair(
      new Metadata.DeployContainer(),
      'meta',
      'Dynamic_Object__c',
      'campaign'
    );
    Assert.isTrue(added);
    assertValue(
      IntegrationObjectMapRegistrationService.lastBuiltMetadata,
      'Operation_Key__c',
      'CampaignSync'
    );
    assertValue(
      IntegrationObjectMapRegistrationService.lastBuiltMetadata,
      'Direction__c',
      'Inbound'
    );

    IntegrationObjectMapRegistrationService.testObjectMaps = new List<Integration_Object_Map__mdt>{
      objectMap(
        'Inactive_NetSuite_Pair',
        'Inactive NetSuite Pair',
        'netsuite',
        'Dynamic_Object__c',
        'LegacyEntity',
        'LegacySync',
        'Outbound',
        false
      )
    };
    Boolean reactivated = IntegrationObjectMapRegistrationService.addMissingPair(
      new Metadata.DeployContainer(),
      'netsuite',
      'Dynamic_Object__c',
      'LegacyEntity'
    );
    Assert.isTrue(reactivated);
    assertValue(
      IntegrationObjectMapRegistrationService.lastBuiltMetadata,
      'Operation_Key__c',
      'LegacySync'
    );

    Boolean didThrow = false;
    try {
      IntegrationObjectMapRegistrationService.addMissingPair(
        new Metadata.DeployContainer(),
        'netsuite',
        'Dynamic_Object__c',
        'UnknownEntity'
      );
    } catch (IntegrationObjectMapRegistrationService.RegistrationException e) {
      didThrow = e.getMessage().contains('No active');
    }
    Assert.isTrue(didThrow);
  }

  @IsTest
  static void classifiesCarrierPairsWithoutRelaxingShipmentRules() {
    IntegrationObjectMapRegistrationService.testObjectMaps = new List<Integration_Object_Map__mdt>();

    IntegrationObjectMapRegistrationService.addMissingCarrierPair(
      new Metadata.DeployContainer(),
      'fedex',
      'Case',
      'validateAddress'
    );
    Metadata.CustomMetadata packageRecord = IntegrationObjectMapRegistrationService.lastBuiltMetadata;
    assertValue(packageRecord, 'External_Object__c', 'Package');
    assertValue(packageRecord, 'Operation_Key__c', 'carrier.operation');
    assertValue(packageRecord, 'Direction__c', 'ActionOnly');

    IntegrationObjectMapRegistrationService.addMissingCarrierPair(
      new Metadata.DeployContainer(),
      'ups',
      'Carrier_Shipment__c',
      'syncTrackingStatus'
    );
    assertValue(
      IntegrationObjectMapRegistrationService.lastBuiltMetadata,
      'External_Object__c',
      'Shipment'
    );
  }

  @IsTest
  static void rejectsIncompleteRegistration() {
    IntegrationObjectMapRegistrationService.testObjectMaps = new List<Integration_Object_Map__mdt>();
    Boolean didThrow = false;
    try {
      IntegrationObjectMapRegistrationService.addMissingPair(
        new Metadata.DeployContainer(),
        'qbonline',
        '',
        'Customer'
      );
    } catch (IntegrationObjectMapRegistrationService.RegistrationException e) {
      didThrow = e.getMessage().contains('required');
    }
    Assert.isTrue(didThrow);
  }

  private static Integration_Object_Map__mdt objectMap(
    String developerName,
    String label,
    String connector,
    String salesforceObject,
    String externalObject,
    String operation,
    String direction,
    Boolean active
  ) {
    return new Integration_Object_Map__mdt(
      DeveloperName = developerName,
      MasterLabel = label,
      Connector_Key__c = connector,
      Salesforce_Object__c = salesforceObject,
      External_Object__c = externalObject,
      Operation_Key__c = operation,
      Direction__c = direction,
      Active__c = active
    );
  }

  private static void assertValue(
    Metadata.CustomMetadata record,
    String fieldName,
    Object expectedValue
  ) {
    Object actualValue;
    for (Metadata.CustomMetadataValue value : record.values) {
      if (value.field == fieldName || value.field.endsWith('__' + fieldName)) {
        actualValue = value.value;
        break;
      }
    }
    Assert.areEqual(expectedValue, actualValue, 'Unexpected ' + fieldName);
  }
}