public with sharing class FedExAuthService {
    
    public class FedExTokenResponse {
        public String access_token;
        public String token_type;
        public Integer expires_in;
    }

    public static String getAccessToken() {
        FedExCredentialConfig config = getCredentialConfig();
        validateConfig(config);
        String baseUrl = getBaseUrl(config.environment);

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + '/oauth/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        String body = 'grant_type=client_credentials'
                    + '&client_id=' + EncodingUtil.urlEncode(config.clientId, 'UTF-8')
                    + '&client_secret=' + EncodingUtil.urlEncode(config.clientSecret, 'UTF-8');
        req.setBody(body);

        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception e) {
            ErrorLogUtility.logException('FedEx', 'FedExAuthService.getAccessToken', e, null, null);
            throw e;
        }

        if (res.getStatusCode() == 200) {
            FedExTokenResponse tokenResp = 
                (FedExTokenResponse) JSON.deserialize(res.getBody(), FedExTokenResponse.class);
            return tokenResp.access_token;
        } else {
            ErrorLogUtility.logCalloutFailure(
                'FedEx',
                'FedExAuthService.getAccessToken',
                'FedEx Auth Failed: ' + res.getStatus() + ' - ' + res.getBody(),
                res.getStatusCode(),
                null,
                null
            );
            throw new CalloutException('FedEx Auth Failed: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    public static String getBaseUrl() {
        return getBaseUrl(getCredentialConfig().environment);
    }

    public static String getBaseUrl(String environment) {
        return environment == 'Sandbox'
            ? 'https://apis-sandbox.fedex.com'
            : 'https://apis.fedex.com';
    }

    public static FedExCredentialConfig getCredentialConfig() {
        FedExCredentialConfig normalizedConfig = getNormalizedCredentialConfig();
        if (normalizedConfig != null) {
            return normalizedConfig;
        }

        Quickbridge_Config__mdt quickbridgeConfig = Quickbridge_Config__mdt.getInstance('FedEx');
        if (quickbridgeConfig != null && (
            String.isNotBlank(quickbridgeConfig.FedEx_Client_Id__c) ||
            String.isNotBlank(quickbridgeConfig.FedEx_Client_Secret__c) ||
            String.isNotBlank(quickbridgeConfig.FedEx_Account_Number__c)
        )) {
            FedExCredentialConfig config = new FedExCredentialConfig();
            config.clientId = quickbridgeConfig.FedEx_Client_Id__c;
            config.clientSecret = quickbridgeConfig.FedEx_Client_Secret__c;
            config.environment = String.isBlank(quickbridgeConfig.FedEx_Environment__c) ? 'Sandbox' : quickbridgeConfig.FedEx_Environment__c;
            config.accountNumber = quickbridgeConfig.FedEx_Account_Number__c;
            config.defaultServiceType = quickbridgeConfig.FedEx_Default_Service_Type__c;
            config.defaultPackagingType = quickbridgeConfig.FedEx_Default_Packaging_Type__c;
            config.defaultPickupType = quickbridgeConfig.FedEx_Default_Pickup_Type__c;
            config.isActive = quickbridgeConfig.FedEx_Active__c == true;
            return config;
        }

        List<FedEx_Config__mdt> legacyConfigs = [
            SELECT Client_Id__c, Client_Secret__c, Environment__c, MasterLabel
            FROM FedEx_Config__mdt
            LIMIT 1
        ];
        FedExCredentialConfig config = new FedExCredentialConfig();
        if (legacyConfigs.isEmpty()) {
            config.environment = 'Sandbox';
            config.isActive = false;
            return config;
        }
        FedEx_Config__mdt legacyConfig = legacyConfigs[0];
        config.clientId = legacyConfig.Client_Id__c;
        config.clientSecret = legacyConfig.Client_Secret__c;
        config.environment = String.isBlank(legacyConfig.Environment__c) ? 'Sandbox' : legacyConfig.Environment__c;
        config.accountNumber = legacyConfig.MasterLabel;
        config.isActive = true;
        return config;
    }

    private static FedExCredentialConfig getNormalizedCredentialConfig() {
        ConnectorConfigService.ConnectorConfig connectorConfig;
        try {
            connectorConfig = ConnectorConfigService.getConfig('fedex');
        } catch (Exception ignored) {
            return null;
        }
        if (connectorConfig == null || connectorConfig.fromNormalizedConfig != true) {
            return null;
        }

        FedExCredentialConfig config = new FedExCredentialConfig();
        config.clientId = firstNonBlank(
            ConnectorConfigResolver.getValue('fedex', 'FedEx_Client_Id__c'),
            ConnectorConfigResolver.getValue('fedex', 'clientId')
        );
        config.clientSecret = firstNonBlank(
            ConnectorConfigResolver.getValue('fedex', 'FedEx_Client_Secret__c'),
            ConnectorConfigResolver.getValue('fedex', 'clientSecretRef')
        );
        config.environment = firstNonBlank(
            ConnectorConfigResolver.getValue('fedex', 'FedEx_Environment__c'),
            connectorConfig.environment
        );
        config.accountNumber = ConnectorConfigResolver.getValue(
            'fedex',
            'FedEx_Account_Number__c'
        );
        config.defaultServiceType = ConnectorConfigResolver.getValue(
            'fedex',
            'FedEx_Default_Service_Type__c'
        );
        config.defaultPackagingType = ConnectorConfigResolver.getValue(
            'fedex',
            'FedEx_Default_Packaging_Type__c'
        );
        config.defaultPickupType = ConnectorConfigResolver.getValue(
            'fedex',
            'FedEx_Default_Pickup_Type__c'
        );
        config.isActive = ConnectorConfigService.isActive('fedex');
        if (String.isBlank(config.environment)) {
            config.environment = 'Sandbox';
        }

        return hasRuntimeConfigValue(config) ? config : null;
    }

    private static Boolean hasRuntimeConfigValue(FedExCredentialConfig config) {
        return config != null && (
            String.isNotBlank(config.clientId) ||
            String.isNotBlank(config.clientSecret) ||
            String.isNotBlank(config.accountNumber) ||
            String.isNotBlank(config.defaultServiceType) ||
            String.isNotBlank(config.defaultPackagingType) ||
            String.isNotBlank(config.defaultPickupType)
        );
    }

    private static void validateConfig(FedExCredentialConfig config) {
        if (config == null || config.isActive != true) {
            logConfigFailure('FedEx configuration is inactive.');
            throw new CalloutException('FedEx configuration is inactive.');
        }
        if (String.isBlank(config.clientId)) {
            logConfigFailure('FedEx Client ID is missing.');
            throw new CalloutException('FedEx Client ID is missing.');
        }
        if (String.isBlank(config.clientSecret)) {
            logConfigFailure('FedEx Client Secret is missing.');
            throw new CalloutException('FedEx Client Secret is missing.');
        }
        if (String.isBlank(config.accountNumber)) {
            logConfigFailure('FedEx Account Number is missing.');
            throw new CalloutException('FedEx Account Number is missing.');
        }
    }

    private static void logConfigFailure(String message) {
        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = 'FedEx';
        context.classMethodName = 'FedExAuthService.validateConfig';
        context.errorMessage = message;
        context.errorCategory = 'Configuration Error';
        ErrorLogUtility.logError(context);
    }

    private static String firstNonBlank(String primary, String fallback) {
        return String.isBlank(primary) ? fallback : primary;
    }

    public class FedExCredentialConfig {
        public String clientId;
        public String clientSecret;
        public String environment;
        public String accountNumber;
        public String defaultServiceType;
        public String defaultPackagingType;
        public String defaultPickupType;
        public Boolean isActive;
    }
}