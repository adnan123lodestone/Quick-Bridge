@isTest
private class QBOWebhookServiceTest {
    private class DummyBulkInvoiceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"QueryResponse":{"Invoice":[]}}');
            return res;
        }
    }

    @isTest
    static void validSignatureIsAccepted() {
        String body = '{"eventNotifications":[]}';
        QBOWebhookService.configureVerifierTokenForTest('unit-secret');
        RestContext.request = request(body, signature(body, 'unit-secret'));
        RestContext.response = new RestResponse();

        Test.startTest();
        QBOWebhookService.handleIncomingWebhook();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
    }

    @isTest
    static void invalidSignatureIsRejected() {
        String body = '{"eventNotifications":[]}';
        QBOWebhookService.configureVerifierTokenForTest('unit-secret');
        RestContext.request = request(body, 'bad-signature');
        RestContext.response = new RestResponse();

        Test.startTest();
        QBOWebhookService.handleIncomingWebhook();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
    }

    @isTest
    static void missingVerifierFailsClosed() {
        QBOWebhookService.configureVerifierTokenForTest('');
        RestContext.request = request('{"eventNotifications":[]}', null);
        RestContext.response = new RestResponse();

        Test.startTest();
        QBOWebhookService.handleIncomingWebhook();
        Test.stopTest();

        System.assertEquals(503, RestContext.response.statusCode);
    }

    @isTest
    static void processValidInvoiceEvent() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        // Build a realistic QBO Webhook JSON payload with Invoice events
        String body = '{"eventNotifications": [{"dataChangeEvent": {"entities": [' +
                      '{"name": "Invoice", "operation": "Create", "id": "INV-100"},' +
                      '{"name": "Invoice", "operation": "Update", "id": "INV-101"},' +
                      '{"name": "Customer", "operation": "Update", "id": "CUST-1"}' +
                      ']}}]}';
        
        QBOWebhookService.configureVerifierTokenForTest('unit-secret');
        RestContext.request = request(body, signature(body, 'unit-secret'));
        RestContext.response = new RestResponse();

        // The queued job will perform a callout, so we set a mock response
        Test.setMock(HttpCalloutMock.class, new DummyBulkInvoiceMock());

        Test.startTest();
        QBOWebhookService.handleIncomingWebhook();
        Test.stopTest(); // Forces the enqueued QBOInvoiceSyncQueueable to execute

        // Verify successful webhook processing
        System.assertEquals(200, RestContext.response.statusCode, 'Valid payload with entities should return 200 OK');
    }

    @isTest
    static void testCatchBlockWithMalformedJSON() {
        // Pass malformed JSON to trigger JSONException during deserialization
        String body = '{"eventNotifications": [ { BAD JSON ] }';
        
        QBOWebhookService.configureVerifierTokenForTest('unit-secret');
        RestContext.request = request(body, signature(body, 'unit-secret'));
        RestContext.response = new RestResponse();

        Test.startTest();
        QBOWebhookService.handleIncomingWebhook();
        Test.stopTest();

        // Catch block sets status code to 500
        System.assertEquals(500, RestContext.response.statusCode, 'Malformed JSON should trigger catch block and return 500');
    }

    private static RestRequest request(String body, String signatureValue) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/qbo/webhook/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        if (signatureValue != null) {
            req.addHeader('intuit-signature', signatureValue);
        }
        return req;
    }

    private static String signature(String body, String verifierToken) {
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(verifierToken));
        return EncodingUtil.base64Encode(mac);
    }
}