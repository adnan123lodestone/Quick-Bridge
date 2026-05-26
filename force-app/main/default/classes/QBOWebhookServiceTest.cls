@isTest
private class QBOWebhookServiceTest {
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