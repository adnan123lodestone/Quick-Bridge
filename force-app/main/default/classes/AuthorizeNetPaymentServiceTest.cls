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

    private class HttpFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(503);
            response.setBody('Service unavailable');
            return response;
        }
    }

    private class InvalidResponseMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('not-json');
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

    private static Order createPaymentOrder() {
        Account account = new Account(Name = 'Authorize.Net Error Account');
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
        AuthorizeNetPaymentService.ClientConfigResponse response = AuthorizeNetPaymentService.getClientConfig();
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null.');
        System.assertNotEquals(null, response.apiLoginId, 'API Login ID should be populated.');
        System.assertNotEquals(null, response.publicClientKey, 'Public Client Key should be populated.');
        System.assertEquals(true, response.configured, 'Configured flag should be true.');
        System.assertNotEquals(null, response.message, 'Message should not be null.');
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
    static void processOpaquePayment_errorLogsAgainstOrder() {
        Order orderRecord = createPaymentOrder();
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        AuthorizeNetPaymentService.PaymentRequest request = new AuthorizeNetPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.orderId = orderRecord.Id;
        request.dataDescriptor = 'COMMON.ACCEPT.INAPP.PAYMENT';
        request.dataValue = 'opaque-token';

        Test.startTest();
        AuthorizeNetPaymentService.PaymentResponse response = AuthorizeNetPaymentService.processOpaquePayment(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log__c
            WHERE Order__c = :orderRecord.Id
            AND Gateway_Name__c = 'Authorize.Net'
            AND Error_Category__c = 'Payment Error'
        ]);
    }

    @IsTest
    static void processOpaquePayment_httpFailureLogsAgainstOrder() {
        Order orderRecord = createPaymentOrder();
        Test.setMock(HttpCalloutMock.class, new HttpFailureMock());

        AuthorizeNetPaymentService.PaymentRequest request = new AuthorizeNetPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.orderId = orderRecord.Id;
        request.dataDescriptor = 'COMMON.ACCEPT.INAPP.PAYMENT';
        request.dataValue = 'opaque-token';

        Test.startTest();
        AuthorizeNetPaymentService.PaymentResponse response = AuthorizeNetPaymentService.processOpaquePayment(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log__c
            WHERE Order__c = :orderRecord.Id
            AND Gateway_Name__c = 'Authorize.Net'
            AND Error_Category__c = 'Callout Failure'
            AND Http_Status_Code__c = 503
        ]);
    }

    @IsTest
    static void processOpaquePayment_invalidResponseLogsUnparented() {
        Test.setMock(HttpCalloutMock.class, new InvalidResponseMock());

        AuthorizeNetPaymentService.PaymentRequest request = new AuthorizeNetPaymentService.PaymentRequest();
        request.amount = 25.00;
        request.dataDescriptor = 'COMMON.ACCEPT.INAPP.PAYMENT';
        request.dataValue = 'opaque-token';

        Test.startTest();
        AuthorizeNetPaymentService.PaymentResponse response = AuthorizeNetPaymentService.processOpaquePayment(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log__c
            WHERE Order__c = null
            AND Gateway_Name__c = 'Authorize.Net'
            AND Error_Category__c = 'Callout Failure'
            AND Http_Status_Code__c = 200
        ]);
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