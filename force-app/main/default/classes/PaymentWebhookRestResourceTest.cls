@IsTest
private class PaymentWebhookRestResourceTest {
    @IsTest
    static void stripeSuccess_createsWebhookLog() {
        Order orderRecord = createOrderRecord();
        String payload =
            '{"id":"evt_3THA7xCkZ7oErXIz1DckNdkz","object":"event","created":1774993634,' +
            '"data":{"object":{"id":"pi_3THA7xCkZ7oErXIz1SmgVXm4","amount":5915,"amount_received":5915,' +
            '"capture_method":"automatic_async","currency":"usd","latest_charge":"ch_3THA7xCkZ7oErXIz1QImscru",' +
            '"customer":"cus_3THA7xCkZ7oErXIz1ABCDEF",' +
            '"livemode":false,"metadata":{"order_id":"' + orderRecord.Id + '","reference_number":"' + orderRecord.Id + '"},' +
            '"payment_method":"pm_1THA7wCkZ7oErXIz3MXYkbCT","status":"succeeded"}},"request":{"id":"req_E5vD8sflSeAxeA"},' +
            '"type":"payment_intent.succeeded"}';
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/stripe',
            payload
        );
        RestContext.request.addHeader('Stripe-Signature', buildStripeSignatureHeader(payload));
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, response.success);
        System.assertEquals(true, response.recordCreated);

        Portal_Payment_Transaction__c logRecord = [
            SELECT Id, Order__c, Payment_Type__c, Payload__c,
                Gateway_Event_Id__c, Gateway_Event_Type__c, Gateway_Event_Date__c,
                Gateway_Amount__c, Gateway_Currency__c, Gateway_Reference_Number__c,
                Gateway_Transaction_Id__c, Stripe_Status__c, Stripe_Charge_Id__c,
                Stripe_Customer_Id__c,
                Stripe_Payment_Method_Id__c, Stripe_Request_Id__c,
                Stripe_Capture_Method__c, Stripe_Live_Mode__c
            FROM Portal_Payment_Transaction__c
            LIMIT 1
        ];
        System.assertEquals(orderRecord.Id, logRecord.Order__c);
        System.assertEquals('Stripe', logRecord.Payment_Type__c);
        System.assert(logRecord.Payload__c.contains('payment_intent.succeeded'));
        System.assertEquals('evt_3THA7xCkZ7oErXIz1DckNdkz', logRecord.Gateway_Event_Id__c);
        System.assertEquals('payment_intent.succeeded', logRecord.Gateway_Event_Type__c);
        System.assertEquals(59.15, logRecord.Gateway_Amount__c);
        System.assertEquals('usd', logRecord.Gateway_Currency__c);
        System.assertEquals(orderRecord.Id, logRecord.Gateway_Reference_Number__c);
        System.assertEquals('pi_3THA7xCkZ7oErXIz1SmgVXm4', logRecord.Gateway_Transaction_Id__c);
        System.assertEquals('succeeded', logRecord.Stripe_Status__c);
        System.assertEquals('ch_3THA7xCkZ7oErXIz1QImscru', logRecord.Stripe_Charge_Id__c);
        System.assertEquals('cus_3THA7xCkZ7oErXIz1ABCDEF', logRecord.Stripe_Customer_Id__c);
        System.assertEquals('pm_1THA7wCkZ7oErXIz3MXYkbCT', logRecord.Stripe_Payment_Method_Id__c);
        System.assertEquals('req_E5vD8sflSeAxeA', logRecord.Stripe_Request_Id__c);
        System.assertEquals('automatic_async', logRecord.Stripe_Capture_Method__c);
        System.assertEquals(false, logRecord.Stripe_Live_Mode__c);
        System.assertNotEquals(null, logRecord.Gateway_Event_Date__c);
    }

    @IsTest
    static void stripeInvoicePaid_createsWebhookLog() {
        Order orderRecord = createOrderRecord();
        String payload =
            '{"id":"evt_invoice_paid_123","object":"event","created":1774993634,' +
            '"data":{"object":{"id":"in_123","amount_due":2000,"amount_paid":2000,"currency":"usd",' +
            '"customer":"cus_invoice_123","invoice_pdf":"https://pay.stripe.com/invoice/test_123/pdf",' +
            '"livemode":false,' +
            '"metadata":{"order_id":"' + orderRecord.Id + '"},' +
            '"status":"paid"}},"type":"invoice.paid"}';
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/stripe',
            payload
        );
        RestContext.request.addHeader('Stripe-Signature', buildStripeSignatureHeader(payload));
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, response.success);
        System.assertEquals(true, response.recordCreated);

        Portal_Payment_Transaction__c logRecord = [
            SELECT Id, Order__c, Gateway_Event_Type__c, Gateway_Amount__c,
                Gateway_Reference_Number__c, Gateway_Transaction_Id__c,
                Stripe_Status__c, Stripe_Customer_Id__c, Stripe_Invoice_PDF_Url__c
            FROM Portal_Payment_Transaction__c
            WHERE Gateway_Event_Id__c = 'evt_invoice_paid_123'
            LIMIT 1
        ];
        System.assertEquals(orderRecord.Id, logRecord.Order__c);
        System.assertEquals('invoice.paid', logRecord.Gateway_Event_Type__c);
        System.assertEquals(20, logRecord.Gateway_Amount__c);
        System.assertEquals(orderRecord.Id, logRecord.Gateway_Reference_Number__c);
        System.assertEquals('in_123', logRecord.Gateway_Transaction_Id__c);
        System.assertEquals('paid', logRecord.Stripe_Status__c);
        System.assertEquals('cus_invoice_123', logRecord.Stripe_Customer_Id__c);
        System.assertEquals('https://pay.stripe.com/invoice/test_123/pdf', logRecord.Stripe_Invoice_PDF_Url__c);
    }

    @IsTest
    static void authorizeNetSuccess_createsWebhookLog() {
        Order orderRecord = createOrderRecord();
        String payload =
            '{"notificationId":"67f73580-a1f9-47f8-9eaf-da2c6cb277a1",' +
            '"eventType":"net.authorize.payment.authcapture.created",' +
            '"eventDate":"2026-04-01T12:32:46.7023538Z",' +
            '"webhookId":"7841e308-70c9-46e8-b2c5-3a5f463ac368",' +
            '"payload":{"responseCode":1,"authCode":"WA6O68","avsResponse":"Y","authAmount":59.15,' +
            '"merchantReferenceId":"' + orderRecord.Id + '","entityName":"transaction","id":"80053527851"}}';
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/authorizenet',
            payload
        );
        RestContext.request.addHeader('X-ANET-SIGNATURE', buildAuthorizeNetSignatureHeader(payload));
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, response.recordCreated);

        Portal_Payment_Transaction__c logRecord = [
            SELECT Id, Order__c, Payment_Type__c,
                Gateway_Event_Id__c, Gateway_Event_Type__c, Gateway_Event_Date__c,
                Gateway_Amount__c, Gateway_Reference_Number__c, Gateway_Transaction_Id__c,
                AuthorizeNet_Webhook_Id__c, AuthorizeNet_Response_Code__c,
                AuthorizeNet_Auth_Code__c, AuthorizeNet_AVS_Response__c,
                AuthorizeNet_Entity_Name__c
            FROM Portal_Payment_Transaction__c
            LIMIT 1
        ];
        System.assertEquals(orderRecord.Id, logRecord.Order__c);
        System.assertEquals('Authorize.Net', logRecord.Payment_Type__c);
        System.assertEquals('67f73580-a1f9-47f8-9eaf-da2c6cb277a1', logRecord.Gateway_Event_Id__c);
        System.assertEquals('net.authorize.payment.authcapture.created', logRecord.Gateway_Event_Type__c);
        System.assertEquals(59.15, logRecord.Gateway_Amount__c);
        System.assertEquals(orderRecord.Id, logRecord.Gateway_Reference_Number__c);
        System.assertEquals('80053527851', logRecord.Gateway_Transaction_Id__c);
        System.assertEquals('7841e308-70c9-46e8-b2c5-3a5f463ac368', logRecord.AuthorizeNet_Webhook_Id__c);
        System.assertEquals(1, logRecord.AuthorizeNet_Response_Code__c);
        System.assertEquals('WA6O68', logRecord.AuthorizeNet_Auth_Code__c);
        System.assertEquals('Y', logRecord.AuthorizeNet_AVS_Response__c);
        System.assertEquals('transaction', logRecord.AuthorizeNet_Entity_Name__c);
        System.assertNotEquals(null, logRecord.Gateway_Event_Date__c);
    }

    @IsTest
    static void authorizeNetBareDigestAndHeaderCaseVariant_createsWebhookLog() {
        Order orderRecord = createOrderRecord();
        String payload = '{"notificationId":"124","eventType":"net.authorize.payment.capture.created","payload":{"merchantReferenceId":"' + orderRecord.Id + '","id":"60012345679"}}';
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/authorizenet',
            payload
        );
        RestContext.request.addHeader('x-anet-signature', buildAuthorizeNetSignatureDigest(payload).toLowerCase());
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, response.success);
        System.assertEquals(true, response.recordCreated);
    }

    @IsTest
    static void payPalSuccess_createsWebhookLog() {
        Order orderRecord = createOrderRecord();
        String payload = '{"id":"WH-123","event_type":"PAYMENT.CAPTURE.COMPLETED","resource":{"id":"3C679366HH908993F","custom_id":"' + orderRecord.Id + '"}}';
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/paypal',
            payload
        );
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, response.recordCreated);

        Portal_Payment_Transaction__c logRecord = [
            SELECT Id, Order__c, Payment_Type__c
            FROM Portal_Payment_Transaction__c
            LIMIT 1
        ];
        System.assertEquals(orderRecord.Id, logRecord.Order__c);
        System.assertEquals('PayPal', logRecord.Payment_Type__c);
    }

    @IsTest
    static void nonSuccessEvent_isIgnored() {
        String payload = '{"id":"evt_456","type":"payment_intent.payment_failed"}';
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/stripe',
            payload
        );
        RestContext.request.addHeader('Stripe-Signature', buildStripeSignatureHeader(payload));
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, response.success);
        System.assertEquals(false, response.recordCreated);
        System.assertEquals(0, [SELECT COUNT() FROM Portal_Payment_Transaction__c]);
    }

    @IsTest
    static void unsupportedPaymentType_returnsBadRequest() {
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/square',
            '{"id":"evt_789","type":"payment.updated"}'
        );
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals(false, response.recordCreated);
        System.assertEquals(0, [SELECT COUNT() FROM Portal_Payment_Transaction__c]);
    }

    @IsTest
    static void invalidStripeSignature_returnsUnauthorized() {
        String payload = '{"id":"evt_987","type":"payment_intent.succeeded"}';
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/stripe',
            payload
        );
        RestContext.request.addHeader('Stripe-Signature', 't=' + String.valueOf(Datetime.now().getTime() / 1000) + ',v1=bad_signature');
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals(false, response.recordCreated);
        System.assertEquals(0, [SELECT COUNT() FROM Portal_Payment_Transaction__c]);
    }

    @IsTest
    static void stripeInvalidJson_returnsBadRequest() {
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/stripe',
            'not-json'
        );
        RestContext.request.addHeader('Stripe-Signature', buildStripeSignatureHeader('not-json'));
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals(false, response.recordCreated);
    }

    @IsTest
    static void stripeInvalidSignatureHeader_returnsUnauthorized() {
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/stripe',
            '{"type":"payment_intent.succeeded"}'
        );
        RestContext.request.addHeader('Stripe-Signature', 'v1=missing_timestamp');
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals(false, response.recordCreated);
    }

    @IsTest
    static void stripeMissingSignature_returnsUnauthorized() {
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/stripe',
            '{"id":"evt_error","type":"payment_intent.succeeded"}'
        );
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals(false, response.recordCreated);
    }

    @IsTest
    static void invalidAuthorizeNetSignature_returnsUnauthorized() {
        String payload = '{"notificationId":"987","eventType":"net.authorize.payment.authcapture.created"}';
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/authorizenet',
            payload
        );
        RestContext.request.addHeader('X-ANET-SIGNATURE', 'sha512=BAD_SIGNATURE');
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals(false, response.recordCreated);
        System.assertEquals(0, [SELECT COUNT() FROM Portal_Payment_Transaction__c]);
    }

    @IsTest
    static void missingAuthorizeNetSignature_returnsUnauthorized() {
        String payload = '{"notificationId":"988","eventType":"net.authorize.payment.authcapture.created"}';
        RestContext.request = buildRequest(
            '/services/apexrest/payment-webhook/authorizenet',
            payload
        );
        RestContext.response = new RestResponse();

        Test.startTest();
        PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals(false, response.recordCreated);
        System.assertEquals(0, [SELECT COUNT() FROM Portal_Payment_Transaction__c]);
    }

    private static RestRequest buildRequest(String requestUri, String body) {
        RestRequest request = new RestRequest();
        request.requestURI = requestUri;
        request.httpMethod = 'POST';
        request.addHeader('Content-Type', 'application/json');
        request.requestBody = Blob.valueOf(body);
        return request;
    }

    private static String buildStripeSignatureHeader(String payload) {
        String timestamp = String.valueOf(Datetime.now().getTime() / 1000);
        String signedPayload = timestamp + '.' + payload;
        
        // Force test secret regardless of org data
        String signingSecret = PaymentWebhookRestResource.TEST_STRIPE_WEBHOOK_SIGNING_SECRET;
        
        String signature = EncodingUtil.convertToHex(
            Crypto.generateMac(
                'HmacSHA256',
                Blob.valueOf(signedPayload),
                Blob.valueOf(signingSecret)
            )
        ).toLowerCase();
        return 't=' + timestamp + ',v1=' + signature;
    }

    private static String buildAuthorizeNetSignatureHeader(String payload) {
        return 'sha512=' + buildAuthorizeNetSignatureDigest(payload);
    }

    private static String buildAuthorizeNetSignatureDigest(String payload) {
        String signingKey = PaymentWebhookRestResource.TEST_AUTHORIZE_NET_WEBHOOK_SIGNING_KEY;
        
        return EncodingUtil.convertToHex(
            Crypto.generateMac(
                'HmacSHA512',
                Blob.valueOf(payload),
                EncodingUtil.convertFromHex(signingKey)
            )
        ).toUpperCase();
    }

    private static Order createOrderRecord() {
        Account account = new Account(Name = 'Webhook Order Account');
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
}