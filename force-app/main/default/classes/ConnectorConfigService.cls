public with sharing class ConnectorConfigService {
    public class ConnectorConfig {
        @AuraEnabled public String connectorKey { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public String environment { get; set; }
        @AuraEnabled public String entitlementStatus { get; set; }
        @AuraEnabled public Date expiryDate { get; set; }
        @AuraEnabled public String healthStatus { get; set; }
        @AuraEnabled public String namedCredential { get; set; }
        @AuraEnabled public String externalCredential { get; set; }
        @AuraEnabled public Datetime lastHealthCheckAt { get; set; }
        @AuraEnabled public Datetime lastEntitlementRefreshAt { get; set; }
        @AuraEnabled public Map<String, String> values { get; set; }
        @AuraEnabled public Boolean fromNormalizedConfig { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static ConnectorConfig getConfig(String connectorKey) {
        ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(connectorKey);
        if (descriptor == null) {
            throw new AuraHandledException('Unsupported QuickBridge connector: ' + connectorKey);
        }

        ConnectorConfig config = new ConnectorConfig();
        config.connectorKey = descriptor.connectorKey;
        config.label = descriptor.label;
        config.values = new Map<String, String>();
        hydrateFromNormalizedConfig(config, descriptor);
        if (config.fromNormalizedConfig != true) {
            hydrateFromLegacyConfig(config, descriptor);
        }
        return config;
    }

    public static String getConfigValue(String connectorKey, String fieldKeyOrLegacyName) {
        ConnectorConfig config = getConfig(connectorKey);
        if (config.values == null) {
            return null;
        }
        if (config.values.containsKey(fieldKeyOrLegacyName)) {
            return config.values.get(fieldKeyOrLegacyName);
        }
        for (ConnectorRegistryService.ConfigFieldDescriptor field : ConnectorRegistryService.configFieldsFor(connectorKey)) {
            if (field.fieldKey == fieldKeyOrLegacyName || field.legacyFieldApiName == fieldKeyOrLegacyName) {
                if (config.values.containsKey(field.fieldKey)) return config.values.get(field.fieldKey);
                if (config.values.containsKey(field.legacyFieldApiName)) return config.values.get(field.legacyFieldApiName);
            }
        }
        return null;
    }

    public static Boolean isActive(String connectorKey) {
        ConnectorConfig config = getConfig(connectorKey);
        return config.active == true && (config.expiryDate == null || config.expiryDate >= Date.today());
    }

    public static void upsertNonSecretValue(String connectorKey, String fieldKey, String value) {
        QuickBridgeAdminGuard.requireManage();
        ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(connectorKey);
        if (descriptor == null) {
            throw new AuraHandledException('Unsupported QuickBridge connector: ' + connectorKey);
        }
        ConnectorRegistryService.ConfigFieldDescriptor fieldDescriptor;
        for (ConnectorRegistryService.ConfigFieldDescriptor field : ConnectorRegistryService.configFieldsFor(descriptor.connectorKey)) {
            if (field.fieldKey == fieldKey) {
                fieldDescriptor = field;
                break;
            }
        }
        if ((fieldDescriptor != null && fieldDescriptor.secret == true) || isSecretField(fieldKey)) {
            throw new AuraHandledException('Secret values must be stored in Named Credentials or External Credentials.');
        }

        Connector_Instance__c instanceRecord = ensureInstance(descriptor);
        List<Connector_Config_Value__c> existing = [
            SELECT Id
            FROM Connector_Config_Value__c
            WHERE Connector_Key__c = :descriptor.connectorKey
            AND Field_Key__c = :fieldKey
            LIMIT 1
        ];
        Connector_Config_Value__c configValue = existing.isEmpty() ? new Connector_Config_Value__c() : existing[0];
        configValue.Name = descriptor.connectorKey + ':' + fieldKey;
        configValue.Connector_Instance__c = instanceRecord.Id;
        configValue.Connector_Key__c = descriptor.connectorKey;
        configValue.Field_Key__c = fieldKey;
        configValue.Value__c = value;
        configValue.Is_Secret_Reference__c = false;
        upsert configValue;
        QuickBridgeAdminGuard.audit('CONFIG_VALUE_UPSERT', descriptor.connectorKey, 'Success', fieldKey, configValue.Id);
    }

    private static void hydrateFromNormalizedConfig(ConnectorConfig config, ConnectorRegistryService.ConnectorDescriptor descriptor) {
        List<Connector_Instance__c> instances = [
            SELECT Id, Connector_Key__c, Connector_Label__c, Active__c, Environment__c, Entitlement_Status__c,
                Expiry_Date__c, Health_Status__c, Named_Credential__c, External_Credential__c,
                Last_Health_Check_At__c, Last_Entitlement_Refresh_At__c
            FROM Connector_Instance__c
            WHERE Connector_Key__c = :descriptor.connectorKey
            LIMIT 1
        ];
        if (instances.isEmpty()) {
            config.fromNormalizedConfig = false;
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
            WHERE Connector_Instance__c = :instanceRecord.Id
            OR Connector_Key__c = :descriptor.connectorKey
        ]) {
            if (valueRow.Is_Secret_Reference__c == true || !isSecretField(valueRow.Field_Key__c)) {
                config.values.put(valueRow.Field_Key__c, valueRow.Value__c);
            }
        }
    }

    private static void hydrateFromLegacyConfig(ConnectorConfig config, ConnectorRegistryService.ConnectorDescriptor descriptor) {
        Quickbridge_Config__mdt legacy = legacyConfig(descriptor.configRecordName);
        if (legacy == null) {
            config.active = false;
            config.fromNormalizedConfig = false;
            return;
        }
        Map<String, Object> raw = legacy.getPopulatedFieldsAsMap();
        config.active = getBoolean(raw, descriptor.activeField);
        config.expiryDate = getDate(raw, descriptor.expiryField);
        config.environment = String.valueOf(raw.get('Environment__c'));
        config.entitlementStatus = config.active == true ? 'Active' : 'Inactive';
        config.healthStatus = 'Legacy';
        config.fromNormalizedConfig = false;

        for (ConnectorRegistryService.ConfigFieldDescriptor field : ConnectorRegistryService.configFieldsFor(descriptor.connectorKey)) {
            String fieldName = String.isBlank(field.legacyFieldApiName) ? field.fieldKey : field.legacyFieldApiName;
            if (String.isBlank(fieldName) || field.secret == true || isSecretField(fieldName)) {
                continue;
            }
            if (raw.containsKey(fieldName) && raw.get(fieldName) != null) {
                config.values.put(field.fieldKey, String.valueOf(raw.get(fieldName)));
                config.values.put(fieldName, String.valueOf(raw.get(fieldName)));
            }
        }
    }

    private static Connector_Instance__c ensureInstance(ConnectorRegistryService.ConnectorDescriptor descriptor) {
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

    private static Quickbridge_Config__mdt legacyConfig(String recordName) {
        if (String.isBlank(recordName)) {
            recordName = 'Default';
        }
        try {
            List<Quickbridge_Config__mdt> rows = [
                SELECT QualifiedApiName, Company_Name__c, QuickBooks_Realm_ID__c, QuickBooks_Is_Active__c,
                    QuickBooks_Start_Date__c, QuickBooks_End_Date__c, Shopify_Store_URL__c, Shopify_Is_Active__c,
                    Shopify_Start_Date__c, Shopify_End_Date__c, Stripe_Publishable_Key__c, Stripe_Active__c,
                    Stripe_Use_Sandbox__c, Stripe_Start_Date__c, Stripe_End_Date__c, AuthorizeNet_API_Login_ID__c,
                    AuthorizeNet_Public_Client_Key__c, AuthorizeNet_Active__c, AuthorizeNet_Use_Sandbox__c,
                    AuthorizeNet_Start_Date__c, AuthorizeNet_End_Date__c, PayPal_ClientId__c, PayPal_Active__c,
                    PayPal_UseSandbox__c, PayPal_StartDate__c, PayPal_EndDate__c, FedEx_Account_Number__c,
                    FedEx_Environment__c, FedEx_Active__c, FedEx_Start_Date__c, FedEx_End_Date__c,
                    UPS_Account_Number__c, UPS_Environment__c, UPS_Active__c, UPS_Start_Date__c, UPS_End_Date__c
                FROM Quickbridge_Config__mdt
                WHERE QualifiedApiName = :recordName
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        } catch (Exception ignored) {
            return null;
        }
    }

    private static Boolean getBoolean(Map<String, Object> raw, String fieldName) {
        Object value = raw == null || String.isBlank(fieldName) ? null : raw.get(fieldName);
        return value instanceof Boolean ? (Boolean)value : false;
    }

    private static Date getDate(Map<String, Object> raw, String fieldName) {
        Object value = raw == null || String.isBlank(fieldName) ? null : raw.get(fieldName);
        return value instanceof Date ? (Date)value : null;
    }

    private static Boolean isSecretField(String fieldName) {
        String normalized = ConnectorRegistryService.normalize(fieldName);
        return normalized.contains('secret') || normalized.contains('token') || normalized.contains('password') || normalized.contains('privatekey') || normalized.contains('clientsecret');
    }
}