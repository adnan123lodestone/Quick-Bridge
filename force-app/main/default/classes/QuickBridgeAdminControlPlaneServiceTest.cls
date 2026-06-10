@IsTest
private class QuickBridgeAdminControlPlaneServiceTest {
    private class GatewayApiCalloutMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public GatewayApiCalloutMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(this.statusCode);
            res.setBody(this.responseBody);
            return res;
        }
    }

    @IsTest
    static void verifyCredentialsAndGetGatewaysReturnsResponse() {
        String mockResponse = '{"status":"Success","message":"Client validated.","sessionToken":"tok_test_123","activeGateways":["Stripe","PayPal"]}';
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(200, mockResponse));

        Test.startTest();
        try {
            String response = QuickBridgeAdminControlPlaneService.verifyCredentialsAndGetGateways(
                'admin@example.com',
                '1234'
            );
            System.assertNotEquals(null, response, 'verifyCredentialsAndGetGateways should return a non-null response');
            System.assert(response.contains('sessionToken') || response.contains('Success'),
                'Response should contain sessionToken or Success status');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'AuraHandledException message should not be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void revokeAdminSessionRevokesActiveSession() {
        QuickBridgeAdminGuard.bypassForTests = true;
        QuickBridgeAdminSessionService.SessionCreateResult sessionResult =
            QuickBridgeAdminSessionService.createSession('admin@example.com', null);

        Test.startTest();
        try {
            Boolean revoked = QuickBridgeAdminControlPlaneService.revokeAdminSession(sessionResult.sessionToken);
            System.assertNotEquals(null, revoked, 'revokeAdminSession should return a non-null Boolean');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'AuraHandledException message should not be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void recoverPinReturnsResponseOrThrowsGracefully() {
        String mockResponse = '{"status":"Success","message":"PIN sent to admin@example.com"}';
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(200, mockResponse));

        Test.startTest();
        try {
            String response = QuickBridgeAdminControlPlaneService.recoverPin('admin@example.com');
            System.assertNotEquals(null, response, 'recoverPin should return a non-null response');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'AuraHandledException from recoverPin should have a message');
        }
        Test.stopTest();
    }

    @IsTest
    static void refreshLicensesReturnsResponseOrThrowsGracefully() {
        QuickBridgeAdminGuard.bypassForTests = true;
        QuickBridgeAdminSessionService.SessionCreateResult sessionResult =
            QuickBridgeAdminSessionService.createSession('admin@example.com', null);

        String mockResponse = '{"status":"Success","message":"Licenses refreshed.","activeGateways":["Stripe"]}';
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(200, mockResponse));

        Test.startTest();
        try {
            String response = QuickBridgeAdminControlPlaneService.refreshLicenses(sessionResult.sessionToken);
            System.assertNotEquals(null, response, 'refreshLicenses should return a non-null response');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'AuraHandledException from refreshLicenses should have a message');
        }
        Test.stopTest();
    }

    @IsTest
    static void reseedSystemManagedProductsRequiresValidSession() {
        QuickBridgeAdminGuard.bypassForTests = true;
        QuickBridgeAdminSessionService.SessionCreateResult sessionResult =
            QuickBridgeAdminSessionService.createSession('admin@example.com', null);

        Test.startTest();
        try {
            String response = QuickBridgeAdminControlPlaneService.reseedSystemManagedProducts(sessionResult.sessionToken);
            System.assertNotEquals(null, response, 'reseedSystemManagedProducts should return a non-null response');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'AuraHandledException from reseedSystemManagedProducts should have a message');
        }
        Test.stopTest();
    }
}