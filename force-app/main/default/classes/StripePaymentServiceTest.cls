@IsTest
private class StripePaymentServiceTest {
    private static Integer createCustomerThenPaymentIntentCallCount = 0;
    private static Integer existingCustomerPaymentIntentCallCount = 0;
    private static Integer orderReferenceCallCount = 0;
    private static Integer sendInvoiceExistingCustomerCallCount = 0;
    private static Integer sendInvoiceCreateCustomerCallCount = 0;
    private static String orderReferenceTestOrderId;
    private static String sendInvoiceExpectedOrderId;

    private static void assertAttachPaymentMethodRequest(HttpRequest request, String paymentMethodId, String customerId) {
        System.assertEquals('callout:Stripe_API/v1/payment_methods/' + paymentMethodId + '/attach', request.getEndpoint());
        System.assertEquals('customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8'), request.getBody());
    }

    private static void assertDefaultPaymentMethodRequest(HttpRequest request, String customerId, String paymentMethodId) {
        System.assertEquals('callout:Stripe_API/v1/customers/' + customerId, request.getEndpoint());
        System.assertEquals(
            'invoice_settings[default_payment_method]=' + EncodingUtil.urlEncode(paymentMethodId, 'UTF-8'),
            request.getBody()
        );
    }

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"id":"pi_123456789","object":"payment_intent","status":"succeeded","client_secret":"pi_123456789_secret_abc","latest_charge":"ch_123456789"}');
            return response;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(402);
            response.setBody('{"error":{"message":"Your card was declined."}}');
            return response;
        }
    }

    private class InvalidBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('not-json');
            return response;
        }
    }

    private class DefaultCurrencyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getBody().contains('currency=usd'));

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"id":"pi_currency_test","object":"payment_intent","status":"succeeded","latest_charge":"ch_currency_test"}');
            return response;
        }
    }

    private class OrderReferenceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            orderReferenceCallCount++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            if (orderReferenceCallCount == 1) {
                assertAttachPaymentMethodRequest(request, 'pm_card_visa', 'cus_order_reference_123');
                response.setBody('{"id":"pm_card_visa","object":"payment_method"}');
                return response;
            }

            if (orderReferenceCallCount == 2) {
                assertDefaultPaymentMethodRequest(request, 'cus_order_reference_123', 'pm_card_visa');
                response.setBody('{"id":"cus_order_reference_123","object":"customer"}');
                return response;
            }

            String encodedOrderId = EncodingUtil.urlEncode(orderReferenceTestOrderId, 'UTF-8');
            System.assertEquals('callout:Stripe_API/v1/payment_intents', request.getEndpoint());
            System.assert(request.getBody().contains('customer=cus_order_reference_123'));
            System.assert(request.getBody().contains('setup_future_usage=off_session'));
            System.assert(request.getBody().contains('metadata%5Border_id%5D=' + encodedOrderId));
            System.assert(request.getBody().contains('metadata%5Breference_number%5D=' + encodedOrderId));
            response.setBody('{"id":"pi_order_reference","object":"payment_intent","status":"succeeded","latest_charge":"ch_order_reference"}');
            return response;
        }
    }

    private class ExistingCustomerPaymentIntentMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            existingCustomerPaymentIntentCallCount++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            if (existingCustomerPaymentIntentCallCount == 1) {
                assertAttachPaymentMethodRequest(request, 'pm_card_visa', 'cus_existing_123');
                response.setBody('{"id":"pm_card_visa","object":"payment_method"}');
                return response;
            }

            if (existingCustomerPaymentIntentCallCount == 2) {
                assertDefaultPaymentMethodRequest(request, 'cus_existing_123', 'pm_card_visa');
                response.setBody('{"id":"cus_existing_123","object":"customer"}');
                return response;
            }

            System.assertEquals('callout:Stripe_API/v1/payment_intents', request.getEndpoint());
            System.assert(request.getBody().contains('customer=cus_existing_123'));
            System.assert(request.getBody().contains('setup_future_usage=off_session'));
            response.setBody('{"id":"pi_existing_customer","object":"payment_intent","status":"succeeded","latest_charge":"ch_existing_customer"}');
            return response;
        }
    }

    private class CreateCustomerThenPaymentIntentMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            createCustomerThenPaymentIntentCallCount++;

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            if (createCustomerThenPaymentIntentCallCount == 1) {
                System.assertEquals('callout:Stripe_API/v1/customers', request.getEndpoint());
                System.assert(request.getBody().contains('metadata%5Baccount_id%5D='));
                System.assert(request.getBody().contains('metadata%5Border_id%5D='));
                response.setBody('{"id":"cus_new_123","object":"customer"}');
                return response;
            }

            if (createCustomerThenPaymentIntentCallCount == 2) {
                assertAttachPaymentMethodRequest(request, 'pm_card_visa', 'cus_new_123');
                response.setBody('{"id":"pm_card_visa","object":"payment_method"}');
                return response;
            }

            if (createCustomerThenPaymentIntentCallCount == 3) {
                assertDefaultPaymentMethodRequest(request, 'cus_new_123', 'pm_card_visa');
                response.setBody('{"id":"cus_new_123","object":"customer"}');
                return response;
            }

            System.assertEquals('callout:Stripe_API/v1/payment_intents', request.getEndpoint());
            System.assert(request.getBody().contains('customer=cus_new_123'));
            System.assert(request.getBody().contains('setup_future_usage=off_session'));
            response.setBody('{"id":"pi_new_customer","object":"payment_intent","status":"succeeded","latest_charge":"ch_new_customer"}');
            return response;
        }
    }

    private class SendInvoiceExistingCustomerMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            sendInvoiceExistingCustomerCallCount++;

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            if (sendInvoiceExistingCustomerCallCount == 1) {
                System.assertEquals('callout:Stripe_API/v1/invoices', request.getEndpoint());
                System.assert(request.getBody().contains('customer=cus_existing_123'));
                System.assert(request.getBody().contains('collection_method=send_invoice'));
                if (String.isNotBlank(sendInvoiceExpectedOrderId)) {
                    String encodedOrderId = EncodingUtil.urlEncode(sendInvoiceExpectedOrderId, 'UTF-8');
                    System.assert(request.getBody().contains('metadata%5Border_id%5D=' + encodedOrderId));
                    System.assert(request.getBody().contains('metadata%5Breference_number%5D=' + encodedOrderId));
                }
                response.setBody('{"id":"in_existing_123","object":"invoice","status":"draft"}');
                return response;
            }

            if (sendInvoiceExistingCustomerCallCount == 2) {
                System.assertEquals('callout:Stripe_API/v1/invoiceitems', request.getEndpoint());
                System.assert(request.getBody().contains('customer=cus_existing_123'));
                System.assert(request.getBody().contains('invoice=in_existing_123'));
                System.assert(request.getBody().contains('amount=4250'));
                if (String.isNotBlank(sendInvoiceExpectedOrderId)) {
                    String encodedOrderId = EncodingUtil.urlEncode(sendInvoiceExpectedOrderId, 'UTF-8');
                    System.assert(request.getBody().contains('metadata%5Border_id%5D=' + encodedOrderId));
                    System.assert(request.getBody().contains('metadata%5Breference_number%5D=' + encodedOrderId));
                }
                response.setBody('{"id":"ii_existing_123","object":"invoiceitem"}');
                return response;
            }

            System.assertEquals('callout:Stripe_API/v1/invoices/in_existing_123/finalize', request.getEndpoint());
            response.setBody('{"id":"in_existing_123","object":"invoice","status":"open","hosted_invoice_url":"https://pay.stripe.com/invoice/existing"}');
            return response;
        }
    }

    private class SendInvoiceCreateCustomerMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            sendInvoiceCreateCustomerCallCount++;

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            if (sendInvoiceCreateCustomerCallCount == 1) {
                System.assertEquals('callout:Stripe_API/v1/customers', request.getEndpoint());
                System.assert(request.getBody().contains('metadata%5Baccount_id%5D='));
                response.setBody('{"id":"cus_invoice_new_123","object":"customer"}');
                return response;
            }

            if (sendInvoiceCreateCustomerCallCount == 2) {
                System.assertEquals('callout:Stripe_API/v1/invoices', request.getEndpoint());
                System.assert(request.getBody().contains('customer=cus_invoice_new_123'));
                response.setBody('{"id":"in_created_123","object":"invoice","status":"draft"}');
                return response;
            }

            if (sendInvoiceCreateCustomerCallCount == 3) {
                System.assertEquals('callout:Stripe_API/v1/invoiceitems', request.getEndpoint());
                System.assert(request.getBody().contains('customer=cus_invoice_new_123'));
                System.assert(request.getBody().contains('invoice=in_created_123'));
                System.assert(request.getBody().contains('amount=5525'));
                response.setBody('{"id":"ii_created_123","object":"invoiceitem"}');
                return response;
            }

            System.assertEquals('callout:Stripe_API/v1/invoices/in_created_123/finalize', request.getEndpoint());
            response.setBody('{"id":"in_created_123","object":"invoice","status":"open","hosted_invoice_url":"https://pay.stripe.com/invoice/new"}');
            return response;
        }
    }

    private static Account createInvoiceActionAccount(String emailAddress, String stripeCustomerId) {
        List<RecordType> personAccountRecordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ];

        Account accountRecord;
        if (!personAccountRecordTypes.isEmpty()) {
            accountRecord = new Account(
                RecordTypeId = personAccountRecordTypes[0].Id,
                LastName = 'Stripe Invoice Customer'
            );
            accountRecord.PersonEmail = emailAddress;
        } else {
            accountRecord = new Account(Name = 'Stripe Invoice Customer');
            Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
            if (accountFields.containsKey('Email__c')) {
                accountRecord.put('Email__c', emailAddress);
            } else if (accountFields.containsKey('PrimaryEmailAddr__c')) {
                accountRecord.put('PrimaryEmailAddr__c', emailAddress);
            }
        }

        if (String.isNotBlank(stripeCustomerId)) {
            accountRecord.Stripe_Customer_Id__c = stripeCustomerId;
        }

        insert accountRecord;
        return accountRecord;
    }

    private static Order createInvoiceActionOrder(Id accountId) {
        Order orderRecord = new Order(
            AccountId = accountId,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert orderRecord;
        return orderRecord;
    }

    private static Invoice__c createInvoiceForInvoiceAction(
        Id accountId,
        Decimal amount,
        String emailAddress,
        Id orderId,
        String referenceNumber
    ) {
        Invoice__c invoiceRecord = new Invoice__c(Related_Account__c = accountId);
        invoiceRecord.put('Amount__c', amount);
        invoiceRecord.put('Email__c', emailAddress);
        if (orderId != null) {
            invoiceRecord.put('Order__c', orderId);
        }
        if (referenceNumber != null) {
            invoiceRecord.put('Reference_number__c', referenceNumber);
        }
        if (Schema.SObjectType.Invoice__c.fields.getMap().containsKey('Invoice_Date__c')) {
            invoiceRecord.put('Invoice_Date__c', Date.today());
        }
        if (Schema.SObjectType.Invoice__c.fields.getMap().containsKey('Due_Date__c')) {
            invoiceRecord.put('Due_Date__c', Date.today().addDays(10));
        }
        insert invoiceRecord;
        return invoiceRecord;
    }

    @IsTest
    static void getClientConfig_returnsResponse() {
        Test.startTest();
        StripePaymentService.ClientConfigResponse response = StripePaymentService.getClientConfig();
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertNotEquals(null, response.message);
        System.assertEquals('https://js.stripe.com/v3/', response.stripeJsUrl);
    }

    @IsTest
    static void processPayment_success() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 25.00;
        request.paymentMethodId = 'pm_card_visa';
        request.fullName = 'Test User';
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('Transaction Successful', response.message);
        System.assertEquals('pi_123456789', response.transId);
        System.assertEquals('Ok', response.resultCode);
    }

    @IsTest
    static void processPayment_succeedsWithPendingWork() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        insert new Account(Name = 'Pending Stripe Callout Work');

        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 25.00;
        request.paymentMethodId = 'pm_card_visa';
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('pi_123456789', response.transId);
    }

    @IsTest
    static void processPayment_error() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 25.00;
        request.paymentMethodId = 'pm_card_chargeDeclined';
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('Your card was declined.', response.message);
    }

    @IsTest
    static void processPayment_succeedsWithoutSessionTokenForInternalAction() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 25.00;
        request.paymentMethodId = 'pm_card_visa';
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('pi_123456789', response.transId);
    }

    @IsTest
    static void processPayment_defaultsCurrencyCode() {
        Test.setMock(HttpCalloutMock.class, new DefaultCurrencyMock());

        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 10.00;
        request.paymentMethodId = 'pm_card_visa';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('pi_currency_test', response.transId);
    }

    @IsTest
    static void processPayment_allowsPlatformSessionForInternalAction() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 25.00;
        request.allowPlatformSession = true;
        request.paymentMethodId = 'pm_card_visa';
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('pi_123456789', response.transId);
    }

    @IsTest
    static void processPayment_includesOrderReferenceMetadata() {
        Account account = new Account(
            Name = 'Order Reference Stripe Account',
            Stripe_Customer_Id__c = 'cus_order_reference_123'
        );
        insert account;

        Order orderRecord = new Order(
            AccountId = account.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert orderRecord;
        orderReferenceTestOrderId = orderRecord.Id;
        orderReferenceCallCount = 0;

        Test.setMock(HttpCalloutMock.class, new OrderReferenceMock());

        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 10.00;
        request.orderId = orderRecord.Id;
        request.paymentMethodId = 'pm_card_visa';
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('pi_order_reference', response.transId);
    }

    @IsTest
    static void processPayment_reusesExistingStripeCustomerId() {
        Account account = new Account(
            Name = 'Existing Stripe Customer Account',
            Stripe_Customer_Id__c = 'cus_existing_123'
        );
        insert account;

        Order orderRecord = new Order(
            AccountId = account.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert orderRecord;

        existingCustomerPaymentIntentCallCount = 0;

        Test.setMock(HttpCalloutMock.class, new ExistingCustomerPaymentIntentMock());

        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 25.00;
        request.orderId = orderRecord.Id;
        request.paymentMethodId = 'pm_card_visa';
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('pi_existing_customer', response.transId);

        Account updatedAccount = [
            SELECT Stripe_Customer_Id__c
            FROM Account
            WHERE Id = :account.Id
        ];
        System.assertEquals('cus_existing_123', updatedAccount.Stripe_Customer_Id__c);
    }

    @IsTest
    static void processPayment_createsStripeCustomerWhenMissing() {
        Account account = new Account(Name = 'New Stripe Customer Account');
        insert account;

        Order orderRecord = new Order(
            AccountId = account.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert orderRecord;

        createCustomerThenPaymentIntentCallCount = 0;
        Test.setMock(HttpCalloutMock.class, new CreateCustomerThenPaymentIntentMock());

        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 25.00;
        request.orderId = orderRecord.Id;
        request.paymentMethodId = 'pm_card_visa';
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('pi_new_customer', response.transId);

        Account updatedAccount = [
            SELECT Stripe_Customer_Id__c
            FROM Account
            WHERE Id = :account.Id
        ];
        System.assertEquals('cus_new_123', updatedAccount.Stripe_Customer_Id__c);
    }

    @IsTest
    static void processPayment_invalidResponseBody() {
        Test.setMock(HttpCalloutMock.class, new InvalidBodyMock());

        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 25.00;
        request.paymentMethodId = 'pm_card_visa';
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('Stripe returned an invalid response.', response.message);
    }

    @IsTest
    static void processPayment_missingPaymentMethod() {
        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.amount = 25.00;
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertNotEquals(null, response.message);
    }

    @IsTest
    static void processPayment_missingAmount() {
        StripePaymentService.PaymentRequest request = new StripePaymentService.PaymentRequest();
        request.paymentMethodId = 'pm_card_visa';
        request.currencyCode = 'usd';

        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(request);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertNotEquals(null, response.message);
    }

    @IsTest
    static void processPayment_missingRequest() {
        Test.startTest();
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(null);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assert(
            response.message.contains('Script-thrown exception') ||
            response.message.contains('Missing payment request.')
        );
    }

    @IsTest
    static void sendInvoiceToCustomer_reusesExistingStripeCustomerId() {
        Account account = createInvoiceActionAccount(null, 'cus_existing_123');
        Order orderRecord = createInvoiceActionOrder(account.Id);
        Invoice__c invoiceRecord = createInvoiceForInvoiceAction(
            account.Id,
            42.50,
            'existing.invoice@example.com',
            orderRecord.Id,
            null
        );

        sendInvoiceExistingCustomerCallCount = 0;
        sendInvoiceExpectedOrderId = orderRecord.Id;
        Test.setMock(HttpCalloutMock.class, new SendInvoiceExistingCustomerMock());

        Test.startTest();
        StripePaymentService.InvoiceDeliveryResponse response = StripePaymentService.sendInvoiceToCustomer(invoiceRecord.Id);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('https://pay.stripe.com/invoice/existing', response.hostedInvoiceUrl);
        System.assertEquals('cus_existing_123', response.stripeCustomerId);
        System.assert(response.message.contains('existing.invoice@example.com'));

        Invoice__c updatedInvoice = [
            SELECT Stripe_Invoice_Link__c
            FROM Invoice__c
            WHERE Id = :invoiceRecord.Id
        ];
        System.assertEquals('https://pay.stripe.com/invoice/existing', (String) updatedInvoice.get('Stripe_Invoice_Link__c'));
    }

    @IsTest
    static void sendInvoiceToCustomer_createsStripeCustomerWhenMissing() {
        Account account = createInvoiceActionAccount(null, null);
        Invoice__c invoiceRecord = createInvoiceForInvoiceAction(account.Id, 55.25, 'new.invoice@example.com', null, null);

        sendInvoiceCreateCustomerCallCount = 0;
        sendInvoiceExpectedOrderId = null;
        Test.setMock(HttpCalloutMock.class, new SendInvoiceCreateCustomerMock());

        Test.startTest();
        StripePaymentService.InvoiceDeliveryResponse response = StripePaymentService.sendInvoiceToCustomer(invoiceRecord.Id);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('https://pay.stripe.com/invoice/new', response.hostedInvoiceUrl);
        System.assertEquals('cus_invoice_new_123', response.stripeCustomerId);

        Account updatedAccount = [
            SELECT Stripe_Customer_Id__c
            FROM Account
            WHERE Id = :account.Id
        ];
        System.assertEquals('cus_invoice_new_123', updatedAccount.Stripe_Customer_Id__c);
    }

    @IsTest
    static void sendInvoiceToCustomer_requiresInvoiceEmail() {
        Account account = createInvoiceActionAccount('account.only@example.com', 'cus_existing_123');
        Invoice__c invoiceRecord = createInvoiceForInvoiceAction(account.Id, 12.00, null, null, null);

        Test.startTest();
        StripePaymentService.InvoiceDeliveryResponse response = StripePaymentService.sendInvoiceToCustomer(invoiceRecord.Id);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assert(
            response.message == 'The invoice does not have an email address.' ||
            response.message == 'Script-thrown exception'
        );
    }
}