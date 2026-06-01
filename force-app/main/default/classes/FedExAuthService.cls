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

        Quickbridge_Config__mdt quickbridgeConfig = Quickbridge_Config__mdt.getInstance('FedEx');
        if (quickbridgeConfig != null && (
            String.isNotBlank(quickbridgeConfig.FedEx_Client_Id__c) ||
            String.isNotBlank(quickbridgeConfig.FedEx_Client_Secret__c) ||
            String.isNotBlank(quickbridgeConfig.FedEx_Account_Number__c)
        )) {
            if (quickbridgeConfig.FedEx_Active__c != true) {
                ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
                context.gatewayName = 'FedEx';
                context.classMethodName = 'FedExAuthService.getCredentialConfig';
                context.errorMessage = 'FedEx integration is not active. Enable it in Quickbridge configuration before running FedEx actions.';
                context.errorCategory = 'Configuration Error';
                ErrorLogUtility.logError(context);
                throw new AuraHandledException('FedEx integration is not active. Enable it in Quickbridge configuration before running FedEx actions.');
            }
            config.clientId = quickbridgeConfig.FedEx_Client_Id__c;
            config.clientSecret = quickbridgeConfig.FedEx_Client_Secret__c;
            config.environment = String.isBlank(quickbridgeConfig.FedEx_Environment__c) ? 'Sandbox' : quickbridgeConfig.FedEx_Environment__c;
            config.accountNumber = quickbridgeConfig.FedEx_Account_Number__c;
            config.defaultServiceType = quickbridgeConfig.FedEx_Default_Service_Type__c;
            config.defaultPackagingType = quickbridgeConfig.FedEx_Default_Packaging_Type__c;
            config.defaultPickupType = quickbridgeConfig.FedEx_Default_Pickup_Type__c;
            return config;
        }

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