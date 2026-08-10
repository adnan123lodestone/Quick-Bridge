@IsTest
private class SalesforceObjectDiscoveryServiceTest {
  @IsTest
  static void discoversBusinessObjectsOutsideLegacyAllowList() {
    List<Map<String, Object>> options = SalesforceObjectDiscoveryService.discover(
      null
    );
    Set<String> normalizedValues = normalizedValues(options);

    System.assert(
      normalizedValues.contains('integration_work_item__c'),
      'An accessible custom business object outside the old allow-list should be discovered.'
    );
    Map<String, Object> customObjectOption = findOption(
      options,
      'Integration_Work_Item__c'
    );
    System.assertEquals(
      Integration_Work_Item__c.SObjectType.getDescribe().getName(),
      customObjectOption.get('value'),
      'Discovery must return the org\'s actual namespaced API name.'
    );
    System.assert(
      !normalizedValues.contains('field_mapping__mdt'),
      'Custom metadata types must not appear in business-object discovery.'
    );
    System.assert(!normalizedValues.contains('accounthistory'));
    System.assert(!normalizedValues.contains('accountshare'));
    System.assert(!normalizedValues.contains('accountfeed'));
    System.assert(!normalizedValues.contains('apexclass'));
    System.assert(!normalizedValues.contains('apextrigger'));
    System.assert(
      normalizedValues.contains('account'),
      'Existing standard objects must remain available.'
    );
  }

  @IsTest
  static void returnsDeterministicSortedOptions() {
    List<Map<String, Object>> options = SalesforceObjectDiscoveryService.discover(
      null
    );

    for (Integer index = 1; index < options.size(); index++) {
      String previousLabel = ((String) options[index - 1].get('label'))
        .toLowerCase();
      String currentLabel = ((String) options[index].get('label'))
        .toLowerCase();
      Integer labelComparison = previousLabel.compareTo(currentLabel);
      System.assert(
        labelComparison < 0 ||
        (labelComparison == 0 &&
        ((String) options[index - 1].get('value'))
          .toLowerCase()
          .compareTo(((String) options[index].get('value')).toLowerCase()) <=
        0),
        'Discovery options must be sorted by label and API name.'
      );
    }
  }

  @IsTest
  static void marksConfiguredPairsAndMissingObjects() {
    SalesforceObjectDiscoveryService.testConfiguredObjectNames = new Set<String>{
      'Missing_Customer_Object__c'
    };
    SalesforceObjectDiscoveryService.testConfiguredExternalObjectsByObject = new Map<String, Set<String>>{
      'Account' => new Set<String>{ 'Customer' },
      'Missing_Customer_Object__c' => new Set<String>{ 'Customer' }
    };

    List<Map<String, Object>> options = SalesforceObjectDiscoveryService.discover(
      'qbonline'
    );
    Map<String, Object> accountOption = findOption(options, 'Account');
    Map<String, Object> missingOption = findOption(
      options,
      'Missing_Customer_Object__c'
    );

    System.assertEquals(true, accountOption.get('available'));
    System.assertEquals(true, accountOption.get('configured'));
    System.assert(
      ((List<String>) accountOption.get('configuredExternalObjects'))
        .contains('Customer')
    );
    System.assertEquals(false, missingOption.get('available'));
    System.assertEquals(true, missingOption.get('configured'));
    System.assert(
      ((String) missingOption.get('label')).contains('(Unavailable)')
    );
  }

  @IsTest
  static void retainsConfiguredReadOnlyBusinessObjects() {
    SalesforceObjectDiscoveryService.testConfiguredExternalObjectsByObject = new Map<String, Set<String>>{
      'AcceptedEventRelation' => new Set<String>{ 'Customer' }
    };

    Map<String, Object> option = findOption(
      SalesforceObjectDiscoveryService.discover('qbonline'),
      'AcceptedEventRelation'
    );

    System.assertEquals(true, option.get('available'));
    System.assertEquals(true, option.get('configured'));
    System.assert(
      ((List<String>) option.get('configuredExternalObjects'))
        .contains('Customer')
    );
  }

  @IsTest
  static void legacyControllerContractRemainsLabelValueOnly() {
    List<Map<String, String>> options = FieldMappingController.getSalesforceObjects();
    System.assert(!options.isEmpty());
    for (Map<String, String> option : options) {
      System.assertEquals(new Set<String>{ 'label', 'value' }, option.keySet());
    }
  }

  private static Set<String> normalizedValues(
    List<Map<String, Object>> options
  ) {
    Set<String> values = new Set<String>();
    for (Map<String, Object> option : options) {
      String value = ((String) option.get('value')).toLowerCase();
      if (value.endsWith('__c') && value.countMatches('__') > 1) {
        value = value.substringAfter('__');
      }
      values.add(value);
    }
    return values;
  }

  private static Map<String, Object> findOption(
    List<Map<String, Object>> options,
    String objectName
  ) {
    for (Map<String, Object> option : options) {
      String value = (String) option.get('value');
      if (value == objectName || value.endsWith('__' + objectName)) {
        return option;
      }
    }
    System.assert(false, 'Expected discovery option for ' + objectName);
    return null;
  }
}