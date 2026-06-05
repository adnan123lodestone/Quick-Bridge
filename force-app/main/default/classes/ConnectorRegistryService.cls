public with sharing class ConnectorRegistryService {
    public class ConfigFieldDescriptor {
        @AuraEnabled public String connectorKey { get; set; }
        @AuraEnabled public String fieldKey { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String dataType { get; set; }
        @AuraEnabled public Boolean required { get; set; }
        @AuraEnabled public Boolean secret { get; set; }
        @AuraEnabled public String legacyFieldApiName { get; set; }
        @AuraEnabled public Integer sortOrder { get; set; }
    }

    public class ObjectMapDescriptor {
        @AuraEnabled public String connectorKey { get; set; }
        @AuraEnabled public String salesforceObject { get; set; }
        @AuraEnabled public String externalObject { get; set; }
        @AuraEnabled public String direction { get; set; }
        @AuraEnabled public String operationKey { get; set; }
    }

    public class ConnectorDescriptor {
        @AuraEnabled public String connectorKey { get; set; }
        @AuraEnabled public String productKey { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String aliases { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String iconName { get; set; }
        @AuraEnabled public String logoUrl { get; set; }
        @AuraEnabled public Integer sortOrder { get; set; }
        @AuraEnabled public String entitlementKey { get; set; }
        @AuraEnabled public String configSchemaKey { get; set; }
        @AuraEnabled public String configRecordName { get; set; }
        @AuraEnabled public String integrationType { get; set; }
        @AuraEnabled public String activeField { get; set; }
        @AuraEnabled public String expiryField { get; set; }
        @AuraEnabled public List<String> editableFields { get; set; }
        @AuraEnabled public Boolean enabled { get; set; }
        @AuraEnabled public Boolean catalogActive { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public List<String> capabilities { get; set; }
        @AuraEnabled public Map<String, String> adapterClassByCapability { get; set; }
        @AuraEnabled public List<ConfigFieldDescriptor> configFields { get; set; }
        @AuraEnabled public List<ObjectMapDescriptor> objectMappings { get; set; }

        @AuraEnabled public Boolean hasConfig { get; set; }
        @AuraEnabled public Boolean hasReporting { get; set; }
        @AuraEnabled public Boolean hasMapping { get; set; }
        @AuraEnabled public Boolean hasScheduler { get; set; }
        @AuraEnabled public Boolean hasCheckout { get; set; }
        @AuraEnabled public Boolean hasPayment { get; set; }
        @AuraEnabled public Boolean hasCarrier { get; set; }
        @AuraEnabled public Boolean countsTowardScheduleLimit { get; set; }
    }

    private static List<ConnectorDescriptor> cachedDescriptors;
    private static Map<String, ConnectorDescriptor> cachedByNormalizedKey;

    @AuraEnabled(cacheable=true)
    public static List<ConnectorDescriptor> getConnectorDescriptors() {
        return connectors();
    }

    public static List<ConnectorDescriptor> connectors() {
        if (cachedDescriptors == null) {
            cachedDescriptors = loadDescriptors();
            cachedByNormalizedKey = new Map<String, ConnectorDescriptor>();
            for (ConnectorDescriptor descriptor : cachedDescriptors) {
                indexDescriptor(descriptor);
            }
        }
        return cloneConnectors(cachedDescriptors);
    }

    public static ConnectorDescriptor byKey(String keyOrAlias) {
        if (cachedDescriptors == null) {
            connectors();
        }
        String normalized = normalize(keyOrAlias);
        return cachedByNormalizedKey.containsKey(normalized) ? cloneConnector(cachedByNormalizedKey.get(normalized)) : null;
    }

    public static List<ConnectorDescriptor> byCapability(String capabilityKey) {
        String normalizedCapability = normalizeCapability(capabilityKey);
        List<ConnectorDescriptor> result = new List<ConnectorDescriptor>();
        for (ConnectorDescriptor descriptor : connectors()) {
            for (String capability : descriptor.capabilities == null ? new List<String>() : descriptor.capabilities) {
                if (normalizeCapability(capability) == normalizedCapability) {
                    result.add(descriptor);
                    break;
                }
            }
        }
        return result;
    }

    public static String adapterClassFor(String connectorKey, String capabilityKey) {
        ConnectorDescriptor descriptor = byKey(connectorKey);
        if (descriptor == null || descriptor.adapterClassByCapability == null) {
            return null;
        }
        String direct = descriptor.adapterClassByCapability.get(capabilityKey);
        if (String.isNotBlank(direct)) {
            return direct;
        }
        String normalizedCapability = normalizeCapability(capabilityKey);
        for (String keyValue : descriptor.adapterClassByCapability.keySet()) {
            if (normalizeCapability(keyValue) == normalizedCapability) {
                return descriptor.adapterClassByCapability.get(keyValue);
            }
        }
        return defaultAdapterClass(descriptor.connectorKey, capabilityKey);
    }

    public static String integrationTypeFor(String keyOrAlias) {
        ConnectorDescriptor descriptor = byKey(keyOrAlias);
        if (descriptor == null) {
            return keyOrAlias;
        }
        return String.isBlank(descriptor.integrationType) ? descriptor.label : descriptor.integrationType;
    }

    public static String connectorKeyForIntegrationType(String integrationType) {
        if (String.isBlank(integrationType)) {
            return integrationType;
        }
        ConnectorDescriptor direct = byKey(integrationType);
        if (direct != null) {
            return direct.connectorKey;
        }

        String normalized = normalize(integrationType);
        for (ConnectorDescriptor descriptor : connectors()) {
            if (
                normalize(descriptor.integrationType) == normalized ||
                normalize(descriptor.label) == normalized ||
                normalize(descriptor.productKey) == normalized ||
                normalize(descriptor.connectorKey) == normalized
            ) {
                return descriptor.connectorKey;
            }
        }
        return integrationType;
    }

    public static Boolean countsTowardScheduleLimit(String keyOrAlias) {
        ConnectorDescriptor descriptor = byKey(keyOrAlias);
        if (descriptor == null) {
            descriptor = byKey(connectorKeyForIntegrationType(keyOrAlias));
        }
        return descriptor != null && descriptor.countsTowardScheduleLimit == true;
    }

    public static List<ConfigFieldDescriptor> configFieldsFor(String connectorKey) {
        ConnectorDescriptor descriptor = byKey(connectorKey);
        return descriptor == null ? new List<ConfigFieldDescriptor>() : cloneConfigFields(descriptor.configFields);
    }

    public static Map<String, String> salesforceToExternalObjectMap(String connectorKey) {
        ConnectorDescriptor descriptor = byKey(connectorKey);
        Map<String, String> result = new Map<String, String>();
        if (descriptor == null) {
            return result;
        }
        for (ObjectMapDescriptor mapRow : descriptor.objectMappings == null ? new List<ObjectMapDescriptor>() : descriptor.objectMappings) {
            if (String.isNotBlank(mapRow.salesforceObject) && String.isNotBlank(mapRow.externalObject)) {
                result.put(mapRow.salesforceObject, mapRow.externalObject);
            }
        }
        return result;
    }

    public static Set<String> externalObjectsFor(String connectorKey) {
        Set<String> result = new Set<String>();
        ConnectorDescriptor descriptor = byKey(connectorKey);
        if (descriptor == null) {
            return result;
        }
        for (ObjectMapDescriptor mapRow : descriptor.objectMappings == null ? new List<ObjectMapDescriptor>() : descriptor.objectMappings) {
            if (String.isNotBlank(mapRow.externalObject)) {
                result.add(mapRow.externalObject);
            }
        }
        return result;
    }

    public static String normalize(String value) {
        return String.isBlank(value) ? '' : value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    public static void clearCache() {
        cachedDescriptors = null;
        cachedByNormalizedKey = null;
    }

    private static List<ConnectorDescriptor> loadDescriptors() {
        // Metadata is the canonical source for capabilities, config fields, and object maps.
        // Product object records overlay presentation fields (logo, dates, status, display order).
        List<ConnectorDescriptor> descriptors = loadMetadataDescriptors();
        if (descriptors.isEmpty()) {
            descriptors = LegacyConnectorRegistryFallback.connectors();
        }
        overlayProductDescriptors(descriptors);
        hydrateCapabilities(descriptors);
        hydrateConfigFields(descriptors);
        hydrateObjectMaps(descriptors);
        return descriptors;
    }

    private static void overlayProductDescriptors(List<ConnectorDescriptor> base) {
        List<Integration_Product__c> productRows;
        try {
            productRows = [
                SELECT Product_Key__c, Connector_Key__c, Product_Label__c, Aliases__c, Category__c,
                    Config_Record_Name__c, Active_Field__c, Expiry_Field__c, Editable_Fields__c,
                    Display_Order__c, Enabled__c, Catalog_Active__c, Has_Config__c, Has_Reporting__c,
                    Has_Mapping__c, Has_Scheduler__c, Has_Checkout__c, Has_Payment__c, Has_Carrier__c,
                    Logo_URL__c, Start_Date__c, End_Date__c, Status__c
                FROM Integration_Product__c
                WHERE Enabled__c = true
                ORDER BY Display_Order__c ASC, Product_Label__c ASC
            ];
        } catch (Exception ignored) {
            return;
        }
        Map<String, ConnectorDescriptor> byKey = byConnectorKey(base);
        for (Integration_Product__c row : productRows) {
            String normalizedConnectorKey = normalize(String.isBlank(row.Connector_Key__c) ? row.Product_Key__c : row.Connector_Key__c);
            ConnectorDescriptor existing = byKey.get(normalizedConnectorKey);
            if (existing != null) {
                // Overlay presentation fields only — do not replace capabilities or config field definitions
                existing.logoUrl = row.Logo_URL__c;
                existing.catalogActive = row.Catalog_Active__c == true;
                existing.startDate = row.Start_Date__c;
                existing.endDate = row.End_Date__c;
                existing.status = row.Status__c;
                if (row.Display_Order__c != null) {
                    existing.sortOrder = row.Display_Order__c.intValue();
                }
            } else {
                // Net-new product not in metadata — add it
                ConnectorDescriptor descriptor = baseDescriptor(
                    row.Connector_Key__c,
                    row.Product_Key__c,
                    row.Product_Label__c,
                    row.Aliases__c,
                    row.Category__c,
                    row.Config_Record_Name__c,
                    row.Product_Label__c,
                    row.Active_Field__c,
                    row.Expiry_Field__c,
                    row.Editable_Fields__c,
                    row.Display_Order__c == null ? 999 : row.Display_Order__c.intValue(),
                    row.Has_Config__c == true,
                    row.Has_Reporting__c == true,
                    row.Has_Mapping__c == true,
                    row.Has_Scheduler__c == true,
                    row.Has_Checkout__c == true,
                    row.Has_Payment__c == true,
                    row.Has_Carrier__c == true,
                    row.Has_Scheduler__c == true
                );
                descriptor.logoUrl = row.Logo_URL__c;
                descriptor.catalogActive = row.Catalog_Active__c == true;
                descriptor.startDate = row.Start_Date__c;
                descriptor.endDate = row.End_Date__c;
                descriptor.status = row.Status__c;
                base.add(descriptor);
                byKey.put(normalizedConnectorKey, descriptor);
                if (String.isNotBlank(row.Product_Key__c)) {
                    byKey.put(normalize(row.Product_Key__c), descriptor);
                }
            }
        }
    }

    private static List<ConnectorDescriptor> loadMetadataDescriptors() {
        List<ConnectorDescriptor> rows = new List<ConnectorDescriptor>();
        try {
            for (Integration_Connector__mdt row : [
                SELECT Connector_Key__c, Product_Key__c, Provider_Label__c, Aliases__c, Category__c,
                    Integration_Type__c, Counts_Toward_Schedule_Limit__c,
                    Config_Record_Name__c, Active_Field__c, Expiry_Field__c, Editable_Fields__c,
                    Display_Order__c, Enabled__c, Has_Config__c, Has_Reporting__c, Has_Mapping__c,
                    Has_Scheduler__c, Has_Checkout__c, Has_Payment__c, Has_Carrier__c
                FROM Integration_Connector__mdt
                WHERE Enabled__c = true
                ORDER BY Display_Order__c ASC, Provider_Label__c ASC
            ]) {
                rows.add(baseDescriptor(
                    row.Connector_Key__c,
                    row.Product_Key__c,
                    row.Provider_Label__c,
                    row.Aliases__c,
                    row.Category__c,
                    row.Config_Record_Name__c,
                    row.Integration_Type__c,
                    row.Active_Field__c,
                    row.Expiry_Field__c,
                    row.Editable_Fields__c,
                    row.Display_Order__c == null ? 999 : row.Display_Order__c.intValue(),
                    row.Has_Config__c == true,
                    row.Has_Reporting__c == true,
                    row.Has_Mapping__c == true,
                    row.Has_Scheduler__c == true,
                    row.Has_Checkout__c == true,
                    row.Has_Payment__c == true,
                    row.Has_Carrier__c == true,
                    row.Counts_Toward_Schedule_Limit__c == true
                ));
            }
        } catch (Exception ignored) {
        }
        return rows;
    }

    private static void hydrateCapabilities(List<ConnectorDescriptor> descriptors) {
        Map<String, ConnectorDescriptor> byKey = byConnectorKey(descriptors);
        try {
            for (Integration_Connector_Capability__mdt row : [
                SELECT Connector_Key__c, Capability_Key__c, Adapter_Class__c, Enabled__c, Sort_Order__c
                FROM Integration_Connector_Capability__mdt
                WHERE Enabled__c = true
                ORDER BY Sort_Order__c ASC
            ]) {
                ConnectorDescriptor descriptor = byKey.get(normalize(row.Connector_Key__c));
                if (descriptor == null || String.isBlank(row.Capability_Key__c)) {
                    continue;
                }
                addCapability(descriptor, row.Capability_Key__c, row.Adapter_Class__c);
            }
        } catch (Exception ignored) {
        }

        for (ConnectorDescriptor descriptor : descriptors) {
            addLegacyCapabilities(descriptor);
        }
    }

    private static void hydrateConfigFields(List<ConnectorDescriptor> descriptors) {
        Map<String, ConnectorDescriptor> byKey = byConnectorKey(descriptors);
        try {
            for (Connector_Config_Field__mdt row : [
                SELECT Connector_Key__c, Field_Key__c, Label__c, Data_Type__c, Required__c, Secret__c,
                    Legacy_Field_API_Name__c, Sort_Order__c
                FROM Connector_Config_Field__mdt
                ORDER BY Sort_Order__c ASC
            ]) {
                ConnectorDescriptor descriptor = byKey.get(normalize(row.Connector_Key__c));
                if (descriptor == null) {
                    continue;
                }
                ConfigFieldDescriptor field = new ConfigFieldDescriptor();
                field.connectorKey = descriptor.connectorKey;
                field.fieldKey = row.Field_Key__c;
                field.label = row.Label__c;
                field.dataType = row.Data_Type__c;
                field.required = row.Required__c == true;
                field.secret = row.Secret__c == true;
                field.legacyFieldApiName = row.Legacy_Field_API_Name__c;
                field.sortOrder = row.Sort_Order__c == null ? 999 : row.Sort_Order__c.intValue();
                descriptor.configFields.add(field);
            }
        } catch (Exception ignored) {
        }

        for (ConnectorDescriptor descriptor : descriptors) {
            Integer orderValue = descriptor.configFields.size();
            for (String fieldName : descriptor.editableFields == null ? new List<String>() : descriptor.editableFields) {
                if (hasConfigField(descriptor, fieldName)) {
                    continue;
                }
                ConfigFieldDescriptor field = new ConfigFieldDescriptor();
                field.connectorKey = descriptor.connectorKey;
                field.fieldKey = fieldName;
                field.label = fieldName.replace('__c', '').replace('_', ' ');
                field.dataType = 'Legacy';
                field.required = false;
                // editableFields are explicitly declared as UI-editable by the registry admin.
                // Do not auto-mark them secret by name — secret status requires an explicit
                // Connector_Config_Field__mdt row with Secret__c = true.
                field.secret = false;
                field.legacyFieldApiName = fieldName;
                field.sortOrder = orderValue++;
                descriptor.configFields.add(field);
            }
        }
    }

    private static Boolean hasConfigField(ConnectorDescriptor descriptor, String fieldName) {
        String normalized = normalize(fieldName);
        for (ConfigFieldDescriptor field : descriptor.configFields == null ? new List<ConfigFieldDescriptor>() : descriptor.configFields) {
            if (normalize(field.fieldKey) == normalized || normalize(field.legacyFieldApiName) == normalized) {
                return true;
            }
        }
        return false;
    }

    private static void hydrateObjectMaps(List<ConnectorDescriptor> descriptors) {
        Map<String, ConnectorDescriptor> byKey = byConnectorKey(descriptors);
        try {
            for (Integration_Object_Map__mdt row : [
                SELECT Connector_Key__c, Salesforce_Object__c, External_Object__c, Direction__c, Operation_Key__c, Active__c
                FROM Integration_Object_Map__mdt
                WHERE Active__c = true
            ]) {
                ConnectorDescriptor descriptor = byKey.get(normalize(row.Connector_Key__c));
                if (descriptor == null) {
                    continue;
                }
                ObjectMapDescriptor mapRow = new ObjectMapDescriptor();
                mapRow.connectorKey = descriptor.connectorKey;
                mapRow.salesforceObject = row.Salesforce_Object__c;
                mapRow.externalObject = row.External_Object__c;
                mapRow.direction = row.Direction__c;
                mapRow.operationKey = row.Operation_Key__c;
                descriptor.objectMappings.add(mapRow);
            }
        } catch (Exception ignored) {
        }

        for (ConnectorDescriptor descriptor : descriptors) {
            if (descriptor.objectMappings.isEmpty()) {
                addFallbackObjectMaps(descriptor);
            }
        }
    }

    private static ConnectorDescriptor baseDescriptor(
        String connectorKey,
        String productKey,
        String label,
        String aliases,
        String category,
        String configRecordName,
        String integrationType,
        String activeField,
        String expiryField,
        String editableFields,
        Integer sortOrder,
        Boolean hasConfig,
        Boolean hasReporting,
        Boolean hasMapping,
        Boolean hasScheduler,
        Boolean hasCheckout,
        Boolean hasPayment,
        Boolean hasCarrier,
        Boolean countsTowardScheduleLimit
    ) {
        ConnectorDescriptor descriptor = new ConnectorDescriptor();
        descriptor.connectorKey = String.isBlank(connectorKey) ? productKey : connectorKey;
        descriptor.productKey = String.isBlank(productKey) ? descriptor.connectorKey : productKey;
        descriptor.label = label;
        descriptor.aliases = aliases;
        descriptor.category = category;
        descriptor.iconName = defaultIconName(category);
        descriptor.logoUrl = null;
        descriptor.sortOrder = sortOrder == null ? 999 : sortOrder;
        descriptor.entitlementKey = descriptor.productKey;
        descriptor.configSchemaKey = descriptor.connectorKey;
        descriptor.configRecordName = configRecordName;
        descriptor.integrationType = String.isBlank(integrationType) ? label : integrationType;
        descriptor.activeField = activeField;
        descriptor.expiryField = expiryField;
        descriptor.editableFields = splitList(editableFields);
        descriptor.enabled = true;
        descriptor.catalogActive = true;
        descriptor.status = 'Available';
        descriptor.capabilities = new List<String>();
        descriptor.adapterClassByCapability = new Map<String, String>();
        descriptor.configFields = new List<ConfigFieldDescriptor>();
        descriptor.objectMappings = new List<ObjectMapDescriptor>();
        descriptor.hasConfig = hasConfig == true;
        descriptor.hasReporting = hasReporting == true;
        descriptor.hasMapping = hasMapping == true;
        descriptor.hasScheduler = hasScheduler == true;
        descriptor.hasCheckout = hasCheckout == true;
        descriptor.hasPayment = hasPayment == true;
        descriptor.hasCarrier = hasCarrier == true;
        descriptor.countsTowardScheduleLimit = countsTowardScheduleLimit == true;
        return descriptor;
    }

    private static void addLegacyCapabilities(ConnectorDescriptor descriptor) {
        if (descriptor.hasConfig == true) addCapability(descriptor, 'config.admin', null);
        if (descriptor.hasReporting == true) addCapability(descriptor, 'reporting.usage', null);
        if (descriptor.hasMapping == true) addCapability(descriptor, 'mapping.fields', null);
        if (descriptor.hasScheduler == true) addCapability(descriptor, 'scheduler.operation', defaultAdapterClass(descriptor.connectorKey, 'scheduler.operation'));
        if (descriptor.hasCheckout == true) addCapability(descriptor, 'payment.checkout', defaultAdapterClass(descriptor.connectorKey, 'payment.checkout'));
        if (descriptor.hasPayment == true) addCapability(descriptor, 'payment.provider', defaultAdapterClass(descriptor.connectorKey, 'payment.provider'));
        if (descriptor.hasCarrier == true) addCapability(descriptor, 'carrier.operation', defaultAdapterClass(descriptor.connectorKey, 'carrier.operation'));
    }

    private static void addCapability(ConnectorDescriptor descriptor, String capabilityKey, String adapterClassName) {
        if (descriptor.capabilities == null) descriptor.capabilities = new List<String>();
        if (!descriptor.capabilities.contains(capabilityKey)) descriptor.capabilities.add(capabilityKey);
        if (String.isNotBlank(adapterClassName)) descriptor.adapterClassByCapability.put(capabilityKey, adapterClassName);
    }

    private static String defaultAdapterClass(String connectorKey, String capabilityKey) {
        return LegacyConnectorRegistryFallback.defaultAdapterClass(connectorKey, capabilityKey);
    }

    private static void addFallbackObjectMaps(ConnectorDescriptor descriptor) {
        descriptor.objectMappings.addAll(LegacyConnectorRegistryFallback.objectMapsFor(descriptor.connectorKey));
    }

    private static Map<String, ConnectorDescriptor> byConnectorKey(List<ConnectorDescriptor> descriptors) {
        Map<String, ConnectorDescriptor> result = new Map<String, ConnectorDescriptor>();
        for (ConnectorDescriptor descriptor : descriptors) {
            result.put(normalize(descriptor.connectorKey), descriptor);
            result.put(normalize(descriptor.productKey), descriptor);
        }
        return result;
    }

    private static void indexDescriptor(ConnectorDescriptor descriptor) {
        cachedByNormalizedKey.put(normalize(descriptor.connectorKey), descriptor);
        cachedByNormalizedKey.put(normalize(descriptor.productKey), descriptor);
        for (String aliasValue : splitList(descriptor.aliases)) {
            cachedByNormalizedKey.put(normalize(aliasValue), descriptor);
        }
    }

    private static String normalizeCapability(String capabilityKey) {
        return String.isBlank(capabilityKey) ? '' : capabilityKey.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static String defaultIconName(String category) {
        String normalized = normalize(category);
        if (normalized == 'payment') return 'utility:money';
        if (normalized == 'carrier') return 'utility:package';
        if (normalized == 'commerce') return 'utility:cart';
        if (normalized == 'accounting') return 'utility:moneybag';
        return 'utility:connected_apps';
    }

    private static Boolean isSecretField(String fieldName) {
        String normalized = normalize(fieldName);
        return normalized.contains('secret') || normalized.contains('token') || normalized.contains('password') || normalized.contains('privatekey') || normalized.contains('clientsecret');
    }

    private static List<String> splitList(String rawValue) {
        List<String> values = new List<String>();
        if (String.isBlank(rawValue)) return values;
        for (String value : rawValue.split(',')) {
            if (String.isNotBlank(value)) values.add(value.trim());
        }
        return values;
    }

    private static List<ConnectorDescriptor> cloneConnectors(List<ConnectorDescriptor> source) {
        List<ConnectorDescriptor> result = new List<ConnectorDescriptor>();
        for (ConnectorDescriptor descriptor : source) result.add(cloneConnector(descriptor));
        return result;
    }

    private static ConnectorDescriptor cloneConnector(ConnectorDescriptor source) {
        ConnectorDescriptor descriptor = baseDescriptor(source.connectorKey, source.productKey, source.label, source.aliases, source.category, source.configRecordName, source.integrationType, source.activeField, source.expiryField, String.join(source.editableFields == null ? new List<String>() : source.editableFields, ','), source.sortOrder, source.hasConfig, source.hasReporting, source.hasMapping, source.hasScheduler, source.hasCheckout, source.hasPayment, source.hasCarrier, source.countsTowardScheduleLimit);
        descriptor.iconName = String.isBlank(source.iconName) ? descriptor.iconName : source.iconName;
        descriptor.logoUrl = source.logoUrl;
        descriptor.entitlementKey = source.entitlementKey;
        descriptor.configSchemaKey = source.configSchemaKey;
        descriptor.catalogActive = source.catalogActive;
        descriptor.startDate = source.startDate;
        descriptor.endDate = source.endDate;
        descriptor.status = source.status;
        descriptor.capabilities = source.capabilities == null ? new List<String>() : new List<String>(source.capabilities);
        descriptor.adapterClassByCapability = source.adapterClassByCapability == null ? new Map<String, String>() : new Map<String, String>(source.adapterClassByCapability);
        descriptor.configFields = cloneConfigFields(source.configFields);
        descriptor.objectMappings = cloneObjectMaps(source.objectMappings);
        return descriptor;
    }

    private static List<ConfigFieldDescriptor> cloneConfigFields(List<ConfigFieldDescriptor> source) {
        List<ConfigFieldDescriptor> result = new List<ConfigFieldDescriptor>();
        for (ConfigFieldDescriptor item : source == null ? new List<ConfigFieldDescriptor>() : source) {
            ConfigFieldDescriptor cloneValue = new ConfigFieldDescriptor();
            cloneValue.connectorKey = item.connectorKey;
            cloneValue.fieldKey = item.fieldKey;
            cloneValue.label = item.label;
            cloneValue.dataType = item.dataType;
            cloneValue.required = item.required;
            cloneValue.secret = item.secret;
            cloneValue.legacyFieldApiName = item.legacyFieldApiName;
            cloneValue.sortOrder = item.sortOrder;
            result.add(cloneValue);
        }
        return result;
    }

    private static List<ObjectMapDescriptor> cloneObjectMaps(List<ObjectMapDescriptor> source) {
        List<ObjectMapDescriptor> result = new List<ObjectMapDescriptor>();
        for (ObjectMapDescriptor item : source == null ? new List<ObjectMapDescriptor>() : source) {
            ObjectMapDescriptor cloneValue = new ObjectMapDescriptor();
            cloneValue.connectorKey = item.connectorKey;
            cloneValue.salesforceObject = item.salesforceObject;
            cloneValue.externalObject = item.externalObject;
            cloneValue.direction = item.direction;
            cloneValue.operationKey = item.operationKey;
            result.add(cloneValue);
        }
        return result;
    }

}