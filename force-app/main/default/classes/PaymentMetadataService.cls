public with sharing class PaymentMetadataService {

    public class MetadataConfig {
        @AuraEnabled public String provider { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Map<String, String> fields { get; set; }
        @AuraEnabled public List<String> editableFields { get; set; }
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

    private class ProductRenewalRequestException extends Exception {}

    private static final Map<String, List<String>> PROVIDER_FIELDS = new Map<String, List<String>>{
        'authorizenet' => new List<String>{ 'Company_Name__c', 'AuthorizeNet_API_Login_ID__c', 'AuthorizeNet_Public_Client_Key__c', 'AuthorizeNet_Webhook_Signing_Key__c', 'AuthorizeNet_Active__c', 'AuthorizeNet_Use_Sandbox__c', 'AuthorizeNet_Start_Date__c', 'AuthorizeNet_End_Date__c' },
        'stripe' => new List<String>{ 'Company_Name__c', 'Stripe_Publishable_Key__c', 'Stripe_Webhook_Signing_Secret__c', 'Stripe_Active__c', 'Stripe_Use_Sandbox__c', 'Stripe_Start_Date__c', 'Stripe_End_Date__c' },
        'paypal' => new List<String>{ 'Company_Name__c', 'PayPal_ClientId__c', 'PayPal_Active__c', 'PayPal_UseSandbox__c', 'PayPal_StartDate__c', 'PayPal_EndDate__c' },
        'shopify' => new List<String>{ 'Company_Name__c', 'Shopify_Store_URL__c', 'Shopify_Access_Token__c', 'Shopify_API_Key__c', 'Shopify_API_Secret__c', 'Shopify_Is_Active__c', 'Shopify_Start_Date__c', 'Shopify_End_Date__c' },
        'qbo' => new List<String>{ 'Company_Name__c', 'QuickBooks_Realm_ID__c', 'QuickBooks_Is_Active__c', 'QuickBooks_Start_Date__c', 'QuickBooks_End_Date__c' },
        'fedex' => new List<String>{ 'FedEx_Client_Id__c', 'FedEx_Client_Secret__c', 'FedEx_Account_Number__c', 'FedEx_Environment__c', 'FedEx_Default_Service_Type__c', 'FedEx_Default_Packaging_Type__c', 'FedEx_Default_Pickup_Type__c', 'FedEx_Active__c', 'FedEx_Start_Date__c', 'FedEx_End_Date__c' },
        'ups' => new List<String>{ 'UPS_Client_Id__c', 'UPS_Client_Secret__c', 'UPS_Account_Number__c', 'UPS_Environment__c', 'UPS_Default_Service_Code__c', 'UPS_Active__c', 'UPS_Start_Date__c', 'UPS_End_Date__c' }
    };

    private static final Map<String, String> PROVIDER_LABELS = new Map<String, String>{
        'authorizenet' => 'Authorize.Net', 'stripe' => 'Stripe', 'paypal' => 'PayPal', 'shopify' => 'Shopify', 'qbo' => 'QuickBooks',
        'fedex' => 'FedEx', 'ups' => 'UPS'
    };

    private static final Map<String, String> PROVIDER_RECORD_NAMES = new Map<String, String>{
        'authorizenet' => 'AuthorizeNet', 'stripe' => 'Stripe', 'paypal' => 'PayPal', 'shopify' => 'Shopify', 'qbo' => 'QuickBooks',
        'fedex' => 'FedEx', 'ups' => 'UPS'
    };

    private static final Map<String, String> PROVIDER_EXPIRY_FIELDS = new Map<String, String>{
        'authorizenet' => 'AuthorizeNet_End_Date__c',
        'stripe' => 'Stripe_End_Date__c',
        'paypal' => 'PayPal_EndDate__c',
        'shopify' => 'Shopify_End_Date__c',
        'qbo' => 'QuickBooks_End_Date__c',
        'fedex' => 'FedEx_End_Date__c',
        'ups' => 'UPS_End_Date__c'
    };

    private static final String METADATA_TYPE_NAME = 'Quickbridge_Config__mdt';
    private static final Integer EXPIRY_WARNING_DAYS = 7;
    private static final String RENEWAL_NOTIFICATION_TYPE = 'QuickBridge_Renewal_Alert';
    private static final String RENEWAL_REQUEST_RECIPIENT = 'adnan@thelodestonegroup.com';

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
            for (String providerKey : PROVIDER_LABELS.keySet()) {
                configs.add(buildMetadataConfig(providerKey));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PaymentMetadataService.getPaymentMetadataConfigs exception: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.getPaymentMetadataConfigs', e, null, null);
        }
        return configs;
    }

    @AuraEnabled
    public static MetadataUpdateResponse updatePaymentMetadata(String provider, String fieldValuesJson) {
        MetadataUpdateResponse response = new MetadataUpdateResponse();
        try {
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

            String normalizedProvider = provider.toLowerCase().trim();
            if (!PROVIDER_RECORD_NAMES.containsKey(normalizedProvider)) {
                response.success = false;
                response.message = 'Unsupported payment provider: ' + provider;
                return response;
            }

            String recordName = PROVIDER_RECORD_NAMES.get(normalizedProvider);
            List<String> allowedFields = PROVIDER_FIELDS.get(normalizedProvider);

            if (!Test.isRunningTest()) {
                System.enqueueJob(new MetadataDeployQueueable(
                    normalizedProvider, fieldValues, allowedFields, recordName, METADATA_TYPE_NAME
                ));
            }

            response.success = true;
            response.message = 'Configuration save initiated for ' + PROVIDER_LABELS.get(normalizedProvider);
            response.deploymentId = null;
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error updating metadata: ' + e.getMessage();
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.updatePaymentMetadata', e, null, null);
        }
        return response;
    }

    @AuraEnabled
    public static ConfigPanelPreferences getConfigPanelPreferences() {
        ConfigPanelPreferences preferences = new ConfigPanelPreferences();
        preferences.availableProductsVisible = true;

        try {
            Quickbridge_Config__mdt config = Quickbridge_Config__mdt.getInstance('Default');
            if (config != null && config.Available_Products_Visible__c != null) {
                preferences.availableProductsVisible = config.Available_Products_Visible__c;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PaymentMetadataService.getConfigPanelPreferences exception: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.getConfigPanelPreferences', e, null, null);
        }

        return preferences;
    }

    @AuraEnabled
    public static MetadataUpdateResponse updateAvailableProductsVisible(Boolean visible) {
        MetadataUpdateResponse response = new MetadataUpdateResponse();
        try {
            Metadata.DeployContainer container = new Metadata.DeployContainer();
            Metadata.CustomMetadata record = new Metadata.CustomMetadata();
            record.fullName = METADATA_TYPE_NAME + '.Default';
            record.label = 'Default';

            Metadata.CustomMetadataValue metaValue = new Metadata.CustomMetadataValue();
            metaValue.field = 'Available_Products_Visible__c';
            metaValue.value = visible == true;
            record.values.add(metaValue);

            container.addMetadata(record);
            if (!Test.isRunningTest()) {
                Metadata.Operations.enqueueDeployment(container, null);
            }

            response.success = true;
            response.message = 'Available Products display preference save initiated.';
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
            alert.providerLabel = PROVIDER_LABELS.get(normalizedProvider);

            String expiryField = PROVIDER_EXPIRY_FIELDS.get(normalizedProvider);
            String recordName = PROVIDER_RECORD_NAMES.get(normalizedProvider);
            if (String.isBlank(expiryField) || String.isBlank(recordName)) {
                return alert;
            }

            String query = 'SELECT ' + expiryField + ' FROM ' + METADATA_TYPE_NAME + ' WHERE DeveloperName = :recordName LIMIT 1';
            SObject metadataRecord = Database.query(query);
            if (metadataRecord == null || metadataRecord.get(expiryField) == null) {
                return alert;
            }

            Date expiryDate = (Date) metadataRecord.get(expiryField);
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

    @AuraEnabled
    public static MetadataUpdateResponse sendProductRenewalRequest(List<String> renewalProductKeys, List<String> additionalSubscriptionProductKeys) {
        MetadataUpdateResponse response = new MetadataUpdateResponse();

        try {
            List<String> renewalProductLabels = resolveProviderLabels(renewalProductKeys);
            List<String> additionalSubscriptionProductLabels = resolveProviderLabels(additionalSubscriptionProductKeys);

            if (renewalProductLabels.isEmpty() && additionalSubscriptionProductLabels.isEmpty()) {
                response.success = false;
                response.message = 'Select at least one product before sending the request.';
                return response;
            }

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ RENEWAL_REQUEST_RECIPIENT });
            email.setSaveAsActivity(false);
            email.setSubject('QuickBridge renewal and subscription request');
            email.setPlainTextBody(buildProductRenewalRequestEmailBody(renewalProductLabels, additionalSubscriptionProductLabels));

            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email }, false);

            response.success = true;
            response.message = 'Renewal request email sent to ' + RENEWAL_REQUEST_RECIPIENT + '.';
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error sending renewal request: ' + e.getMessage();
            ErrorLogUtility.logException('QuickBridge', 'PaymentMetadataService.sendProductRenewalRequest', e, null, null);
        }

        return response;
    }

    private static MetadataConfig buildMetadataConfig(String provider) {
        MetadataConfig config = new MetadataConfig();
        config.provider = provider;
        config.label = PROVIDER_LABELS.get(provider);
        config.fields = new Map<String, String>();
        config.editableFields = PROVIDER_FIELDS.get(provider);

        try {
            SObject metadataRecord;
            String recordName = PROVIDER_RECORD_NAMES.get(provider);
            String query = 'SELECT ' + String.join(config.editableFields, ',') + ' FROM ' + METADATA_TYPE_NAME + ' WHERE DeveloperName = :recordName LIMIT 1';

            try {
                metadataRecord = Database.query(query);
            } catch(Exception e) {
            }

            if(metadataRecord != null) {
                Boolean isActive = false;

                for(String fieldName : config.editableFields) {
                    if (fieldName.contains('Active')) {
                        Object val = metadataRecord.get(fieldName);
                        if (val != null) isActive = (Boolean)val;
                    }
                }

                config.active = isActive;

                for(String fieldName : config.editableFields) {
                    Object val = metadataRecord.get(fieldName);
                    config.fields.put(fieldName, val == null ? '' : String.valueOf(val));
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

        String normalizedProvider = provider.toLowerCase().trim();
        if (!PROVIDER_RECORD_NAMES.containsKey(normalizedProvider)) {
            throw new AuraHandledException('Unsupported payment provider: ' + provider);
        }

        return normalizedProvider;
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
    private static List<String> resolveProviderLabels(List<String> providerKeys) {
        List<String> labels = new List<String>();
        if (providerKeys == null) {
            return labels;
        }

        Set<String> seenProviderKeys = new Set<String>();
        for (String providerKey : providerKeys) {
            if (String.isBlank(providerKey)) {
                continue;
            }

            String normalizedProvider = providerKey.toLowerCase().trim();
            if (!PROVIDER_LABELS.containsKey(normalizedProvider)) {
                throw new ProductRenewalRequestException('Unsupported product: ' + providerKey);
            }

            if (seenProviderKeys.add(normalizedProvider)) {
                labels.add(PROVIDER_LABELS.get(normalizedProvider));
            }
        }

        labels.sort();
        return labels;
    }

    @TestVisible
    private static String buildProductRenewalRequestEmailBody(List<String> renewalProductLabels, List<String> additionalSubscriptionProductLabels) {
        List<String> bodyLines = new List<String>{
            'QuickBridge product request submitted.',
            '',
            'Requested By: ' + UserInfo.getName() + ' <' + UserInfo.getUserEmail() + '>',
            'Submitted At: ' + String.valueOf(System.now()),
            ''
        };

        bodyLines.add('Renewal for existing subscriptions:');
        bodyLines.addAll(formatProductLines(renewalProductLabels));
        bodyLines.add('');
        bodyLines.add('Additional subscriptions requested:');
        bodyLines.addAll(formatProductLines(additionalSubscriptionProductLabels));
        bodyLines.add('');
        bodyLines.add('This request was sent from the QuickBridge product selection page.');

        return String.join(bodyLines, '\n');
    }

    @TestVisible
    private static List<String> formatProductLines(List<String> productLabels) {
        List<String> lines = new List<String>();
        if (productLabels == null || productLabels.isEmpty()) {
            lines.add('- None selected');
            return lines;
        }

        for (String productLabel : productLabels) {
            lines.add('- ' + productLabel);
        }
        return lines;
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
