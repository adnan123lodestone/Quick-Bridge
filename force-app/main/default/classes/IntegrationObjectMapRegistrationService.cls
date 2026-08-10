public inherited sharing class IntegrationObjectMapRegistrationService {
  public class RegistrationException extends Exception {
  }

  private class RegistrationSpec {
    String operationKey;
    String direction;

    RegistrationSpec(String operationKey, String direction) {
      this.operationKey = operationKey;
      this.direction = direction;
    }
  }

  private static final Set<String> SHIPMENT_ONLY_ACTIONS = new Set<String>{
    'voidshipment',
    'synctrackingstatus'
  };

  @TestVisible
  private static List<Integration_Object_Map__mdt> testObjectMaps;
  @TestVisible
  private static String testNamespacePrefix;
  @TestVisible
  private static Metadata.CustomMetadata lastBuiltMetadata;
  private static List<Integration_Object_Map__mdt> cachedObjectMaps;

  public static Boolean addMissingPair(
    Metadata.DeployContainer container,
    String connectorKey,
    String salesforceObject,
    String externalObject
  ) {
    Integration_Object_Map__mdt existingPair = findExistingPair(
      connectorKey,
      salesforceObject,
      externalObject
    );
    if (existingPair?.Active__c == true) {
      lastBuiltMetadata = null;
      return false;
    }
    RegistrationSpec spec = existingPair != null &&
      String.isNotBlank(existingPair.Operation_Key__c) &&
      String.isNotBlank(existingPair.Direction__c)
      ? new RegistrationSpec(
          existingPair.Operation_Key__c,
          existingPair.Direction__c
        )
      : resolveSharedSpec(connectorKey, externalObject);
    return addMissingPair(
      container,
      connectorKey,
      salesforceObject,
      externalObject,
      spec.operationKey,
      spec.direction
    );
  }

  public static Boolean addMissingCarrierPair(
    Metadata.DeployContainer container,
    String connectorKey,
    String salesforceObject,
    String actionName
  ) {
    String normalizedAction = normalize(actionName);
    String externalObject = SHIPMENT_ONLY_ACTIONS.contains(normalizedAction)
      ? 'Shipment'
      : 'Package';
    return addMissingPair(
      container,
      connectorKey,
      salesforceObject,
      externalObject,
      'carrier.operation',
      'ActionOnly'
    );
  }

  @TestVisible
  private static Boolean addMissingPair(
    Metadata.DeployContainer container,
    String connectorKey,
    String salesforceObject,
    String externalObject,
    String operationKey,
    String direction
  ) {
    if (container == null) {
      throw new RegistrationException(
        'A metadata deployment container is required.'
      );
    }
    if (
      String.isBlank(connectorKey) ||
      String.isBlank(salesforceObject) ||
      String.isBlank(externalObject) ||
      String.isBlank(operationKey) ||
      String.isBlank(direction)
    ) {
      throw new RegistrationException(
        'Connector, Salesforce object, external object, operation, and direction are required to register an object pair.'
      );
    }

    Integration_Object_Map__mdt existingPair = findExistingPair(
      connectorKey,
      salesforceObject,
      externalObject
    );

    if (existingPair?.Active__c == true) {
      lastBuiltMetadata = null;
      return false;
    }

    String developerName = existingPair == null
      ? buildDeveloperName(connectorKey, salesforceObject, externalObject)
      : existingPair.DeveloperName;
    Metadata.CustomMetadata record = new Metadata.CustomMetadata();
    record.fullName =
      namespacePrefix() +
      'Integration_Object_Map__mdt.' +
      developerName;
    String label = existingPair == null
      ? connectorKey + ' ' + salesforceObject + ' ' + externalObject
      : existingPair.MasterLabel;
    record.label = label.length() > 40 ? label.substring(0, 40) : label;
    addValue(record, 'Connector_Key__c', canonicalConnector(connectorKey));
    addValue(record, 'Salesforce_Object__c', salesforceObject);
    addValue(record, 'External_Object__c', externalObject);
    addValue(record, 'Operation_Key__c', operationKey);
    addValue(record, 'Direction__c', direction);
    addValue(record, 'Active__c', true);
    container.addMetadata(record);
    lastBuiltMetadata = record;
    return true;
  }

  private static RegistrationSpec resolveSharedSpec(
    String connectorKey,
    String externalObject
  ) {
    String connector = canonicalConnector(connectorKey);
    if (connector == 'qbonline' || connector == 'shopify') {
      return new RegistrationSpec('fieldMapping', 'Bidirectional');
    }
    if (connector == 'meta' || connector == 'netsuite') {
      for (Integration_Object_Map__mdt row : objectMaps()) {
        if (
          row.Active__c == true &&
          canonicalConnector(row.Connector_Key__c) == connector &&
          normalize(row.External_Object__c) == normalize(externalObject) &&
          String.isNotBlank(row.Operation_Key__c) &&
          String.isNotBlank(row.Direction__c)
        ) {
          return new RegistrationSpec(row.Operation_Key__c, row.Direction__c);
        }
      }
      throw new RegistrationException(
        'No active ' +
          connectorKey +
          ' object-map template exists for external object ' +
          externalObject +
          '. The pair was not registered.'
      );
    }
    throw new RegistrationException(
      'Automatic object-pair registration is not supported for connector ' +
        connectorKey +
        '.'
    );
  }

  private static List<Integration_Object_Map__mdt> objectMaps() {
    if (Test.isRunningTest() && testObjectMaps != null) {
      return testObjectMaps;
    }
    if (cachedObjectMaps == null) {
      cachedObjectMaps = [
        SELECT
          DeveloperName,
          MasterLabel,
          Connector_Key__c,
          Salesforce_Object__c,
          External_Object__c,
          Operation_Key__c,
          Direction__c,
          Active__c
        FROM Integration_Object_Map__mdt
      ];
    }
    return cachedObjectMaps;
  }

  private static Integration_Object_Map__mdt findExistingPair(
    String connectorKey,
    String salesforceObject,
    String externalObject
  ) {
    for (Integration_Object_Map__mdt row : objectMaps()) {
      if (
        canonicalConnector(row.Connector_Key__c) ==
        canonicalConnector(connectorKey) &&
        canonicalObject(row.Salesforce_Object__c) ==
        canonicalObject(salesforceObject) &&
        normalize(row.External_Object__c) == normalize(externalObject)
      ) {
        return row;
      }
    }
    return null;
  }

  @TestVisible
  private static String buildDeveloperName(
    String connectorKey,
    String salesforceObject,
    String externalObject
  ) {
    String baseName =
      'Auto_' +
      connectorKey +
      '_' +
      salesforceObject +
      '_' +
      externalObject;
    baseName = baseName.replaceAll('[^a-zA-Z0-9_]', '_').replaceAll('_+', '_');
    String identity =
      canonicalConnector(connectorKey) +
      '|' +
      canonicalObject(salesforceObject) +
      '|' +
      normalize(externalObject);
    String hashSuffix =
      '_' +
      EncodingUtil.convertToHex(
          Crypto.generateDigest('MD5', Blob.valueOf(identity))
        )
        .substring(0, 8)
        .toLowerCase();
    Integer prefixLength = 40 - hashSuffix.length();
    String prefix = baseName.length() > prefixLength
      ? baseName.substring(0, prefixLength)
      : baseName;
    return prefix.replaceAll('_+$', '') + hashSuffix;
  }

  private static void addValue(
    Metadata.CustomMetadata record,
    String fieldName,
    Object value
  ) {
    Metadata.CustomMetadataValue metadataValue = new Metadata.CustomMetadataValue();
    metadataValue.field = namespacePrefix() + fieldName;
    metadataValue.value = value;
    record.values.add(metadataValue);
  }

  private static String canonicalConnector(String value) {
    String normalized = normalize(value);
    if (normalized == 'qbo' || normalized == 'quickbooks') {
      return 'qbonline';
    }
    return normalized;
  }

  private static String canonicalObject(String value) {
    if (String.isBlank(value)) {
      return '';
    }
    String trimmedValue = value.trim();
    String prefix = namespacePrefix();
    if (
      String.isNotBlank(prefix) &&
      trimmedValue.startsWith(prefix) &&
      trimmedValue.endsWith('__c')
    ) {
      return trimmedValue.substring(prefix.length()).toLowerCase();
    }
    return trimmedValue.toLowerCase();
  }

  private static String normalize(String value) {
    return String.isBlank(value)
      ? ''
      : value.toLowerCase().replaceAll('[^a-z0-9]', '');
  }

  private static String namespacePrefix() {
    if (Test.isRunningTest() && testNamespacePrefix != null) {
      return testNamespacePrefix;
    }
    String className = IntegrationObjectMapRegistrationService.class.getName();
    return className.contains('.') ? className.substringBefore('.') + '__' : '';
  }
}