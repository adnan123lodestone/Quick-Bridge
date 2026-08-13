public without sharing class QuickBooksAuthHandler {
    private static final String QB_API_PATH = '/v3/company/';

    private class ConfigurationException extends Exception {}

    private class QuickBooksConnectionConfig {
        String realmId;
        String namedCredential;
        String minorVersion;
    }

    @TestVisible private static String testRealmId;
    @TestVisible private static String testNamedCredential;
    @TestVisible private static String testMinorVersion;

    @TestVisible
    static void configureConnectionForTest(String realmId, String namedCredential, String minorVersion) {
        testRealmId = realmId;
        testNamedCredential = namedCredential;
        testMinorVersion = minorVersion;
    }
    
    private static QuickBooksConnectionConfig getConnectionConfig() {
        QuickBooksConnectionConfig result = new QuickBooksConnectionConfig();

        if (Test.isRunningTest()) {
            if (testRealmId != null || testNamedCredential != null || testMinorVersion != null) {
                result.realmId = String.isNotBlank(testRealmId) ? testRealmId.trim() : '123456789';
                result.namedCredential = String.isNotBlank(testNamedCredential) ? testNamedCredential.trim() : 'QuickBooksNC';
                result.minorVersion = String.isNotBlank(testMinorVersion) ? testMinorVersion.trim() : '65';
                return result;
            }
        }

        ConnectorConfigService.ConnectorConfig cfg;
        try {
            cfg = ConnectorConfigService.getAuthoritativeConfig('qbo');
        } catch (Exception e) {
            cfg = null;
        }
        if (cfg == null || cfg.fromNormalizedConfig != true) {
            throw new ConfigurationException('QuickBooks configuration record was not found.');
        }

        result.realmId = ConnectorConfigResolver.getValue('qbo', 'QuickBooks_Realm_ID__c');
        result.namedCredential = cfg.namedCredential;
        String minorVersion = ConnectorConfigResolver.getValue('qbo', 'Minor_Version__c');
        if (String.isBlank(minorVersion)) {
            minorVersion = ConnectorConfigResolver.getValue('qbo', 'QuickBooks_Minor_Version__c');
        }
        if (String.isNotBlank(minorVersion)) {
            result.minorVersion = minorVersion.trim();
        }

        if (String.isBlank(result.realmId)) {
            throw new ConfigurationException('QuickBooks Realm ID is missing.');
        }
        if (String.isBlank(result.namedCredential)) {
            throw new ConfigurationException('QuickBooks Named Credential is missing.');
        }

        result.realmId = result.realmId.trim();
        result.namedCredential = result.namedCredential.trim();
        return result;
    }

    public static HttpResponse makeApiCall(String method, String resource, String body) {
        return makeApiCall(method, resource, body, true);
    }

    public static HttpResponse makeApiCall(
        String method,
        String resource,
        String body,
        Boolean logFailure
    ) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        
        QuickBooksConnectionConfig config = getConnectionConfig();
        String endpoint = buildEndpoint(resource, config.realmId, config.namedCredential, config.minorVersion);

        req.setEndpoint(endpoint);
        System.debug('Request Method: ' + method);
        System.debug('Request Endpoint: ' + endpoint);
        
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        System.debug('Headers Set');

        if (body != null) {
            req.setBody(body);
            System.debug('Request Body: ' + body);
        } else {
            System.debug('No Body Sent in Request');
        }

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
            System.debug('Response Status Code: ' + res.getStatusCode());
            System.debug('Response Body: ' + res.getBody());
            if ((res.getStatusCode() < 200 || res.getStatusCode() >= 300) && logFailure != false) {
                ErrorLogUtility.logCalloutFailure(
                    'QuickBooks',
                    'QuickBooksAuthHandler.makeApiCall',
                    method + ' ' + resource + ' failed with HTTP ' + res.getStatusCode() + ': ' + res.getBody(),
                    res.getStatusCode(),
                    null,
                    null
                );
            }
        } catch (Exception e) {
            System.debug('Exception occurred during HTTP callout: ' + e.getMessage());
            if (logFailure != false) {
                ErrorLogUtility.logException(
                    'QuickBooks',
                    'QuickBooksAuthHandler.makeApiCall',
                    e,
                    null,
                    null
                );
            }
            throw e;
        }

        return res;
    }

    public static HttpResponse makeBinaryApiCall(String resource) {
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');

        QuickBooksConnectionConfig config = getConnectionConfig();
        String endpoint = buildEndpoint(resource, config.realmId, config.namedCredential, config.minorVersion);

        req.setEndpoint(endpoint);
        req.setHeader('Content-Type', 'application/pdf');
        req.setHeader('Accept', 'application/pdf');

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                ErrorLogUtility.logCalloutFailure(
                    'QuickBooks',
                    'QuickBooksAuthHandler.makeBinaryApiCall',
                    'GET ' + resource + ' failed with HTTP ' + res.getStatusCode() + ': ' + res.getStatus(),
                    res.getStatusCode(),
                    null,
                    null
                );
            }
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QuickBooksAuthHandler.makeBinaryApiCall',
                e,
                null,
                null
            );
            throw e;
        }

        return res;
    }

    @TestVisible
    static String buildEndpointForTest(String resource, String realmId, String namedCredential, String minorVersion) {
        return buildEndpoint(resource, realmId, namedCredential, minorVersion);
    }

    private static String buildEndpoint(String resource, String realmId, String namedCredential, String minorVersion) {
        if (String.isBlank(namedCredential)) {
            throw new ConfigurationException('QuickBooks Named Credential is missing.');
        }
        if (String.isBlank(realmId)) {
            throw new ConfigurationException('QuickBooks Realm ID is missing.');
        }

        String safeNamedCredential = namedCredential.trim();
        String safeRealmId = realmId.trim();
        String safeResource = String.isBlank(resource) ? '' : resource.trim();
        String safeMinorVersion = String.isBlank(minorVersion) ? null : minorVersion.trim();
        String endpoint = 'callout:' + safeNamedCredential + QB_API_PATH + safeRealmId + safeResource;
        if (String.isBlank(safeMinorVersion) || safeResource.toLowerCase().contains('minorversion=')) {
            return endpoint;
        }
        return endpoint + (safeResource.contains('?') ? '&' : '?') + 'minorversion=' + EncodingUtil.urlEncode(safeMinorVersion, 'UTF-8');
    }

    public static void validateConfiguration() {
        if (Test.isRunningTest() && String.isNotBlank(testRealmId) && String.isNotBlank(testNamedCredential)) {
            return;
        }
        ConnectorConfigService.ConnectorConfig cfg = ConnectorConfigService.getConfig('qbo');
        if (cfg == null || cfg.active != true) {
            throw new AuraHandledException('QuickBooks Online is inactive. Please activate it in Settings.');
        }
        String realmId = cfg.values != null ? cfg.values.get('QuickBooks_Realm_ID__c') : null;
        if (String.isBlank(realmId)) {
            throw new AuraHandledException('QuickBooks Online Realm ID is missing. Please configure it in Settings.');
        }
        QuickBooksConnectionConfig connectionConfig = getConnectionConfig();
        if (String.isBlank(connectionConfig.namedCredential)) {
            throw new AuraHandledException('QuickBooks Online Named Credential is missing. Please configure it in Settings.');
        }
    }
}