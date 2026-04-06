@IsTest
private class AuthorizeNetPaymentServiceTest {
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"transactionResponse":{"responseCode":"1","authCode":"ABC123","transId":"60012345678"},"messages":{"resultCode":"Ok","message":[{"code":"I00001","text":"Successful."}]}}');
            return response;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"transactionResponse":{"responseCode":"3","errors":[{"errorCode":"2","errorText":"The transaction was declined."}]},"messages":{"resultCode":"Error","message":[{"code":"E00027","text":"The transaction was unsuccessful."}]}}');
            return response;
        }
    }

    private class OrderReferenceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getBody().contains('"refId":"801000000000001AAA"'));

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"transactionResponse":{"responseCode":"1","authCode":"ABC123","transId":"60012345679"},"messages":{"resultCode":"Ok","message":[{"code":"I00001","text":"Successful."}]}}');
            return response;
        }
    }

    @IsTest
    static void getClientConfig_handlesMissingPublicClientKey() {
        Test.startTest();
        AuthorizeNetPaymentService.ClientConfigResponse response = AuthorizeNetPaymentService.getClientConfig();
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals('2aBPd89rBMC', response.apiLoginId);
        System.assertNotEquals(null, response.message);
    }

    @IsTest
    static void processOpaquePayment_success() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        AuthorizeNetPaymentService.PaymentRequest request = new AuthorizeNetPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.dataDescriptor = 'COMMON.ACCEPT.INAPP.PAYMENT';
        request.dataValue = 'opaque-token';
        request.fullName = 'Test User';
        request.zip = '48104';

        Test.startTest();
        AuthorizeNetPaymentService.PaymentResponse response = AuthorizeNetPaymentService.processOpaquePayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('Transaction Successful', response.message);
        System.assertEquals('60012345678', response.transId);
        System.assertEquals('ABC123', response.authCode);
    }

    @IsTest
    static void processOpaquePayment_succeedsWithPendingWork() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        insert new Account(Name = 'Pending Authorize.Net Callout Work');

        AuthorizeNetPaymentService.PaymentRequest request = new AuthorizeNetPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.dataDescriptor = 'COMMON.ACCEPT.INAPP.PAYMENT';
        request.dataValue = 'opaque-token';

        Test.startTest();
        AuthorizeNetPaymentService.PaymentResponse response = AuthorizeNetPaymentService.processOpaquePayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('60012345678', response.transId);
    }

    @IsTest
    static void processOpaquePayment_error() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        AuthorizeNetPaymentService.PaymentRequest request = new AuthorizeNetPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.dataDescriptor = 'COMMON.ACCEPT.INAPP.PAYMENT';
        request.dataValue = 'opaque-token';

        Test.startTest();
        AuthorizeNetPaymentService.PaymentResponse response = AuthorizeNetPaymentService.processOpaquePayment(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('The transaction was declined.', response.message);
    }

    @IsTest
    static void processOpaquePayment_allowsPlatformSessionForInternalAction() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        AuthorizeNetPaymentService.PaymentRequest request = new AuthorizeNetPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.allowPlatformSession = true;
        request.dataDescriptor = 'COMMON.ACCEPT.INAPP.PAYMENT';
        request.dataValue = 'opaque-token';

        Test.startTest();
        AuthorizeNetPaymentService.PaymentResponse response = AuthorizeNetPaymentService.processOpaquePayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('60012345678', response.transId);
    }

    @IsTest
    static void processOpaquePayment_includesOrderReference() {
        Test.setMock(HttpCalloutMock.class, new OrderReferenceMock());

        AuthorizeNetPaymentService.PaymentRequest request = new AuthorizeNetPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.orderId = '801000000000001AAA';
        request.dataDescriptor = 'COMMON.ACCEPT.INAPP.PAYMENT';
        request.dataValue = 'opaque-token';

        Test.startTest();
        AuthorizeNetPaymentService.PaymentResponse response = AuthorizeNetPaymentService.processOpaquePayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('60012345679', response.transId);
    }

    @IsTest
    static void processOpaquePayment_succeedsWithoutSessionTokenForInternalAction() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        AuthorizeNetPaymentService.PaymentRequest request = new AuthorizeNetPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.dataDescriptor = 'COMMON.ACCEPT.INAPP.PAYMENT';
        request.dataValue = 'opaque-token';

        Test.startTest();
        AuthorizeNetPaymentService.PaymentResponse response = AuthorizeNetPaymentService.processOpaquePayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('60012345678', response.transId);
    }
}