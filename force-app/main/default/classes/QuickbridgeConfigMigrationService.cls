public with sharing class QuickbridgeConfigMigrationService {
  public class MigrationResult {
    @AuraEnabled
    public String connectorKey { get; set; }
    @AuraEnabled
    public Boolean success { get; set; }
    @AuraEnabled
    public String message { get; set; }
    @AuraEnabled
    public Id connectorInstanceId { get; set; }
    @AuraEnabled
    public Integer valuesMigrated { get; set; }
  }

  @AuraEnabled
  public static List<MigrationResult> migrateAll() {
    QuickBridgeAdminGuard.requireManage();
    List<MigrationResult> results = new List<MigrationResult>();
    for (
      ConnectorRegistryService.ConnectorDescriptor descriptor : ConnectorRegistryService.connectors()
    ) {
      if (descriptor.hasConfig == true) {
        results.add(migrateDescriptor(descriptor));
      }
    }
    return results;
  }

  @AuraEnabled
  public static MigrationResult migrateConnector(String connectorKey) {
    QuickBridgeAdminGuard.requireManage();
    ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(
      connectorKey
    );
    if (descriptor == null) {
      MigrationResult unsupported = new MigrationResult();
      unsupported.connectorKey = connectorKey;
      unsupported.success = false;
      unsupported.message =
        'Unsupported QuickBridge connector: ' + connectorKey;
      unsupported.valuesMigrated = 0;
      return unsupported;
    }
    return migrateDescriptor(descriptor);
  }

  private static MigrationResult migrateDescriptor(
    ConnectorRegistryService.ConnectorDescriptor descriptor
  ) {
    MigrationResult result = new MigrationResult();
    result.connectorKey = descriptor.connectorKey;
    result.valuesMigrated = 0;
    try {
      ConnectorConfigService.ConnectorConfig config = ConnectorConfigService.getConfig(
        descriptor.connectorKey,
        true
      );
      Connector_Instance__c instanceRecord = upsertInstance(descriptor, config);
      result.connectorInstanceId = instanceRecord.Id;
      result.valuesMigrated = upsertConfigValues(
        descriptor,
        instanceRecord.Id,
        config
      );
      result.success = true;
      result.message = config.fromNormalizedConfig == true
        ? 'Connector already uses normalized config.'
        : 'Legacy QuickBridge metadata migrated to normalized connector config.';
    } catch (Exception e) {
      result.success = false;
      result.message = e.getMessage();
      ErrorLogUtility.logException(
        'QuickBridge',
        'QuickbridgeConfigMigrationService.migrateDescriptor',
        e,
        null,
        null
      );
    }
    return result;
  }

  private static Connector_Instance__c upsertInstance(
    ConnectorRegistryService.ConnectorDescriptor descriptor,
    ConnectorConfigService.ConnectorConfig config
  ) {
    List<Connector_Instance__c> existing = [
      SELECT Id
      FROM Connector_Instance__c
      WHERE Connector_Key__c = :descriptor.connectorKey
      LIMIT 1
    ];
    Connector_Instance__c instanceRecord = existing.isEmpty()
      ? new Connector_Instance__c()
      : existing[0];
    instanceRecord.Name = descriptor.label;
    instanceRecord.Connector_Key__c = descriptor.connectorKey;
    instanceRecord.Connector_Label__c = descriptor.label;
    instanceRecord.Active__c = config.active == true;
    instanceRecord.Environment__c = config.environment;
    instanceRecord.Entitlement_Status__c = String.isBlank(
        config.entitlementStatus
      )
      ? (config.active == true ? 'Active' : 'Inactive')
      : config.entitlementStatus;
    instanceRecord.Expiry_Date__c = config.expiryDate;
    instanceRecord.Health_Status__c = String.isBlank(config.healthStatus)
      ? 'Migrated'
      : config.healthStatus;
    instanceRecord.Named_Credential__c = config.namedCredential;
    instanceRecord.External_Credential__c = config.externalCredential;
    upsert instanceRecord;
    return instanceRecord;
  }

  private static Integer upsertConfigValues(
    ConnectorRegistryService.ConnectorDescriptor descriptor,
    Id instanceId,
    ConnectorConfigService.ConnectorConfig config
  ) {
    List<Connector_Config_Value__c> valuesToUpsert = new List<Connector_Config_Value__c>();
    Set<String> fieldKeys = new Set<String>();
    for (
      ConnectorRegistryService.ConfigFieldDescriptor field : ConnectorRegistryService.configFieldsFor(
        descriptor.connectorKey
      )
    ) {
      if (
        field == null ||
        field.secret == true ||
        isSecretField(field.fieldKey) ||
        isSecretField(field.legacyFieldApiName)
      ) {
        continue;
      }
      String value = resolveValue(config, field);
      if (String.isBlank(field.fieldKey) || value == null) {
        continue;
      }
      fieldKeys.add(field.fieldKey);
      valuesToUpsert.add(
        new Connector_Config_Value__c(
          Name = descriptor.connectorKey + ':' + field.fieldKey,
          Connector_Instance__c = instanceId,
          Connector_Key__c = descriptor.connectorKey,
          Field_Key__c = field.fieldKey,
          Value__c = value,
          Is_Secret_Reference__c = false
        )
      );
    }

    if (valuesToUpsert.isEmpty()) {
      return 0;
    }

    Map<String, Id> existingIdsByFieldKey = new Map<String, Id>();
    for (Connector_Config_Value__c existing : [
      SELECT Id, Field_Key__c
      FROM Connector_Config_Value__c
      WHERE
        Connector_Key__c = :descriptor.connectorKey
        AND Field_Key__c IN :fieldKeys
    ]) {
      existingIdsByFieldKey.put(existing.Field_Key__c, existing.Id);
    }
    for (Connector_Config_Value__c valueRow : valuesToUpsert) {
      if (existingIdsByFieldKey.containsKey(valueRow.Field_Key__c)) {
        valueRow.Id = existingIdsByFieldKey.get(valueRow.Field_Key__c);
      }
    }
    upsert valuesToUpsert;
    return valuesToUpsert.size();
  }

  private static String resolveValue(
    ConnectorConfigService.ConnectorConfig config,
    ConnectorRegistryService.ConfigFieldDescriptor field
  ) {
    if (config == null || config.values == null || field == null) {
      return null;
    }
    if (config.values.containsKey(field.fieldKey)) {
      return config.values.get(field.fieldKey);
    }
    if (
      String.isNotBlank(field.legacyFieldApiName) &&
      config.values.containsKey(field.legacyFieldApiName)
    ) {
      return config.values.get(field.legacyFieldApiName);
    }
    return null;
  }

  private static Boolean isSecretField(String fieldName) {
    if (String.isBlank(fieldName)) {
      return false;
    }
    String normalized = ConnectorRegistryService.normalize(fieldName);
    return normalized.contains('secret') ||
      normalized.contains('token') ||
      normalized.contains('password') ||
      normalized.contains('privatekey') ||
      normalized.contains('clientsecret');
  }
}
