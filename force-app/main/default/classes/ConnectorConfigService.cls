public without sharing class ConnectorConfigService {
  public class ConnectorConfig {
    @AuraEnabled
    public String connectorKey { get; set; }
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public Boolean active { get; set; }
    @AuraEnabled
    public String environment { get; set; }
    @AuraEnabled
    public String entitlementStatus { get; set; }
    @AuraEnabled
    public Date expiryDate { get; set; }
    @AuraEnabled
    public String healthStatus { get; set; }
    @AuraEnabled
    public String namedCredential { get; set; }
    @AuraEnabled
    public String externalCredential { get; set; }
    @AuraEnabled
    public Datetime lastHealthCheckAt { get; set; }
    @AuraEnabled
    public Datetime lastEntitlementRefreshAt { get; set; }
    @AuraEnabled
    public Map<String, String> values { get; set; }
    @AuraEnabled
    public Boolean fromNormalizedConfig { get; set; }
  }

  @AuraEnabled(cacheable=false)
  public static ConnectorConfig getPublicConfig(
    String connectorKey,
    String sessionToken
  ) {
    QuickBridgeAdminGuard.requireView();
    QuickBridgeAdminSessionService.requireValidSession(sessionToken);
    ConnectorConfig cfg = getConfig(connectorKey);
    redactSecretFields(cfg);
    return cfg;
  }

  public static ConnectorConfig getConfig(String connectorKey) {
    ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(
      connectorKey
    );
    if (descriptor == null) {
      throw new AuraHandledException(
        'Unsupported QuickBridge connector: ' + connectorKey
      );
    }

    ConnectorConfig config = new ConnectorConfig();
    config.connectorKey = descriptor.connectorKey;
    config.label = descriptor.label;
    config.values = new Map<String, String>();
    hydrateFromNormalizedConfig(config, descriptor);
    return config;
  }

  public static ConnectorConfig getAuthoritativeConfig(String connectorKey) {
    return getConfig(connectorKey);
  }

  private static void redactSecretFields(ConnectorConfig cfg) {
    if (cfg == null || cfg.values == null) {
      return;
    }
    Map<String, String> redacted = new Map<String, String>();
    for (String key : cfg.values.keySet()) {
      redacted.put(key, isSecretField(key) ? '••••••••' : cfg.values.get(key));
    }
    cfg.values = redacted;
  }

  public static String getConfigValue(
    String connectorKey,
    String fieldKeyOrLegacyName
  ) {
    ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(
      connectorKey
    );
    // Connectors not in the registry (e.g. Enabled__c = false internal connectors)
    // are not accessible via getConfig() — query Connector_Config_Value__c directly.
    if (descriptor == null) {
      return queryDirectValue(connectorKey, fieldKeyOrLegacyName);
    }
    ConnectorConfig config = getConfig(connectorKey);
    if (config.values == null) {
      return null;
    }
    if (
      String.isNotBlank(descriptor.activeField) &&
      descriptor.activeField == fieldKeyOrLegacyName
    ) {
      return String.valueOf(config.active == true);
    }
    if (
      String.isNotBlank(descriptor.expiryField) &&
      descriptor.expiryField == fieldKeyOrLegacyName
    ) {
      return config.expiryDate == null
        ? null
        : String.valueOf(config.expiryDate);
    }
    if (config.values.containsKey(fieldKeyOrLegacyName)) {
      return config.values.get(fieldKeyOrLegacyName);
    }
    for (
      ConnectorRegistryService.ConfigFieldDescriptor field : ConnectorRegistryService.configFieldsFor(
        connectorKey
      )
    ) {
      if (
        field.fieldKey == fieldKeyOrLegacyName ||
        field.legacyFieldApiName == fieldKeyOrLegacyName
      ) {
        if (config.values.containsKey(field.fieldKey))
          return config.values.get(field.fieldKey);
        if (config.values.containsKey(field.legacyFieldApiName))
          return config.values.get(field.legacyFieldApiName);
      }
    }
    return null;
  }

  private static String queryDirectValue(
    String connectorKey,
    String fieldKey
  ) {
    List<Connector_Config_Value__c> rows = [
      SELECT Value__c
      FROM Connector_Config_Value__c
      WHERE Connector_Key__c = :connectorKey AND Field_Key__c = :fieldKey
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Value__c;
  }

  public static Boolean isActive(String connectorKey) {
    ConnectorConfig config = getConfig(connectorKey);
    return config.active == true &&
      (config.expiryDate == null ||
      config.expiryDate >= Date.today());
  }

  public static void upsertNonSecretValue(
    String connectorKey,
    String fieldKey,
    String value
  ) {
    QuickBridgeAdminGuard.requireManage();
    ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(
      connectorKey
    );
    if (descriptor == null) {
      throw new AuraHandledException(
        'Unsupported QuickBridge connector: ' + connectorKey
      );
    }
    ConnectorRegistryService.ConfigFieldDescriptor fieldDescriptor;
    String normalizedFieldKey = ConnectorRegistryService.normalize(fieldKey);
    for (
      ConnectorRegistryService.ConfigFieldDescriptor field : ConnectorRegistryService.configFieldsFor(
        descriptor.connectorKey
      )
    ) {
      // Match on fieldKey or legacyFieldApiName — mdt entries use fieldKey (e.g. 'clientSecretRef')
      // while editableFields entries use the legacy API name (e.g. 'FedEx_Client_Secret__c').
      if (
        ConnectorRegistryService.normalize(field.fieldKey) == normalizedFieldKey ||
        ConnectorRegistryService.normalize(field.legacyFieldApiName) == normalizedFieldKey
      ) {
        fieldDescriptor = field;
        break;
      }
    }
    // Fields explicitly registered in the connector's configFields are sanctioned for saving.
    // Only block secret-named fields that have no registry entry at all (submitted outside
    // the normal UI flow). Registry-listed fields with secret=true are stored as plain values
    // when the admin has explicitly added them to editableFields.
    Boolean fieldInRegistry = fieldDescriptor != null;
    if (!fieldInRegistry && isSecretField(fieldKey)) {
      throw new AuraHandledException(
        'Secret values must be stored in Named Credentials or External Credentials.'
      );
    }

    Connector_Instance__c instanceRecord = ensureInstance(descriptor);
    updateInstanceState(instanceRecord, descriptor, fieldKey, value);
    List<Connector_Config_Value__c> existing = [
      SELECT Id
      FROM Connector_Config_Value__c
      WHERE
        Connector_Key__c = :descriptor.connectorKey
        AND Field_Key__c = :fieldKey
      LIMIT 1
    ];
    Connector_Config_Value__c configValue = existing.isEmpty()
      ? new Connector_Config_Value__c()
      : existing[0];
    configValue.Name = descriptor.connectorKey + ':' + fieldKey;
    configValue.Connector_Instance__c = instanceRecord.Id;
    configValue.Connector_Key__c = descriptor.connectorKey;
    configValue.Field_Key__c = fieldKey;
    configValue.Value__c = value;
    configValue.Is_Secret_Reference__c =
      fieldDescriptor != null &&
      String.isNotBlank(fieldDescriptor.dataType) &&
      fieldDescriptor.dataType.equalsIgnoreCase('SecretReference');
    upsert configValue;
    QuickBridgeAdminGuard.audit(
      'CONFIG_VALUE_UPSERT',
      descriptor.connectorKey,
      'Success',
      fieldKey,
      configValue.Id
    );
  }

  private static void updateInstanceState(
    Connector_Instance__c instanceRecord,
    ConnectorRegistryService.ConnectorDescriptor descriptor,
    String fieldKey,
    String value
  ) {
    Boolean changed = false;
    if (
      descriptor != null &&
      String.isNotBlank(descriptor.activeField) &&
      descriptor.activeField == fieldKey
    ) {
      instanceRecord.Active__c = parseBoolean(value);
      instanceRecord.Entitlement_Status__c = instanceRecord.Active__c == true
        ? 'Active'
        : 'Inactive';
      changed = true;
    }
    if (
      descriptor != null &&
      String.isNotBlank(descriptor.expiryField) &&
      descriptor.expiryField == fieldKey
    ) {
      instanceRecord.Expiry_Date__c = parseDate(value);
      changed = true;
    }
    if (changed) {
      update instanceRecord;
    }
  }

  private static void hydrateFromNormalizedConfig(
    ConnectorConfig config,
    ConnectorRegistryService.ConnectorDescriptor descriptor
  ) {
    List<Connector_Instance__c> instances = [
      SELECT
        Id,
        Connector_Key__c,
        Connector_Label__c,
        Active__c,
        Environment__c,
        Entitlement_Status__c,
        Expiry_Date__c,
        Health_Status__c,
        Named_Credential__c,
        External_Credential__c,
        Last_Health_Check_At__c,
        Last_Entitlement_Refresh_At__c
      FROM Connector_Instance__c
      WHERE Connector_Key__c = :descriptor.connectorKey
      LIMIT 1
    ];
    if (instances.isEmpty()) {
      config.fromNormalizedConfig = false;
      config.active = false;
      return;
    }

    Connector_Instance__c instanceRecord = instances[0];
    config.fromNormalizedConfig = true;
    config.active = instanceRecord.Active__c;
    config.environment = instanceRecord.Environment__c;
    config.entitlementStatus = instanceRecord.Entitlement_Status__c;
    config.expiryDate = instanceRecord.Expiry_Date__c;
    config.healthStatus = instanceRecord.Health_Status__c;
    config.namedCredential = instanceRecord.Named_Credential__c;
    config.externalCredential = instanceRecord.External_Credential__c;
    config.lastHealthCheckAt = instanceRecord.Last_Health_Check_At__c;
    config.lastEntitlementRefreshAt = instanceRecord.Last_Entitlement_Refresh_At__c;

    for (Connector_Config_Value__c valueRow : [
      SELECT Field_Key__c, Value__c, Is_Secret_Reference__c
      FROM Connector_Config_Value__c
      WHERE
        Connector_Instance__c = :instanceRecord.Id
        OR Connector_Key__c = :descriptor.connectorKey
    ]) {
      // Include the value if: it's a Named/External Credential reference, OR
      // the field name doesn't look like a secret, OR it's explicitly registered
      // in the connector's configFields (sanctioned by the registry admin).
      String rowFieldKey = valueRow.Field_Key__c;
      Boolean isRegistered = isFieldInRegistry(descriptor, rowFieldKey);
      if (
        valueRow.Is_Secret_Reference__c == true ||
        !isSecretField(rowFieldKey) ||
        isRegistered
      ) {
        config.values.put(rowFieldKey, valueRow.Value__c);
      }
    }
  }

  private static Connector_Instance__c ensureInstance(
    ConnectorRegistryService.ConnectorDescriptor descriptor
  ) {
    List<Connector_Instance__c> existing = [
      SELECT Id
      FROM Connector_Instance__c
      WHERE Connector_Key__c = :descriptor.connectorKey
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0];
    }
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = descriptor.label,
      Connector_Key__c = descriptor.connectorKey,
      Connector_Label__c = descriptor.label,
      Active__c = false,
      Entitlement_Status__c = 'Unknown',
      Health_Status__c = 'Unknown'
    );
    insert instanceRecord;
    return instanceRecord;
  }

  private static Boolean parseBoolean(String value) {
    if (String.isBlank(value)) {
      return false;
    }
    return value.equalsIgnoreCase('true') ||
      value.equalsIgnoreCase('yes') ||
      value == '1';
  }

  private static Date parseDate(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return Date.valueOf(value);
    } catch (Exception e) {
      throw new AuraHandledException('Invalid connector config date: ' + value);
    }
  }

  private static Boolean isSecretField(String fieldName) {
    String normalized = ConnectorRegistryService.normalize(fieldName);
    return normalized.contains('secret') ||
      normalized.contains('token') ||
      normalized.contains('password') ||
      normalized.contains('privatekey') ||
      normalized.contains('clientsecret');
  }

  // Public alias so PaymentMetadataService can reuse this check on the read path.
  public static Boolean isFieldInRegistryPublic(
    ConnectorRegistryService.ConnectorDescriptor descriptor,
    String fieldName
  ) {
    return isFieldInRegistry(descriptor, fieldName);
  }

  // Returns true if fieldName matches any configField entry by fieldKey or legacyFieldApiName.
  // Registry-listed fields are sanctioned for plain-value storage regardless of their name.
  private static Boolean isFieldInRegistry(
    ConnectorRegistryService.ConnectorDescriptor descriptor,
    String fieldName
  ) {
    if (descriptor == null || String.isBlank(fieldName)) return false;
    String normalized = ConnectorRegistryService.normalize(fieldName);
    for (ConnectorRegistryService.ConfigFieldDescriptor field : ConnectorRegistryService.configFieldsFor(descriptor.connectorKey)) {
      if (
        ConnectorRegistryService.normalize(field.fieldKey) == normalized ||
        ConnectorRegistryService.normalize(field.legacyFieldApiName) == normalized
      ) {
        return true;
      }
    }
    return false;
  }
}