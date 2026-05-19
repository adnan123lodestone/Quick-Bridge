@IsTest
private class IntegrationEntityRegistryTest {
  @IsTest
  static void resolvesSeededMetadataEntitiesForCurrentProducts() {
    IntegrationEntityRegistry.clearCache();

    System.assertEquals(
      'Customer',
      IntegrationEntityRegistry.resolveExternalEntity(
        'qbonline',
        'Account',
        null,
        'Invoice'
      )
    );
    System.assertEquals(
      'Product',
      IntegrationEntityRegistry.resolveExternalEntity(
        'shopify',
        'Product2',
        null,
        'Customer'
      )
    );
    System.assertEquals(
      'Invoice',
      IntegrationEntityRegistry.resolveExternalEntity(
        'qbo',
        'pkg__Invoice__c',
        null,
        'Invoice'
      )
    );
    System.assertEquals(
      'Shipment',
      IntegrationEntityRegistry.resolveExternalEntity(
        'fedex',
        'Carrier_Shipment__c',
        null,
        'Default'
      )
    );

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Integration_Object_Map__mdt
        WHERE
          Connector_Key__c = 'qbonline'
          AND Salesforce_Object__c = 'Account'
          AND External_Object__c = 'Customer'
          AND Active__c = TRUE
      ]
    );
  }

  @IsTest
  static void resolvesConfiguredEntityDefinitionsBeforeFallback() {
    insert new Integration_Entity_Definition__c(
      Name = 'Klaviyo Contact',
      Integration_Key__c = 'klaviyo',
      Salesforce_Object__c = 'Contact',
      External_Entity__c = 'Profile',
      Active__c = true
    );
    IntegrationEntityRegistry.clearCache();

    System.assertEquals(
      'Profile',
      IntegrationEntityRegistry.resolveExternalEntity(
        'klaviyo',
        'Contact',
        null,
        'Default'
      )
    );
    System.assertEquals(
      'Default',
      IntegrationEntityRegistry.resolveExternalEntity(
        'klaviyo',
        'Account',
        null,
        'Default'
      )
    );
  }
}
