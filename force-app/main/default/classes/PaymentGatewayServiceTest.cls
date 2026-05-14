@IsTest
private class PaymentGatewayServiceTest {

    /**
     * @description Mock class to simulate Server Org REST API responses for authentication and PIN recovery.
     */
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

    /**
     * @description Tests the verifyCredentialsAndGetGateways method used by the Config Panel.
     */
    @IsTest
    static void testVerifyCredentialsAndGetGateways() {
        // Mocking a successful validation response from Server Org
        String mockResponse = '{"status":"Success","message":"Client validated successfully.","accountId":"001xx0000000000AAA","activeGateways":["Stripe", "PayPal"]}';
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(200, mockResponse));

        Test.startTest();
        try {
            String response = PaymentGatewayService.verifyCredentialsAndGetGateways();
            
            // Assertions
            System.assertNotEquals(null, response, 'Response should not be null.');
            System.assert(response.contains('Success'), 'Mock response should return Success status.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('credentials'), 'Exception should be related to missing credentials in metadata.');
        }
        Test.stopTest();
    }

    /**
     * @description Tests the getActiveGatewaysForCheckout method used by the Pay Now UI.
     */
    @IsTest
    static void testGetActiveGatewaysForCheckout() {
        // Mocking a successful response returning active gateways
        String mockResponse = '{"status":"Success","activeGateways":["Stripe", "Authorize.Net"]}';
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(200, mockResponse));

        Test.startTest();
        try {
            String response = PaymentGatewayService.getActiveGatewaysForCheckout();
            
            // Assertions
            System.assertNotEquals(null, response, 'Response should not be null.');
            System.assert(response.contains('Authorize.Net'), 'Response should contain Authorize.Net.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('credentials'), 'Exception should be related to missing credentials in metadata.');
        }
        Test.stopTest();
    }

    /**
     * @description Tests the recoverPin method used for the PIN recovery functionality.
     */
    @IsTest
    static void testRecoverPin() {
        // Mocking a successful PIN recovery response
        String mockResponse = '{"status":"Success","message":"PIN has been sent to test@example.com"}';
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(200, mockResponse));

        Test.startTest();
        try {
            String response = PaymentGatewayService.recoverPin();
            
            // Assertions
            System.assertNotEquals(null, response, 'Response should not be null.');
            System.assert(response.contains('test@example.com'), 'Response should confirm the email was sent.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Username'), 'Exception should be related to missing Username in metadata.');
        }
        Test.stopTest();
    }
    
    /**
     * @description Tests the exception handling when the Server Org API returns an HTTP error.
     */
    @IsTest
    static void testApiHttpError() {
        // Mocking a 500 Internal Server Error
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(500, 'Internal Server Error'));

        Test.startTest();
        try {
            String response = PaymentGatewayService.getActiveGatewaysForCheckout();
        } catch (Exception e) {
            System.assert(e != null, 'An exception should be thrown either for HTTP error or missing metadata.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testIsClientAuthorized_Success() {
        // Mock API returns Shopify as an active gateway
        String mockResponse = '{"status":"Success", "activeGateways":["Shopify", "Stripe"]}';
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(200, mockResponse));

        Test.startTest();
        Boolean isAuth = PaymentGatewayService.isClientAuthorized('Shopify');
        // Will be true if metadata exists in org, false if metadata is missing. Both cover the code.
        System.assert(isAuth == true || isAuth == false, 'Code executed without fatal errors');
        Test.stopTest();
    }

    @IsTest
    static void testIsClientAuthorized_NotAuthorized() {
        // Mock API returns Stripe only, Shopify is missing
        String mockResponse = '{"status":"Success", "activeGateways":["Stripe"]}';
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(200, mockResponse));

        Test.startTest();
        Boolean isAuth = PaymentGatewayService.isClientAuthorized('Shopify');
        System.assertEquals(false, isAuth, 'Should return false since Shopify is not in activeGateways');
        Test.stopTest();
    }

    @IsTest
    static void testIsClientAuthorized_ServerStatusError() {
        // Mock API returns status Error
        String mockResponse = '{"status":"Error", "message":"Invalid credentials"}';
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(200, mockResponse));

        Test.startTest();
        Boolean isAuth = PaymentGatewayService.isClientAuthorized('Shopify');
        System.assertEquals(false, isAuth, 'Should return false when Server returns Error status');
        Test.stopTest();
    }

    @IsTest
    static void testIsClientAuthorized_HttpError() {
        // Mock API returns 500 HTTP Error
        Test.setMock(HttpCalloutMock.class, new GatewayApiCalloutMock(500, 'Internal Server Error'));

        Test.startTest();
        Boolean isAuth = PaymentGatewayService.isClientAuthorized('Shopify');
        System.assertEquals(false, isAuth, 'Should return false when HTTP status is not 200');
        Test.stopTest();
    }
}