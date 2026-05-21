public with sharing class FedExAuthService {
    
    public class FedExTokenResponse {
        public String access_token;
        public String token_type;
        public Integer expires_in;
    }

    public static String getAccessToken() {
        FedExCredentialConfig config = getCredentialConfig();
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
        FedExCredentialConfig config = new FedExCredentialConfig();

        String clientId = ConnectorConfigResolver.getValue('fedex', 'FedEx_Client_Id__c');
        String clientSecret = ConnectorConfigResolver.getValue('fedex', 'FedEx_Client_Secret__c');
        Boolean isActive = ConnectorConfigResolver.getBoolean('fedex', 'FedEx_Active__c');

        if (String.isNotBlank(clientId) || String.isNotBlank(clientSecret)) {
            if (isActive != true) {
                ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
                context.gatewayName = 'FedEx';
                context.classMethodName = 'FedExAuthService.getCredentialConfig';
                context.errorMessage = 'FedEx integration is not active. Enable it in Quickbridge configuration before running FedEx actions.';
                context.errorCategory = 'Configuration Error';
                ErrorLogUtility.logError(context);
                throw new AuraHandledException('FedEx integration is not active. Enable it in Quickbridge configuration before running FedEx actions.');
            }
            config.clientId = clientId;
            config.clientSecret = clientSecret;
            config.environment = String.isBlank(ConnectorConfigResolver.getValue('fedex', 'FedEx_Environment__c')) ? 'Sandbox' : ConnectorConfigResolver.getValue('fedex', 'FedEx_Environment__c');
            config.accountNumber = ConnectorConfigResolver.getValue('fedex', 'FedEx_Account_Number__c');
            config.defaultServiceType = ConnectorConfigResolver.getValue('fedex', 'FedEx_Default_Service_Type__c');
            config.defaultPackagingType = ConnectorConfigResolver.getValue('fedex', 'FedEx_Default_Packaging_Type__c');
            config.defaultPickupType = ConnectorConfigResolver.getValue('fedex', 'FedEx_Default_Pickup_Type__c');
            return config;
        }

        // Legacy FedEx_Config__mdt fallback (pre-Quickbridge config)
        FedEx_Config__mdt legacyConfig = [
            SELECT Client_Id__c, Client_Secret__c, Environment__c, MasterLabel
            FROM FedEx_Config__mdt
            LIMIT 1
        ];
        config.clientId = legacyConfig.Client_Id__c;
        config.clientSecret = legacyConfig.Client_Secret__c;
        config.environment = String.isBlank(legacyConfig.Environment__c) ? 'Sandbox' : legacyConfig.Environment__c;
        config.accountNumber = legacyConfig.MasterLabel;
        return config;
    }

    public class FedExCredentialConfig {
        public String clientId;
        public String clientSecret;
        public String environment;
        public String accountNumber;
        public String defaultServiceType;
        public String defaultPackagingType;
        public String defaultPickupType;
    }
}