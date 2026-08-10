public with sharing class SalesforceObjectDiscoveryService {
  @TestVisible
  private static Map<String, Set<String>> testConfiguredExternalObjectsByObject;
  @TestVisible
  private static Set<String> testConfiguredObjectNames;

  private class DiscoveryOption implements Comparable {
    String label;
    String value;
    Boolean available;
    Boolean configured;
    Set<String> configuredExternalObjects = new Set<String>();

    public Integer compareTo(Object other) {
      DiscoveryOption otherOption = (DiscoveryOption) other;
      Integer labelComparison = safeLower(label)
        .compareTo(safeLower(otherOption.label));
      return labelComparison == 0
        ? safeLower(value).compareTo(safeLower(otherOption.value))
        : labelComparison;
    }
  }

  public static List<Map<String, Object>> discover(String connectorKey) {
    String normalizedConnector = canonicalConnectorKey(connectorKey);
    Boolean hasConnectorContext = String.isNotBlank(normalizedConnector);
    Map<String, Set<String>> configuredExternalObjectsByObject = new Map<String, Set<String>>();
    Set<String> configuredObjectNames = new Set<String>();
    Map<String, String> configuredApiNamesByCanonicalName = new Map<String, String>();

    loadConfiguredObjectMaps(
      normalizedConnector,
      configuredExternalObjectsByObject,
      configuredObjectNames,
      configuredApiNamesByCanonicalName
    );
    loadSavedMappingObjects(
      normalizedConnector,
      configuredObjectNames,
      configuredApiNamesByCanonicalName
    );
    if (Test.isRunningTest() && testConfiguredObjectNames != null) {
      for (String objectName : testConfiguredObjectNames) {
        String canonicalName = canonicalObjectName(objectName);
        configuredObjectNames.add(canonicalName);
        configuredApiNamesByCanonicalName.put(canonicalName, objectName);
      }
    }
    if (Test.isRunningTest() && testConfiguredExternalObjectsByObject != null) {
      for (String objectName : testConfiguredExternalObjectsByObject.keySet()) {
        String canonicalName = canonicalObjectName(objectName);
        configuredObjectNames.add(canonicalName);
        configuredApiNamesByCanonicalName.put(canonicalName, objectName);
        if (!configuredExternalObjectsByObject.containsKey(canonicalName)) {
          configuredExternalObjectsByObject.put(
            canonicalName,
            new Set<String>()
          );
        }
        configuredExternalObjectsByObject.get(canonicalName)
          .addAll(testConfiguredExternalObjectsByObject.get(objectName));
      }
    }

    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    Map<String, DiscoveryOption> availableByCanonicalName = new Map<String, DiscoveryOption>();

    for (Schema.SObjectType objectType : globalDescribe.values()) {
      Schema.DescribeSObjectResult objectDescribe;
      try {
        objectDescribe = objectType.getDescribe(
          SObjectDescribeOptions.DEFERRED
        );
      } catch (Exception ignored) {
        continue;
      }

      String objectApiName = objectDescribe.getName();
      String canonicalName = canonicalObjectName(objectApiName);
      Boolean configured = configuredObjectNames.contains(canonicalName);
      if (!isDiscoverableBusinessObject(objectDescribe, configured)) {
        continue;
      }

      DiscoveryOption option = new DiscoveryOption();
      option.label = objectDescribe.getLabel();
      option.value = objectApiName;
      option.available = true;
      option.configured = configured;
      if (configuredExternalObjectsByObject.containsKey(canonicalName)) {
        option.configuredExternalObjects.addAll(
          configuredExternalObjectsByObject.get(canonicalName)
        );
      }
      availableByCanonicalName.put(canonicalName, option);
    }

    List<DiscoveryOption> options = new List<DiscoveryOption>();
    options.addAll(availableByCanonicalName.values());

    if (hasConnectorContext) {
      for (String configuredObjectName : configuredObjectNames) {
        if (availableByCanonicalName.containsKey(configuredObjectName)) {
          continue;
        }
        DiscoveryOption staleOption = new DiscoveryOption();
        String configuredApiName = configuredApiNamesByCanonicalName.get(
          configuredObjectName
        );
        if (String.isBlank(configuredApiName)) {
          configuredApiName = configuredObjectName;
        }
        staleOption.label = configuredApiName + ' (Unavailable)';
        staleOption.value = configuredApiName;
        staleOption.available = false;
        staleOption.configured = true;
        if (
          configuredExternalObjectsByObject.containsKey(configuredObjectName)
        ) {
          staleOption.configuredExternalObjects.addAll(
            configuredExternalObjectsByObject.get(configuredObjectName)
          );
        }
        options.add(staleOption);
      }
    }

    options.sort();
    List<Map<String, Object>> result = new List<Map<String, Object>>();
    for (DiscoveryOption option : options) {
      List<String> externalObjects = new List<String>();
      externalObjects.addAll(option.configuredExternalObjects);
      externalObjects.sort();
      result.add(
        new Map<String, Object>{
          'label' => option.label,
          'value' => option.value,
          'available' => option.available,
          'configured' => option.configured,
          'configuredExternalObjects' => externalObjects
        }
      );
    }
    return result;
  }

  private static void loadConfiguredObjectMaps(
    String normalizedConnector,
    Map<String, Set<String>> configuredExternalObjectsByObject,
    Set<String> configuredObjectNames,
    Map<String, String> configuredApiNamesByCanonicalName
  ) {
    for (Integration_Object_Map__mdt row : [
      SELECT Connector_Key__c, Salesforce_Object__c, External_Object__c
      FROM Integration_Object_Map__mdt
      WHERE Active__c = TRUE
    ]) {
      if (
        String.isNotBlank(normalizedConnector) &&
        canonicalConnectorKey(row.Connector_Key__c) != normalizedConnector
      ) {
        continue;
      }
      addConfiguredObject(
        row.Salesforce_Object__c,
        row.External_Object__c,
        configuredExternalObjectsByObject,
        configuredObjectNames,
        configuredApiNamesByCanonicalName
      );
    }
  }

  private static void loadSavedMappingObjects(
    String normalizedConnector,
    Set<String> configuredObjectNames,
    Map<String, String> configuredApiNamesByCanonicalName
  ) {
    if (String.isBlank(normalizedConnector)) {
      return;
    }
    for (Field_Mapping__mdt row : [
      SELECT Integration__c, SF_Object__c
      FROM Field_Mapping__mdt
      WHERE Is_Active__c = TRUE
    ]) {
      if (
        canonicalConnectorKey(row.Integration__c) == normalizedConnector &&
        String.isNotBlank(row.SF_Object__c)
      ) {
        String canonicalName = canonicalObjectName(row.SF_Object__c);
        configuredObjectNames.add(canonicalName);
        configuredApiNamesByCanonicalName.put(canonicalName, row.SF_Object__c);
      }
    }
  }

  private static void addConfiguredObject(
    String objectApiName,
    String externalObject,
    Map<String, Set<String>> configuredExternalObjectsByObject,
    Set<String> configuredObjectNames,
    Map<String, String> configuredApiNamesByCanonicalName
  ) {
    if (String.isBlank(objectApiName)) {
      return;
    }
    String canonicalName = canonicalObjectName(objectApiName);
    configuredObjectNames.add(canonicalName);
    configuredApiNamesByCanonicalName.put(canonicalName, objectApiName);
    if (!configuredExternalObjectsByObject.containsKey(canonicalName)) {
      configuredExternalObjectsByObject.put(canonicalName, new Set<String>());
    }
    if (String.isNotBlank(externalObject)) {
      configuredExternalObjectsByObject.get(canonicalName).add(externalObject);
    }
  }

  private static Boolean isDiscoverableBusinessObject(
    Schema.DescribeSObjectResult objectDescribe,
    Boolean configured
  ) {
    if (
      objectDescribe == null ||
      !objectDescribe.isAccessible() ||
      !objectDescribe.isQueryable() ||
      objectDescribe.isDeprecatedAndHidden() ||
      objectDescribe.isCustomSetting()
    ) {
      return false;
    }

    String apiName = objectDescribe.getName();
    String lowerName = safeLower(apiName);
    if (
      lowerName.endsWith('__mdt') ||
      lowerName.endsWith('__e') ||
      lowerName.endsWith('__b') ||
      lowerName.endsWith('changeevent') ||
      lowerName.endsWith('history') ||
      lowerName.endsWith('share') ||
      lowerName.endsWith('feed')
    ) {
      return false;
    }

    return configured ||
      objectDescribe.isCreateable() ||
      objectDescribe.isUpdateable();
  }

  private static String canonicalConnectorKey(String connectorKey) {
    if (String.isBlank(connectorKey)) {
      return '';
    }
    ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(
      connectorKey
    );
    String resolvedKey = descriptor == null
      ? connectorKey
      : descriptor.connectorKey;
    return ConnectorRegistryService.normalize(resolvedKey);
  }

  private static String canonicalObjectName(String objectApiName) {
    if (String.isBlank(objectApiName)) {
      return '';
    }
    String trimmedName = objectApiName.trim();
    String namespacePrefix = getNamespacePrefix();
    if (
      String.isNotBlank(namespacePrefix) &&
      trimmedName.startsWith(namespacePrefix) &&
      trimmedName.endsWith('__c')
    ) {
      return trimmedName.substring(namespacePrefix.length()).toLowerCase();
    }
    return trimmedName.toLowerCase();
  }

  private static String getNamespacePrefix() {
    String className = SalesforceObjectDiscoveryService.class.getName();
    return className.contains('.') ? className.substringBefore('.') + '__' : '';
  }

  private static String safeLower(String value) {
    return String.isBlank(value) ? '' : value.toLowerCase();
  }
}