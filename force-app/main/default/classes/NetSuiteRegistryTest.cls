@IsTest
private class NetSuiteRegistryTest {
  @IsTest
  static void registryExposesNetSuiteDescriptorAliasesCapabilitiesAndMaps() {
    ConnectorRegistryService.clearCache();

    ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey('ns');

    System.assertNotEquals(null, descriptor, 'NetSuite should resolve by alias.');
    System.assertEquals('netsuite', descriptor.connectorKey);
    System.assertEquals('NetSuite', descriptor.label);
    System.assertEquals('ERP', descriptor.category);
    System.assertEquals(true, descriptor.hasConfig);
    System.assertEquals(true, descriptor.hasMapping);
    System.assertEquals(true, descriptor.hasScheduler);
    System.assert(descriptor.capabilities.contains('scheduler.operation'));
    System.assert(descriptor.capabilities.contains('work.CustomerSync'));
    System.assert(descriptor.capabilities.contains('work.ItemSync'));
    System.assertEquals(
      'NetSuiteScheduledOperationAdapter',
      ConnectorRegistryService.adapterClassFor('oracle-netsuite', 'scheduler.operation')
    );
    System.assertEquals(
      'NetSuiteIntegrationWorker',
      ConnectorRegistryService.adapterClassFor('netsuite', 'work.CustomerSync')
    );
    System.assert(
      ConnectorRegistryService.externalObjectsFor('netsuite').contains('Customer'),
      'Customer object map should be registered.'
    );
    System.assert(
      ConnectorRegistryService.externalObjectsFor('netsuite').contains('Item'),
      'Item object map should be registered.'
    );

    Set<String> fieldKeys = new Set<String>();
    for (ConnectorRegistryService.ConfigFieldDescriptor field : descriptor.configFields) {
      fieldKeys.add(field.fieldKey);
    }
    System.assert(fieldKeys.contains('account_id'));
    System.assert(fieldKeys.contains('named_credential_name'));
    System.assert(fieldKeys.contains('auth_type'));
    System.assert(fieldKeys.contains('enable_customer_sync'));
    System.assert(fieldKeys.contains('enable_item_sync'));
  }
}