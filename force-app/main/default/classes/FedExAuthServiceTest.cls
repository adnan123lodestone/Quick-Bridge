@isTest
public class FedExAuthServiceTest {
    
    // Mock for successful token response
    private class FedExSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"access_token":"testToken123","token_type":"Bearer","expires_in":3600}');
            return res;
        }
    }
    
    // Mock for failed response
    private class FedExFailureMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('{"error":"invalid_client"}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        // Insert Custom Metadata using Test Metadata (available in test context)
        // Metadata cannot be inserted in tests directly, so we mock via Stub below
        // But for SOQL to work, use Custom Metadata Loader if already deployed
        
        // Workaround: Use Custom Settings instead if not using CMDT in tests
        // If CMDT exists, no need to insert, it will be queried automatically
    }

    @isTest
    static void testGetAccessToken_SuccessSandbox() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new FedExSuccessMock());
        // Call method
        String token = FedExAuthService.getAccessToken();
        System.assertEquals('testToken123', token, 'Access token should match mocked value');
        Test.stopTest();
    }

    @isTest
    static void testGetAccessToken_Failure() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new FedExFailureMock());
        Boolean exceptionThrown = false;
        try {
            FedExAuthService.getAccessToken();
        } catch (Exception e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('FedEx Auth Failed'), 'Exception message should indicate FedEx auth failure');
        }
        System.assertEquals(true, exceptionThrown, 'Exception should be thrown on failed auth');
        Test.stopTest();
    }
}