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

    private class QBAuthExceptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Forced callout exception');
        }
    }

    @testSetup
    static void setupData() {
        insert new Account(Name = 'Auth Handler Seed');
    }

    @isTest
    static void testMakeApiCall() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'Custom_QB_Named_Credential', '70');
        Test.setMock(HttpCalloutMock.class, new QBAuthMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', '/customer/1', '{"body":true}');
        System.assertEquals(200, res.getStatusCode());
        Test.stopTest();
    }

    @isTest
    static void testMakeApiCallWithNullBody() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'Custom_QB_Named_Credential', '70');
        Test.setMock(HttpCalloutMock.class, new QBAuthMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', '/customer/1', null);
        System.assertEquals(200, res.getStatusCode());
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
            System.assert(false);
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Named Credential'));
        }
    }

    @isTest
    static void endpointRequiresConfiguredRealmId() {
        try {
            QuickBooksAuthHandler.buildEndpointForTest('/customer/1', null, 'Custom_QB_Named_Credential', null);
            System.assert(false);
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Realm ID'));
        }
    }

    @isTest
    static void makeApiCallLogsNonSuccessResponseWithoutThrowing() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'Custom_QB_Named_Credential', '70');
        Test.setMock(HttpCalloutMock.class, new QBAuthFailureMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', '/customer/1', null);
        System.assertEquals(503, res.getStatusCode());
        Test.stopTest();
    }

    @isTest
    static void makeApiCallThrowsException() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'Custom_QB_Named_Credential', '70');
        Test.setMock(HttpCalloutMock.class, new QBAuthExceptionMock());
        Test.startTest();
        try {
            QuickBooksAuthHandler.makeApiCall('GET', '/customer/1', null);
            System.assert(false);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testMakeBinaryApiCallSuccess() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'Custom_QB_Named_Credential', '70');
        Test.setMock(HttpCalloutMock.class, new QBAuthMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthHandler.makeBinaryApiCall('/customer/1/pdf');
        System.assertEquals(200, res.getStatusCode());
        Test.stopTest();
    }

    @isTest
    static void testMakeBinaryApiCallFailure() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'Custom_QB_Named_Credential', '70');
        Test.setMock(HttpCalloutMock.class, new QBAuthFailureMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthHandler.makeBinaryApiCall('/customer/1/pdf');
        System.assertEquals(503, res.getStatusCode());
        Test.stopTest();
    }

    @isTest
    static void testMakeBinaryApiCallException() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'Custom_QB_Named_Credential', '70');
        Test.setMock(HttpCalloutMock.class, new QBAuthExceptionMock());
        Test.startTest();
        try {
            QuickBooksAuthHandler.makeBinaryApiCall('/customer/1/pdf');
            System.assert(false);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testValidateConfigurationWithTestConfig() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'Custom_QB_Named_Credential', '70');
        Test.startTest();
        QuickBooksAuthHandler.validateConfiguration();
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testValidateConfigurationWithoutTestConfig() {
        QuickBooksAuthHandler.configureConnectionForTest(null, null, null);
        Test.startTest();
        try {
            QuickBooksAuthHandler.validateConfiguration();
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGetConnectionConfigMissingRecordException() {
        QuickBooksAuthHandler.configureConnectionForTest(null, null, null);
        Test.startTest();
        try {
            QuickBooksAuthHandler.makeApiCall('GET', '/customer/1', null);
            System.assert(false);
        } catch (Exception e) {
            System.assert(e.getMessage().contains('configuration record was not found'));
        }
        Test.stopTest();
    }
}