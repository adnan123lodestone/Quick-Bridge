public with sharing class PaymentMetadataService {

    public class MetadataConfig {
        @AuraEnabled public String provider { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Map<String, String> fields { get; set; }
        @AuraEnabled public List<String> editableFields { get; set; }
        @AuraEnabled public Map<String, String> fieldLabels { get; set; }
    }

    public class MetadataUpdateResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String deploymentId { get; set; }
    }

    public class ConfigPanelPreferences {
        @AuraEnabled public Boolean availableProductsVisible { get; set; }
    }

    public class IntegrationExpiryAlert {
        @AuraEnabled public Boolean shouldAlert { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String variant { get; set; }
        @AuraEnabled public String provider { get; set; }
        @AuraEnabled public String providerLabel { get; set; }
        @AuraEnabled public Date expiryDate { get; set; }
        @AuraEnabled public Integer daysUntilExpiry { get; set; }
        @AuraEnabled public Boolean emailSent { get; set; }
        @AuraEnabled public Boolean notificationSent { get; set; }
    }

    private static final Integer EXPIRY_WARNING_DAYS = 7;
    private static final String RENEWAL_NOTIFICATION_TYPE = 'QuickBridge_Renewal_Alert';

    public class MetadataDeployQueueable implements Queueable {
        private String provider;
        private Map<String, Object> fieldValues;
        private List<String> allowedFields;
        private String recordName;
        private String metadataTypeName;

        public MetadataDeployQueueable(String provider, Map<String, Object> fieldValues, List<String> allowedFields, String recordName, String metadataTypeName) {
            this.provider = provider;
            this.fieldValues = fieldValues;
            this.allowedFields = allowedFields;
            this.recordName = recordName;
            this.metadataTypeName = metadataTypeName;
        }

        public void execute(QueueableContext ctx) {
            try {
                Metadata.DeployContainer container = new Metadata.DeployContainer();
                Metadata.CustomMetadata record = new Metadata.CustomMetadata();
                record.fullName = metadataTypeName + '.' + recordName;
                record.label = recordName;

                for (String fieldName : fieldValues.keySet()) {
                    if (!allowedFields.contains(fieldName)) continue;

                    Object fieldValue = fieldValues.get(fieldName);
                    Metadata.CustomMetadataValue metaValue = new Metadata.CustomMetadataValue();
                    metaValue.field = fieldName;

                    if (fieldName.contains('Date')) {
                        if (fieldValue != null && String.isNotBlank(String.valueOf(fieldValue))) {
                            metaValue.value = Date.valueOf(String.valueOf(fieldValue));
                        } else {
                            metaValue.value = null;
                        }
                    } else {
                        metaValue.value = fieldValue;
                    }
                    record.values.add(metaValue);
                }

                container.addMetadata(record);
                Metadata.Operations.enqueueDeployment(container, null);
            } catch (Exception e) {
                ErrorLogUtility.logException(
                    provider,
                    'PaymentMetadataService.MetadataDeployQueueable.execute',
                    e,
                    null,
                    null
                );
                throw e;
            }
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<MetadataConfig> getPaymentMetadataConfigs() {
        List<MetadataConfig> configs = new List<MetadataConfig>();
        try {
            for (ConnectorRegistryService.ConnectorDescriptor descriptor : configurableDescriptors()) {
                configs.add(buildMetadataConfig(descriptor.connectorKey));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PaymentMetadataService.getPaymentMetadataConfigs exception: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.getPaymentMetadataConfigs', e, null, null);
        }
        return configs;
    }

    @AuraEnabled(cacheable=false)
    public static List<MetadataConfig> getConnectorConfigs() {
        List<MetadataConfig> configs = new List<MetadataConfig>();
        try {
            for (ConnectorRegistryService.ConnectorDescriptor descriptor : ConnectorRegistryService.connectors()) {
                if (descriptor.hasConfig != true) continue;
                MetadataConfig config = new MetadataConfig();
                config.provider = descriptor.connectorKey;
                config.label = descriptor.label;
                config.fields = new Map<String, String>();
                config.editableFields = descriptor.editableFields != null ? descriptor.editableFields : new List<String>();
                config.fieldLabels = new Map<String, String>();
                if (descriptor.configFields != null) {
                    for (ConnectorRegistryService.ConfigFieldDescriptor cf : descriptor.configFields) {
                        if (String.isNotBlank(cf.legacyFieldApiName) && String.isNotBlank(cf.label)) {
                            config.fieldLabels.put(cf.legacyFieldApiName, cf.label);
                        }
                        if (String.isNotBlank(cf.fieldKey) && String.isNotBlank(cf.label)) {
                            config.fieldLabels.put(cf.fieldKey, cf.label);
                        }
                    }
                }

                ConnectorConfigService.ConnectorConfig cfg = ConnectorConfigService.getConfig(descriptor.connectorKey);
                config.active = cfg.active == true;

                // Populate expiry and start date under descriptor field names for the config panel.
                if (cfg.expiryDate != null && String.isNotBlank(descriptor.expiryField)) {
                    config.fields.put(descriptor.expiryField, String.valueOf(cfg.expiryDate));
                }
                String startFieldKey = deriveStartFieldKey(descriptor.expiryField);
                if (cfg.values != null && String.isNotBlank(startFieldKey)) {
                    String startVal = cfg.values.containsKey(startFieldKey)
                        ? cfg.values.get(startFieldKey)
                        : cfg.values.get(startFieldKey.replace('start_date', 'Start_Date__c'));
                    if (String.isNotBlank(startVal)) {
                        config.fields.put(startFieldKey, startVal);
                    }
                }

                // Build normalized-key → legacy-API-name lookup from registry descriptor
                Map<String, String> normalizedToLegacy = new Map<String, String>();
                if (descriptor.configFields != null) {
                    for (ConnectorRegistryService.ConfigFieldDescriptor cf : descriptor.configFields) {
                        if (String.isNotBlank(cf.fieldKey) && String.isNotBlank(cf.legacyFieldApiName)) {
                            normalizedToLegacy.put(cf.fieldKey, cf.legacyFieldApiName);
                        }
                    }
                }

                // Populate all non-secret config values under both normalized and legacy field names.
                // Registry-listed fields are included even if their name looks like a secret —
                // the admin explicitly sanctioned them by adding them to editableFields.
                if (cfg.values != null) {
                    for (String fieldKey : cfg.values.keySet()) {
                        Boolean registrySanctioned = ConnectorConfigService.isFieldInRegistryPublic(descriptor, fieldKey);
                        if (!isSecretConfigField(fieldKey) || registrySanctioned) {
                            String val = cfg.values.get(fieldKey);
                            config.fields.put(fieldKey, val);
                            String legacyName = normalizedToLegacy.get(fieldKey);
                            if (String.isNotBlank(legacyName)) {
                                config.fields.put(legacyName, val);
                            }
                        }
                    }
                }

                // Also populate active field so the config panel form shows the correct state
                if (String.isNotBlank(descriptor.activeField)) {
                    config.fields.put(descriptor.activeField, String.valueOf(config.active));
                }

                configs.add(config);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PaymentMetadataService.getConnectorConfigs exception: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.getConnectorConfigs', e, null, null);
        }
        return configs;
    }

    @AuraEnabled
    public static MetadataUpdateResponse saveConnectorConfig(String connectorKey, String fieldValuesJson, String sessionToken) {
        MetadataUpdateResponse response = new MetadataUpdateResponse();
        try {
            QuickBridgeAdminSessionService.requireValidSession(sessionToken);

            if (String.isBlank(connectorKey) || String.isBlank(fieldValuesJson)) {
                response.success = false;
                response.message = 'Invalid request parameters';
                return response;
            }

            String normalizedKey = connectorKey.toLowerCase().trim();
            ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(normalizedKey);
            if (descriptor == null) {
                response.success = false;
                response.message = 'Unsupported connector: ' + connectorKey;
                return response;
            }

            Map<String, Object> fieldValues = (Map<String, Object>) JSON.deserializeUntyped(fieldValuesJson);
            for (String fieldKey : fieldValues.keySet()) {
                // Skip active field — it is derived from expiry date, not set directly
                if (fieldKey.containsIgnoreCase('Active')) continue;
                Object val = fieldValues.get(fieldKey);
                String strVal = val == null ? null : String.valueOf(val);
                ConnectorConfigService.upsertNonSecretValue(normalizedKey, fieldKey, strVal);
            }

            response.success = true;
            response.message = 'Configuration saved for ' + (descriptor.label != null ? descriptor.label : connectorKey);
        } catch (AuraHandledException ahe) {
            response.success = false;
            // AuraHandledException.getMessage() returns "Script thrown exception" when thrown
            // from a sub-method (Salesforce platform limitation). Fall back to a useful message.
            String aheMsg = ahe.getMessage();
            response.message = (String.isBlank(aheMsg) || aheMsg == 'Script thrown exception')
                ? 'Configuration could not be saved. A field value was rejected.'
                : aheMsg;
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error saving configuration: ' + e.getMessage();
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.saveConnectorConfig', e, null, null);
        }
        return response;
    }

    @AuraEnabled
    public static MetadataUpdateResponse validateConnectorConnection(String connectorKey, String sessionToken) {
        MetadataUpdateResponse response = new MetadataUpdateResponse();
        try {
            QuickBridgeAdminSessionService.requireValidSession(sessionToken);
            QuickBridgeAdminGuard.requireManage();
            ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(connectorKey);
            if (descriptor == null) {
                response.success = false;
                response.message = 'Unsupported connector: ' + connectorKey;
                return response;
            }
            if (descriptor.connectorKey == NetSuiteConfigService.CONNECTOR_KEY) {
                NetSuiteConnectionValidator.ValidationResult validation = NetSuiteConnectionValidator.validateConnection();
                response.success = validation.success;
                response.message = validation.message;
                return response;
            }
            response.success = false;
            response.message = 'Connection validation is not registered for ' + descriptor.label + '.';
        } catch (AuraHandledException ahe) {
            response.success = false;
            String aheMsg = ahe.getMessage();
            response.message = (String.isBlank(aheMsg) || aheMsg == 'Script thrown exception')
                ? 'Connection validation could not be completed.'
                : aheMsg;
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error validating connector: ' + e.getMessage();
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.validateConnectorConnection', e, null, null);
        }
        return response;
    }

    private static String deriveStartFieldKey(String expiryFieldKey) {
        if (String.isBlank(expiryFieldKey)) return null;
        if (expiryFieldKey.containsIgnoreCase('End_Date__c')) return expiryFieldKey.replaceAll('(?i)End_Date__c', 'Start_Date__c');
        if (expiryFieldKey.containsIgnoreCase('EndDate__c')) return expiryFieldKey.replaceAll('(?i)EndDate__c', 'StartDate__c');
        if (expiryFieldKey.containsIgnoreCase('end_date')) return expiryFieldKey.replaceAll('(?i)end_date', 'start_date');
        return null;
    }

    private static Boolean isSecretConfigField(String fieldName) {
        String normalized = ConnectorRegistryService.normalize(fieldName);
        return normalized.contains('secret') || normalized.contains('token') ||
               normalized.contains('password') || normalized.contains('privatekey') ||
               normalized.contains('clientsecret');
    }

    @AuraEnabled
    public static MetadataUpdateResponse updatePaymentMetadata(String provider, String fieldValuesJson, String sessionToken) {
        MetadataUpdateResponse response = new MetadataUpdateResponse();
        try {
            QuickBridgeAdminSessionService.requireValidSession(sessionToken);

            if (String.isBlank(provider) || String.isBlank(fieldValuesJson)) {
                response.success = false;
                response.message = 'Invalid request parameters';
                return response;
            }

            Map<String, Object> fieldValues = (Map<String, Object>) JSON.deserializeUntyped(fieldValuesJson);

            // Prevent Date fields from deployed
            for(String key : new List<String>(fieldValues.keySet())) {
                if(key.containsIgnoreCase('Date')) {
                    fieldValues.remove(key);
                }
            }

            String normalizedProvider = normalizeProvider(provider);
            for (String fieldKey : fieldValues.keySet()) {
                Object val = fieldValues.get(fieldKey);
                ConnectorConfigService.upsertNonSecretValue(
                    normalizedProvider,
                    fieldKey,
                    val == null ? null : String.valueOf(val)
                );
            }

            response.success = true;
            response.message = 'Configuration saved for ' + providerLabel(normalizedProvider);
            response.deploymentId = null;
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error updating metadata: ' + e.getMessage();
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.updatePaymentMetadata', e, null, null);
        }
        return response;
    }

    private static final String QB_PANEL_CONNECTOR_KEY = 'quickbridge';
    private static final String AVAILABLE_PRODUCTS_VISIBLE_FIELD = 'available_products_visible';

    @AuraEnabled
    public static ConfigPanelPreferences getConfigPanelPreferences() {
        ConfigPanelPreferences preferences = new ConfigPanelPreferences();
        preferences.availableProductsVisible = true;

        try {
            List<Connector_Config_Value__c> rows = [
                SELECT Value__c
                FROM Connector_Config_Value__c
                WHERE Connector_Key__c = :QB_PANEL_CONNECTOR_KEY
                  AND Field_Key__c = :AVAILABLE_PRODUCTS_VISIBLE_FIELD
                LIMIT 1
            ];
            if (!rows.isEmpty() && String.isNotBlank(rows[0].Value__c)) {
                preferences.availableProductsVisible = rows[0].Value__c == 'true';
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PaymentMetadataService.getConfigPanelPreferences exception: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.getConfigPanelPreferences', e, null, null);
        }

        return preferences;
    }

    @AuraEnabled
    public static MetadataUpdateResponse updateAvailableProductsVisible(Boolean visible, String sessionToken) {
        MetadataUpdateResponse response = new MetadataUpdateResponse();
        try {
            QuickBridgeAdminSessionService.requireValidSession(sessionToken);

            String visibleStr = visible == true ? 'true' : 'false';
            List<Connector_Config_Value__c> existing = [
                SELECT Id
                FROM Connector_Config_Value__c
                WHERE Connector_Key__c = :QB_PANEL_CONNECTOR_KEY
                  AND Field_Key__c = :AVAILABLE_PRODUCTS_VISIBLE_FIELD
                LIMIT 1
            ];
            Connector_Config_Value__c row = existing.isEmpty() ? new Connector_Config_Value__c() : existing[0];
            row.Name = QB_PANEL_CONNECTOR_KEY + ':' + AVAILABLE_PRODUCTS_VISIBLE_FIELD;
            row.Connector_Key__c = QB_PANEL_CONNECTOR_KEY;
            row.Field_Key__c = AVAILABLE_PRODUCTS_VISIBLE_FIELD;
            row.Value__c = visibleStr;
            row.Is_Secret_Reference__c = false;
            upsert row;

            response.success = true;
            response.message = 'Available Products display preference saved.';
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error updating Available Products preference: ' + e.getMessage();
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.updateAvailableProductsVisible', e, null, null);
        }
        return response;
    }

    @AuraEnabled
    public static IntegrationExpiryAlert checkIntegrationExpiry(String provider) {
        IntegrationExpiryAlert alert = new IntegrationExpiryAlert();
        alert.shouldAlert = false;
        alert.emailSent = false;
        alert.notificationSent = false;

        try {
            String normalizedProvider = normalizeProvider(provider);
            alert.provider = normalizedProvider;
            alert.providerLabel = providerLabel(normalizedProvider);

            ConnectorConfigService.ConnectorConfig cfg = ConnectorConfigService.getConfig(normalizedProvider);
            Date expiryDate = cfg.expiryDate;
            if (expiryDate == null) {
                return alert;
            }
            Integer daysUntilExpiry = Date.today().daysBetween(expiryDate);
            if (daysUntilExpiry > EXPIRY_WARNING_DAYS) {
                return alert;
            }

            alert.shouldAlert = true;
            alert.expiryDate = expiryDate;
            alert.daysUntilExpiry = daysUntilExpiry;
            alert.variant = daysUntilExpiry < 0 ? 'error' : 'warning';
            alert.title = daysUntilExpiry < 0 ? 'Integration Expired' : 'Integration Expiring Soon';
            alert.message = buildExpiryMessage(alert.providerLabel, expiryDate, daysUntilExpiry);

            sendRenewalEmailToSystemAdmins(alert);
            sendRenewalNotification(alert);
        } catch (Exception e) {
            alert.shouldAlert = false;
            alert.title = 'Expiry Check Failed';
            alert.message = e.getMessage();
            alert.variant = 'error';
            System.debug(LoggingLevel.ERROR, 'PaymentMetadataService.checkIntegrationExpiry exception: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.checkIntegrationExpiry', e, null, null);
        }

        return alert;
    }

    private static final String RENEWAL_REQUEST_RECIPIENT = 'adnan@thelodestonegroup.com';

    @AuraEnabled
    public static MetadataUpdateResponse sendProductRenewalRequest(
        List<String> renewalProductKeys,
        List<String> additionalSubscriptionProductKeys,
        String sessionToken
    ) {
        MetadataUpdateResponse response = new MetadataUpdateResponse();
        try {
            QuickBridgeAdminSessionService.requireValidSession(sessionToken);

            List<String> safeRenewal = renewalProductKeys != null ? renewalProductKeys : new List<String>();
            List<String> safeAdditional = additionalSubscriptionProductKeys != null ? additionalSubscriptionProductKeys : new List<String>();

            if (safeRenewal.isEmpty() && safeAdditional.isEmpty()) {
                response.success = false;
                response.message = 'Select at least one product to include in the renewal request.';
                return response;
            }

            // Validate all product keys
            List<String> allKeys = new List<String>(safeRenewal);
            allKeys.addAll(safeAdditional);
            for (String key : allKeys) {
                if (String.isBlank(key)) continue;
                String normalized = key.toLowerCase().trim();
                if (ConnectorRegistryService.byKey(normalized) == null) {
                    response.success = false;
                    response.message = 'Unsupported product key: ' + key;
                    return response;
                }
            }

            List<String> renewalLabels = resolveProviderLabels(safeRenewal);
            List<String> additionalLabels = resolveProviderLabels(safeAdditional);
            String emailBody = buildProductRenewalRequestEmailBody(renewalLabels, additionalLabels);

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ RENEWAL_REQUEST_RECIPIENT });
            email.setSubject('QuickBridge Renewal Request');
            email.setPlainTextBody(emailBody);
            if (!Test.isRunningTest()) {
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);
            }

            response.success = true;
            response.message = 'Renewal request sent to ' + RENEWAL_REQUEST_RECIPIENT;
        } catch (AuraHandledException ahe) {
            response.success = false;
            response.message = ahe.getMessage();
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error sending renewal request: ' + e.getMessage();
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.sendProductRenewalRequest', e, null, null);
        }
        return response;
    }

    @TestVisible
    private static List<String> resolveProviderLabels(List<String> productKeys) {
        List<String> labels = new List<String>();
        Set<String> seenKeys = new Set<String>();
        if (productKeys == null) return labels;
        for (String key : productKeys) {
            if (String.isBlank(key)) continue;
            String normalized = key.toLowerCase().trim();
            if (seenKeys.contains(normalized)) continue;
            seenKeys.add(normalized);
            String label = providerLabel(normalized);
            if (String.isNotBlank(label)) labels.add(label);
        }
        return labels;
    }

    @TestVisible
    private static String buildProductRenewalRequestEmailBody(List<String> renewalLabels, List<String> additionalLabels) {
        List<String> lines = new List<String>();
        lines.add('Renewal for existing subscriptions:');
        lines.addAll(formatProductLines(renewalLabels));
        lines.add('');
        lines.add('Additional subscriptions requested:');
        lines.addAll(formatProductLines(additionalLabels));
        return String.join(lines, '\n');
    }

    @TestVisible
    private static List<String> formatProductLines(List<String> labels) {
        if (labels == null || labels.isEmpty()) return new List<String>{ '- None selected' };
        List<String> lines = new List<String>();
        for (String label : labels) lines.add('- ' + label);
        return lines;
    }

    private static MetadataConfig buildMetadataConfig(String provider) {
        MetadataConfig config = new MetadataConfig();
        config.provider = provider;
        config.label = providerLabel(provider);
        config.fields = new Map<String, String>();
        ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(provider);
        config.editableFields = descriptor == null ? new List<String>() : descriptor.editableFields;

        try {
            ConnectorConfigService.ConnectorConfig cfg = ConnectorConfigService.getConfig(provider);
            config.active = cfg.active == true;
            if (cfg.values != null) {
                for (String fieldName : config.editableFields == null ? new List<String>() : config.editableFields) {
                    String value = cfg.values.get(fieldName);
                    if (value == null) {
                        for (ConnectorRegistryService.ConfigFieldDescriptor field : ConnectorRegistryService.configFieldsFor(provider)) {
                            if (field.legacyFieldApiName == fieldName && cfg.values.containsKey(field.fieldKey)) {
                                value = cfg.values.get(field.fieldKey);
                                break;
                            }
                        }
                    }
                    config.fields.put(fieldName, value == null ? '' : value);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error building config: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.buildMetadataConfig', e, null, null);
        }

        return config;
    }

    private static String normalizeProvider(String provider) {
        if (String.isBlank(provider)) {
            throw new AuraHandledException('Provider is required.');
        }

        ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(provider);
        if (descriptor == null) {
            throw new AuraHandledException('Unsupported payment provider: ' + provider);
        }

        return descriptor.connectorKey;
    }

    private static List<ConnectorRegistryService.ConnectorDescriptor> configurableDescriptors() {
        List<ConnectorRegistryService.ConnectorDescriptor> descriptors = new List<ConnectorRegistryService.ConnectorDescriptor>();
        for (ConnectorRegistryService.ConnectorDescriptor descriptor : ConnectorRegistryService.connectors()) {
            if (descriptor.hasConfig == true) {
                descriptors.add(descriptor);
            }
        }
        return descriptors;
    }

    private static String providerLabel(String provider) {
        ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(provider);
        return descriptor == null || String.isBlank(descriptor.label) ? provider : descriptor.label;
    }

    @TestVisible
    private static String buildExpiryMessage(String providerLabel, Date expiryDate, Integer daysUntilExpiry) {
        String expiryText = String.valueOf(expiryDate);
        if (daysUntilExpiry < 0) {
            return providerLabel + ' expired on ' + expiryText + '. Please renew the subscription.';
        }
        if (daysUntilExpiry == 0) {
            return providerLabel + ' expires today (' + expiryText + '). Please renew the subscription.';
        }
        return providerLabel + ' expires in ' + daysUntilExpiry + ' day' + (daysUntilExpiry == 1 ? '' : 's') +
            ' (' + expiryText + '). Please renew the subscription.';
    }

    @TestVisible
    private static List<User> getActiveSystemAdmins() {
        return [
            SELECT Id, Email
            FROM User
            WHERE IsActive = true
            AND Email != null
            AND Profile.Name = 'System Administrator'
            LIMIT 100
        ];
    }

    @TestVisible
    private static void sendRenewalEmailToSystemAdmins(IntegrationExpiryAlert alert) {
        try {
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (User adminUser : getActiveSystemAdmins()) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ adminUser.Email });
                email.setSubject(alert.title + ': ' + alert.providerLabel);
                email.setPlainTextBody(
                    alert.message + '\n\n' +
                    'Provider: ' + alert.providerLabel + '\n' +
                    'Expiry Date: ' + String.valueOf(alert.expiryDate) + '\n' +
                    'Days Until Expiry: ' + String.valueOf(alert.daysUntilExpiry) + '\n\n' +
                    'This alert was generated from the QuickBridge integrations page.'
                );
                emails.add(email);
            }

            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails, false);
                alert.emailSent = true;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PaymentMetadataService.sendRenewalEmailToSystemAdmins exception: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.sendRenewalEmailToSystemAdmins', e, null, null);
        }
    }

    @TestVisible
    private static void sendRenewalNotification(IntegrationExpiryAlert alert) {
        try {
            List<CustomNotificationType> notificationTypes = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = :RENEWAL_NOTIFICATION_TYPE
                LIMIT 1
            ];
            if (notificationTypes.isEmpty()) {
                return;
            }

            Set<String> recipientIds = new Set<String>{ UserInfo.getUserId() };
            for (User adminUser : getActiveSystemAdmins()) {
                recipientIds.add(String.valueOf(adminUser.Id));
            }

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(alert.title + ': ' + alert.providerLabel);
            notification.setBody(alert.message);
            notification.setNotificationTypeId(notificationTypes[0].Id);
            notification.setTargetId(UserInfo.getUserId());
            notification.send(recipientIds);
            alert.notificationSent = true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PaymentMetadataService.sendRenewalNotification exception: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.sendRenewalNotification', e, null, null);
        }
    }
}
