public with sharing class UPSAuthService {

    public class UPSTokenResponse {
        public String access_token;
        public String token_type;
        public String expires_in;
    }

    public class UPSCredentialConfig {
        public String clientId;
        public String clientSecret;
        public String environment;
        public String accountNumber;
        public String defaultServiceCode;
        public Boolean isActive;
    }

    public static String getAccessToken() {
        UPSCredentialConfig config = getCredentialConfig();
        validateConfig(config);
        String baseUrl = getBaseUrl(config.environment);

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + '/security/v1/oauth/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        String credentials = EncodingUtil.base64Encode(
            Blob.valueOf(config.clientId + ':' + config.clientSecret)
        );
        req.setHeader('Authorization', 'Basic ' + credentials);
        req.setBody('grant_type=client_credentials');

        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception e) {
            ErrorLogUtility.logException('UPS', 'UPSAuthService.getAccessToken', e, null, null);
            throw e;
        }
        if (res.getStatusCode() == 200) {
            UPSTokenResponse tokenResp = (UPSTokenResponse) JSON.deserialize(res.getBody(), UPSTokenResponse.class);
            return tokenResp.access_token;
        } else {
            ErrorLogUtility.logCalloutFailure(
                'UPS',
                'UPSAuthService.getAccessToken',
                'UPS Auth Failed: ' + res.getStatus() + ' - ' + res.getBody(),
                res.getStatusCode(),
                null,
                null
            );
            throw new CalloutException('UPS Auth Failed: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    public static String getBaseUrl() {
        return getBaseUrl(getCredentialConfig().environment);
    }

    public static String getBaseUrl(String environment) {
        return environment == 'Production'
            ? 'https://onlinetools.ups.com'
            : 'https://wwwcie.ups.com';
    }

    public static String getApiBaseUrl() {
        return getBaseUrl() + '/api';
    }

    public static UPSCredentialConfig getCredentialConfig() {
        UPSCredentialConfig config = new UPSCredentialConfig();

        Quickbridge_Config__mdt qbConfig = Quickbridge_Config__mdt.getInstance('UPS');
        if (qbConfig != null && (
            String.isNotBlank(qbConfig.UPS_Client_Id__c) ||
            String.isNotBlank(qbConfig.UPS_Client_Secret__c)
        )) {
            config.clientId = qbConfig.UPS_Client_Id__c;
            config.clientSecret = qbConfig.UPS_Client_Secret__c;
            config.environment = String.isBlank(qbConfig.UPS_Environment__c) ? 'Sandbox' : qbConfig.UPS_Environment__c;
            config.accountNumber = qbConfig.UPS_Account_Number__c;
            config.defaultServiceCode = String.isBlank(qbConfig.UPS_Default_Service_Code__c) ? '03' : qbConfig.UPS_Default_Service_Code__c;
            config.isActive = qbConfig.UPS_Active__c == true;
            return config;
        }

        config.clientId = '';
        config.clientSecret = '';
        config.environment = 'Sandbox';
        config.accountNumber = '';
        config.defaultServiceCode = '03';
        config.isActive = false;
        return config;
    }

    private static void validateConfig(UPSCredentialConfig config) {
        if (config == null || config.isActive != true) {
            logConfigFailure('UPS configuration is inactive.');
            throw new CalloutException('UPS configuration is inactive.');
        }
        if (String.isBlank(config.clientId)) {
            logConfigFailure('UPS Client ID is missing.');
            throw new CalloutException('UPS Client ID is missing.');
        }
        if (String.isBlank(config.clientSecret)) {
            logConfigFailure('UPS Client Secret is missing.');
            throw new CalloutException('UPS Client Secret is missing.');
        }
        if (String.isBlank(config.accountNumber)) {
            logConfigFailure('UPS Account Number is missing.');
            throw new CalloutException('UPS Account Number is missing.');
        }
    }

    private static void logConfigFailure(String message) {
        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = 'UPS';
        context.classMethodName = 'UPSAuthService.validateConfig';
        context.errorMessage = message;
        context.errorCategory = 'Configuration Error';
        ErrorLogUtility.logError(context);
    }

    public static String generateTransId() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 32);
    }
}