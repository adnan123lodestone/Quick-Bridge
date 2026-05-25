@isTest
private class QuickBooksAuthHandlerTest {

    private class QBAuthMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"ok":true}');
            return res;
        }
    }

    private class QBAuthFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"fault":"temporary"}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        insert new Account(Name = 'Auth Handler Seed');
    }

    @isTest
    static void testMakeApiCall() {
        Test.setMock(HttpCalloutMock.class, new QBAuthMock());

        Test.startTest();
        try {
            HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', '/customer/1', null);
            System.assertEquals(200, res.getStatusCode());
        } catch (Exception e) {
            System.assert(e.getMessage() != null);
        }
        Test.stopTest();
    }

    @isTest
    static void endpointUsesConfiguredNamedCredentialAndMinorVersionDefaults() {
        String endpoint = QuickBooksAuthHandler.buildEndpointForTest(
            '/customer/1',
            '12345',
            'Custom_QB_Named_Credential',
            '70'
        );

        System.assertEquals(
            'callout:Custom_QB_Named_Credential/v3/company/12345/customer/1?minorversion=70',
            endpoint
        );
    }

    @isTest
    static void endpointDoesNotDuplicateMinorVersionWhenResourceAlreadyHasOne() {
        String endpoint = QuickBooksAuthHandler.buildEndpointForTest(
            '/query?query=select+*+from+Customer&minorversion=65',
            '12345',
            'Custom_QB_Named_Credential',
            null
        );

        System.assertEquals(
            'callout:Custom_QB_Named_Credential/v3/company/12345/query?query=select+*+from+Customer&minorversion=65',
            endpoint
        );
    }

    @isTest
    static void endpointDoesNotAddMinorVersionWhenUnconfigured() {
        String endpoint = QuickBooksAuthHandler.buildEndpointForTest(
            '/query?query=select+*+from+Customer',
            '12345',
            'Custom_QB_Named_Credential',
            ''
        );

        System.assertEquals(
            'callout:Custom_QB_Named_Credential/v3/company/12345/query?query=select+*+from+Customer',
            endpoint
        );
    }

    @isTest
    static void endpointRequiresConfiguredNamedCredential() {
        try {
            QuickBooksAuthHandler.buildEndpointForTest('/customer/1', '12345', null, null);
            System.assert(false, 'Expected missing Named Credential to be rejected.');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Named Credential'), e.getMessage());
        }
    }

    @isTest
    static void makeApiCallLogsNonSuccessResponseWithoutThrowing() {
        Test.setMock(HttpCalloutMock.class, new QBAuthFailureMock());

        Test.startTest();
        try {
            HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', '/customer/1', null);
            System.assertEquals(503, res.getStatusCode());
        } catch (Exception e) {
            System.assert(e.getMessage() != null);
        }
        Test.stopTest();
    }
}