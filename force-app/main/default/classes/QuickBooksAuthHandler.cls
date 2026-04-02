public class QuickBooksAuthHandler {
    private static final String xvy;
    private static final String NAMED_CREDENTIAL = 'Test_App';
    private static final String QB_API_PATH = '/v3/company/';
    private static final String MINOR_VERSION = '?minorversion=65';
    
    private static String getRealmId() {
        QuickBooks_Config__mdt config = [
            SELECT Realm_ID__c
            FROM QuickBooks_Config__mdt
            LIMIT 1
        ];
        return config.Realm_ID__c;
    }
    
    static {
        QuickBooks_Config__mdt config = [
            SELECT Realm_ID__c
            FROM QuickBooks_Config__mdt
            LIMIT 1
        ];
        xvy = config.Realm_ID__c;
    }

    public static HttpResponse makeApiCall(String method, String resource, String body) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        
        String realmId = getRealmId();
        String endpoint = 'callout:' + NAMED_CREDENTIAL + QB_API_PATH + realmId + resource + MINOR_VERSION;

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
        } catch (Exception e) {
            System.debug('Exception occurred during HTTP callout: ' + e.getMessage());
            throw e;
        }

        return res;
    }
}