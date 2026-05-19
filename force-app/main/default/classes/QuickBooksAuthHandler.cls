public without sharing class QuickBooksAuthHandler {
    private static final String DEFAULT_NAMED_CREDENTIAL = 'QuickBridgeTLG__QuickBookSandbox';
    private static final String QB_API_PATH = '/v3/company/';
    private static final String DEFAULT_MINOR_VERSION = '65';

    private class QuickBooksConnectionConfig {
        String realmId;
        String namedCredential;
        String minorVersion;
    }
    
    private static QuickBooksConnectionConfig getConnectionConfig() {
        QuickBooksConnectionConfig result = new QuickBooksConnectionConfig();
        result.namedCredential = DEFAULT_NAMED_CREDENTIAL;
        result.minorVersion = DEFAULT_MINOR_VERSION;

        List<QuickBooks_Config__mdt> rows = [
            SELECT Realm_ID__c, Named_Credential__c, Minor_Version__c
            FROM QuickBooks_Config__mdt
            WHERE Realm_ID__c != null
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            QuickBooks_Config__mdt config = rows[0];
            result.realmId = config.Realm_ID__c;
            if (String.isNotBlank(config.Named_Credential__c)) {
                result.namedCredential = config.Named_Credential__c.trim();
            }
            if (String.isNotBlank(config.Minor_Version__c)) {
                result.minorVersion = config.Minor_Version__c.trim();
            }
        }
        return result;
    }

    public static HttpResponse makeApiCall(String method, String resource, String body) {
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
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
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
            ErrorLogUtility.logException(
                'QuickBooks',
                'QuickBooksAuthHandler.makeApiCall',
                e,
                null,
                null
            );
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
        String safeNamedCredential = String.isBlank(namedCredential) ? DEFAULT_NAMED_CREDENTIAL : namedCredential.trim();
        String safeResource = String.isBlank(resource) ? '' : resource.trim();
        String safeMinorVersion = String.isBlank(minorVersion) ? DEFAULT_MINOR_VERSION : minorVersion.trim();
        String endpoint = 'callout:' + safeNamedCredential + QB_API_PATH + realmId + safeResource;
        if (String.isBlank(safeMinorVersion) || safeResource.toLowerCase().contains('minorversion=')) {
            return endpoint;
        }
        return endpoint + (safeResource.contains('?') ? '&' : '?') + 'minorversion=' + EncodingUtil.urlEncode(safeMinorVersion, 'UTF-8');
    }
}