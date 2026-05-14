@IsTest
private class PayPalPaymentServiceTest {
    private static void useTestOverrides() {
        PayPalPaymentService.testBaseEndpointOverride = 'https://api-m.sandbox.paypal.com';
        PayPalPaymentService.testAccessTokenOverride = 'token_test_override';
    }

    private static void useEndpointOnlyOverride() {
        PayPalPaymentService.testBaseEndpointOverride = 'https://api-m.sandbox.paypal.com';
        PayPalPaymentService.testAccessTokenOverride = null;
    }

    private class SuccessCreateAndCaptureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();

            if (request.getEndpoint().contains('/v1/oauth2/token')) {
                response.setStatusCode(200);
                response.setBody('{"access_token":"token_123","token_type":"Bearer"}');
                return response;
            }

            if (request.getEndpoint().contains('/v2/checkout/orders/') && request.getEndpoint().endsWith('/capture')) {
                response.setStatusCode(201);
                response.setBody('{"id":"5O190127TN364715T","status":"COMPLETED","purchase_units":[{"payments":{"captures":[{"id":"3C679366HH908993F","status":"COMPLETED"}]}}]}');
                return response;
            }

            response.setStatusCode(201);
            response.setBody('{"id":"5O190127TN364715T","status":"CREATED","links":[{"href":"https://www.paypal.com/checkoutnow?token=5O190127TN364715T","rel":"approve","method":"GET"}]}');
            return response;
        }
    }

    private class OrderReferenceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();

            if (request.getEndpoint().contains('/v1/oauth2/token')) {
                response.setStatusCode(200);
                response.setBody('{"access_token":"token_123","token_type":"Bearer"}');
                return response;
            }

            System.assert(request.getBody().contains('"reference_id":"801000000000001AAA"'));
            System.assert(request.getBody().contains('"custom_id":"801000000000001AAA"'));
            System.assert(request.getBody().contains('"invoice_id":"801000000000001AAA"'));

            response.setStatusCode(201);
            response.setBody('{"id":"ORDER_WITH_REFERENCE","status":"CREATED"}');
            return response;
        }
    }

    private class PayPalErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();

            if (request.getEndpoint().contains('/v1/oauth2/token')) {
                response.setStatusCode(200);
                response.setBody('{"access_token":"token_123","token_type":"Bearer"}');
                return response;
            }

            response.setStatusCode(422);
            response.setBody('{"name":"UNPROCESSABLE_ENTITY","message":"Request is not well-formed.","details":[{"description":"Amount is invalid."}]}');
            return response;
        }
    }

    private class InvalidCreateBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint().contains('/v1/oauth2/token')) {
                response.setStatusCode(200);
                response.setBody('{"access_token":"token_123","token_type":"Bearer"}');
                return response;
            }
            response.setStatusCode(201);
            response.setBody('not-json');
            return response;
        }
    }

    private class CurrencyDefaultMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            
            if (request.getEndpoint().contains('/v1/oauth2/token')) {
                response.setStatusCode(200);
                response.setBody('{"access_token":"token_123","token_type":"Bearer"}');
                return response;
            }

            if (request.getEndpoint().contains('/v2/checkout/orders/')) {
                response.setStatusCode(201);
                response.setBody('{"id":"ORDER_CURRENCY_TEST","status":"CREATED"}');
                return response;
            }

            System.assert(request.getBody().contains('"currency_code":"USD"'));
            response.setStatusCode(201);
            response.setBody('{"id":"ORDER_CURRENCY_TEST","status":"CREATED"}');
            return response;
        }
    }

    private class CaptureErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint().contains('/v1/oauth2/token')) {
                response.setStatusCode(200);
                response.setBody('{"access_token":"token_123","token_type":"Bearer"}');
                return response;
            }
            response.setStatusCode(422);
            response.setBody('{"name":"UNPROCESSABLE_ENTITY","message":"The order could not be captured."}');
            return response;
        }
    }

    private static Order createPaymentOrder() {
        Account account = new Account(Name = 'PayPal Error Account');
        insert account;
        Order orderRecord = new Order(
            AccountId = account.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert orderRecord;
        return orderRecord;
    }

    @IsTest
    static void getClientConfig_returnsResponse() {
        Test.startTest();
        PayPalPaymentService.ClientConfigResponse response = PayPalPaymentService.getClientConfig();
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertNotEquals(null, response.message, 'Message should not be null');
        System.assert(response.payPalJsUrl.contains('https://www.paypal.com/sdk/js?client-id='), 'URL should contain the client-id format');
    }

    @IsTest
    static void createOrder_success() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new SuccessCreateAndCaptureMock());

        PayPalPaymentService.PaymentRequest request = new PayPalPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.currencyCode = 'USD';
        
        // ADDED TO COVER THE WRAPPER CLASS VARIABLES
        request.sessionToken = 'test_session_token';
        request.fullName = 'Test User';
        request.address = '123 Test Ave';
        request.city = 'Test City';
        request.state = 'TX';
        request.zip = '75000';
        request.country = 'US';
        request.allowPlatformSession = true;

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(request);
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('5O190127TN364715T', response.paypalOrderId);
    }

    @IsTest
    static void createOrder_succeedsWithPendingWork() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new SuccessCreateAndCaptureMock());

        insert new Account(Name = 'Pending PayPal Callout Work');

        PayPalPaymentService.PaymentRequest request = new PayPalPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.currencyCode = 'USD';

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(request);
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('5O190127TN364715T', response.paypalOrderId);
    }

    @IsTest
    static void createOrder_succeedsWithoutSessionTokenForInternalAction() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new SuccessCreateAndCaptureMock());

        PayPalPaymentService.PaymentRequest request = new PayPalPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.currencyCode = 'USD';

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(request);
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('5O190127TN364715T', response.paypalOrderId);
    }

    @IsTest
    static void createOrder_allowsPlatformSessionForInternalAction() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new SuccessCreateAndCaptureMock());

        PayPalPaymentService.PaymentRequest request = new PayPalPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.allowPlatformSession = true;
        request.currencyCode = 'USD';

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(request);
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('5O190127TN364715T', response.paypalOrderId);
    }

    @IsTest
    static void createOrder_includesOrderReference() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new OrderReferenceMock());

        PayPalPaymentService.PaymentRequest request = new PayPalPaymentService.PaymentRequest();
        request.amount = 10.00;
        request.orderId = '801000000000001AAA';
        request.currencyCode = 'USD';

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(request);
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('ORDER_WITH_REFERENCE', response.paypalOrderId);
    }

    @IsTest
    static void createOrder_error() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new PayPalErrorMock());

        PayPalPaymentService.PaymentRequest request = new PayPalPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.currencyCode = 'USD';

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertNotEquals(null, response.message);
    }

    @IsTest
    static void captureOrder_success() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new SuccessCreateAndCaptureMock());

        PayPalPaymentService.CaptureRequest request = new PayPalPaymentService.CaptureRequest();
        request.paypalOrderId = '5O190127TN364715T';
        
        // ADDED TO COVER CAPTURE REQUEST WRAPPER VARIABLES
        request.allowPlatformSession = true;
        request.orderId = 'test_order_id';
        request.sessionToken = 'test_session_token';

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.captureOrder(request);
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('3C679366HH908993F', response.transId);
    }

    @IsTest
    static void captureOrder_missingOrderId() {
        PayPalPaymentService.CaptureRequest request = new PayPalPaymentService.CaptureRequest();

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.captureOrder(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertNotEquals(null, response.message);
    }

    @IsTest
    static void createOrder_missingRequest() {
        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(null);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertNotEquals(null, response.message);
    }

    @IsTest
    static void createOrder_missingAmount() {
        PayPalPaymentService.PaymentRequest request = new PayPalPaymentService.PaymentRequest();

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertNotEquals(null, response.message);
    }

    @IsTest
    static void createOrder_invalidJsonResponse() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new InvalidCreateBodyMock());

        PayPalPaymentService.PaymentRequest request = new PayPalPaymentService.PaymentRequest();
        request.amount = 12.50;

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assert(response.message.contains('invalid response'), 'Should handle bad JSON gracefully');
    }

    @IsTest
    static void createOrder_defaultsCurrencyCodeToUsd() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new CurrencyDefaultMock());

        PayPalPaymentService.PaymentRequest request = new PayPalPaymentService.PaymentRequest();
        request.amount = 10;

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(request);
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('ORDER_CURRENCY_TEST', response.paypalOrderId);
    }

    @IsTest
    static void captureOrder_error() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new CaptureErrorMock());

        PayPalPaymentService.CaptureRequest request = new PayPalPaymentService.CaptureRequest();
        request.paypalOrderId = 'ORDER_FAIL';

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.captureOrder(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertNotEquals(null, response.message);
    }

    @IsTest
    static void captureOrder_errorLogsAgainstOrder() {
        Order orderRecord = createPaymentOrder();
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new CaptureErrorMock());

        PayPalPaymentService.CaptureRequest request = new PayPalPaymentService.CaptureRequest();
        request.paypalOrderId = 'ORDER_FAIL';
        request.orderId = orderRecord.Id;

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.captureOrder(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log__c
            WHERE Order__c = :orderRecord.Id
            AND Gateway_Name__c = 'PayPal'
            AND Error_Category__c = 'Callout Failure'
        ]);
    }

    @IsTest
    static void captureOrder_succeedsWithoutSessionTokenForInternalAction() {
        useTestOverrides();
        Test.setMock(HttpCalloutMock.class, new SuccessCreateAndCaptureMock());

        PayPalPaymentService.CaptureRequest request = new PayPalPaymentService.CaptureRequest();
        request.paypalOrderId = '5O190127TN364715T';

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.captureOrder(request);
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('3C679366HH908993F', response.transId);
    }

    @IsTest
    static void createOrder_withOAuthCalloutPath() {
        useEndpointOnlyOverride();
        Test.setMock(HttpCalloutMock.class, new SuccessCreateAndCaptureMock());

        PayPalPaymentService.PaymentRequest request = new PayPalPaymentService.PaymentRequest();
        request.amount = 15;
        request.currencyCode = 'USD';

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(request);
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('5O190127TN364715T', response.paypalOrderId);
    }

    @IsTest
    static void captureOrder_withOAuthCalloutPath() {
        useEndpointOnlyOverride();
        Test.setMock(HttpCalloutMock.class, new SuccessCreateAndCaptureMock());

        PayPalPaymentService.CaptureRequest request = new PayPalPaymentService.CaptureRequest();
        request.paypalOrderId = '5O190127TN364715T';

        Test.startTest();
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.captureOrder(request);
        Test.stopTest();

        System.assertEquals(true, response.success, response.message);
        System.assertEquals('3C679366HH908993F', response.transId);
    }
}