@IsTest
private class InvoiceQRServiceTest {

    static void disableTriggersForTest() {
        QuickBooksInvoiceHandler.isProcessing = true;
        QBTriggerHandler.isOrderProcessing = true;
        QBInvoiceToOrderSyncBatch.isProcessing = true;
    }

    @testSetup
    static void setupTestData() {
        disableTriggersForTest();

        Account acc = new Account(Name = 'Test Enterprise Client');
        insert acc;

        Product2 prod = new Product2(Name = 'Consulting Services', IsActive = true);
        insert prod;

        Id standardPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId, 
            Product2Id = prod.Id, 
            UnitPrice = 500.00, 
            IsActive = true
        );
        insert pbe;

        Order orderStripe = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Payment_Gateway__c = 'Stripe', Pricebook2Id = standardPricebookId);
        Order orderPayPal = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Payment_Gateway__c = 'PayPal', Pricebook2Id = standardPricebookId);
        Order orderAuthNet = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Payment_Gateway__c = 'Authorize.Net', Pricebook2Id = standardPricebookId);
        Order orderInvalid = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Payment_Gateway__c = 'Bitcoin', Pricebook2Id = standardPricebookId);
        Order orderNoAmount = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Payment_Gateway__c = 'Stripe', Pricebook2Id = standardPricebookId);
        
        insert new List<Order>{ orderStripe, orderPayPal, orderAuthNet, orderInvalid, orderNoAmount };

        List<OrderItem> orderItems = new List<OrderItem>();
        for (Order ord : new List<Order>{ orderStripe, orderPayPal, orderAuthNet, orderInvalid }) {
            orderItems.add(new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 500.00));
        }
        insert orderItems;

        Invoice__c invStripe = new Invoice__c(Order__c = orderStripe.Id);
        Invoice__c invPayPal = new Invoice__c(Order__c = orderPayPal.Id);
        Invoice__c invAuthNet = new Invoice__c(Order__c = orderAuthNet.Id);
        Invoice__c invInvalid = new Invoice__c(Order__c = orderInvalid.Id);
        Invoice__c invNoAmount = new Invoice__c(Order__c = orderNoAmount.Id);
        Invoice__c invNoOrder = new Invoice__c(); 
        
        insert new List<Invoice__c>{ invStripe, invPayPal, invAuthNet, invInvalid, invNoAmount, invNoOrder };

        Portal_Payment_Transaction__c transPayPal = new Portal_Payment_Transaction__c(
            Order__c = orderPayPal.Id, 
            Gateway_Transaction_Id__c = 'INV2-TEST-PAYPAL-1234', 
            Gateway_Currency__c = 'USD',
            Payment_Type__c = 'PayPal'
        );
        insert transPayPal;
    }

    private class QRServiceCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint().toLowerCase();

            if (endpoint.contains('stripe')) {
                res.setBody('{"id": "cs_test_123", "url": "https://checkout.stripe.com/pay/test_123"}');
            } else if (endpoint.contains('paypal')) {
                res.setBody('{"image": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="}'); 
            } else if (endpoint.contains('authorizenet')) {
                res.setBody('{"messages": {"resultCode": "Ok"}, "token": "test_authnet_token_xyz"}');
            } else {
                res.setStatusCode(400); 
                res.setBody('{"error": "Unknown Endpoint"}');
            }
            return res;
        }
    }

    // ========== Existing passing tests (unchanged except fix for error log) ==========
    @IsTest
    static void testStripeQRGenerationSuccess() {
        disableTriggersForTest(); 
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__r.Payment_Gateway__c = 'Stripe' AND Order__r.TotalAmount > 0 LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new QRServiceCalloutMock());

        Test.startTest();
        InvoiceQRService.QRWrapper result = InvoiceQRService.generateAndSaveQRCode(inv.Id);
        Test.stopTest();

        System.assert(result.isSuccess, 'QR Code generation should be successful for Stripe.');
        System.assert(result.qrImageUrl.contains('quickchart.io'), 'Stripe QR should route through QuickChart API.');
        
        Invoice__c updatedInv = [SELECT Payment_QR_Code__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assert(updatedInv.Payment_QR_Code__c.contains('<img src='), 'Invoice Payment_QR_Code__c field should contain HTML image tag.');
    }

    @IsTest
    static void testPayPalQRGenerationSuccess() {
        disableTriggersForTest();
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__r.Payment_Gateway__c = 'PayPal' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new QRServiceCalloutMock());

        Test.startTest();
        InvoiceQRService.QRWrapper result = InvoiceQRService.generateAndSaveQRCode(inv.Id);
        Test.stopTest();

        System.assert(result.isSuccess, 'QR Code generation should be successful for PayPal.');
        System.assert(result.qrImageUrl.startsWith('data:image/png;base64,'), 'PayPal QR should return a Base64 image string.');
    }

    @IsTest
    static void testAuthorizeNetQRGenerationSuccess() {
        disableTriggersForTest();
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__r.Payment_Gateway__c = 'Authorize.Net' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new QRServiceCalloutMock());

        Test.startTest();
        InvoiceQRService.QRWrapper result = InvoiceQRService.generateAndSaveQRCode(inv.Id);
        Test.stopTest();

        System.assert(result.isSuccess, 'QR Code generation should be successful for Authorize.Net.');
        System.assert(result.qrImageUrl.contains('qrserver.com'), 'Authorize.Net QR should route through QRServer API.');
    }

    @IsTest
    static void testMissingOrderContext() {
        disableTriggersForTest();
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__c = null LIMIT 1];

        Test.startTest();
        try {
            InvoiceQRService.generateAndSaveQRCode(inv.Id);
            System.assert(false, 'Expected AuraHandledException due to missing Order association.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not linked to an Order'), 'Expected specific error message regarding missing Order.');
        }
        Test.stopTest();

        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log__c
            WHERE Source_Record_Id__c = :inv.Id
            AND Class_Method_Name__c = 'InvoiceQRService.generateAndSaveQRCode'
        ]);
    }

    @IsTest
    static void testInvalidTotalAmount() {
        disableTriggersForTest();
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__r.TotalAmount = null OR Order__r.TotalAmount = 0 LIMIT 1];

        Test.startTest();
        try {
            InvoiceQRService.generateAndSaveQRCode(inv.Id);
            System.assert(false, 'Expected AuraHandledException due to 0 or null Total Amount.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Amount is missing or invalid'), 'Expected specific error message regarding invalid amount.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUnsupportedPaymentGateway() {
        disableTriggersForTest();
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__r.Payment_Gateway__c = 'Bitcoin' LIMIT 1];

        Test.startTest();
        try {
            InvoiceQRService.generateAndSaveQRCode(inv.Id);
            System.assert(false, 'Expected AuraHandledException due to unsupported gateway.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Unsupported Payment Gateway'), 'Expected specific error message regarding unsupported gateway.');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testPayPalMissingTransactionContext() {
        disableTriggersForTest();
        Order newOrder = new Order(AccountId = [SELECT Id FROM Account LIMIT 1].Id, Status = 'Draft', EffectiveDate = Date.today(), Payment_Gateway__c = 'PayPal', Pricebook2Id = Test.getStandardPricebookId());
        insert newOrder;
        
        OrderItem oi = new OrderItem(OrderId = newOrder.Id, PricebookEntryId = [SELECT Id FROM PricebookEntry LIMIT 1].Id, Quantity = 1, UnitPrice = 100.00);
        insert oi;
        
        Invoice__c newInv = new Invoice__c(Order__c = newOrder.Id);
        insert newInv;

        Test.startTest();
        try {
            InvoiceQRService.generateAndSaveQRCode(newInv.Id);
            System.assert(false, 'Expected AuraHandledException due to missing PayPal transaction.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('No PayPal Invoice ID found'), 'Expected specific error message regarding missing PayPal transaction.');
        }
        Test.stopTest();
    }


    @IsTest
    static void testBuildQRCodeImageUrl_Success() {
        String paymentUrl = 'https://example.com/pay/123';
        Test.startTest();
        String result = InvoiceQRService.buildQRCodeImageUrl(paymentUrl);
        Test.stopTest();
        System.assert(result.startsWith('https://quickchart.io/qr?text='), 'QR URL should be generated using quickchart.io');
        System.assert(result.contains(EncodingUtil.urlEncode(paymentUrl, 'UTF-8')), 'Payment URL should be URL-encoded');
    }

    @IsTest
    static void testBuildQRCodeImageUrl_BlankUrl_ThrowsException() {
        Test.startTest();
        try {
            InvoiceQRService.buildQRCodeImageUrl('');
            System.assert(false, 'Exception expected for blank URL');
        } catch (InvoiceQRService.CustomQRException e) {
            System.assert(e.getMessage().contains('Payment URL is required'), 'Correct exception message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveQRCodeFileForUrl_Success() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String paymentUrl = 'https://example.com/pay/456';
        String title = 'Test QR File';
        Test.startTest();
        Id contentDocId = InvoiceQRService.saveQRCodeFileForUrl(acc.Id, paymentUrl, title);
        Test.stopTest();
        System.assertNotEquals(null, contentDocId, 'ContentDocument Id should be returned');
        ContentDocumentLink link = [SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :contentDocId LIMIT 1];
        System.assertEquals(acc.Id, link.LinkedEntityId, 'Should be linked to the parent record');
    }

    @IsTest
    static void testSaveQRCodeFileForUrl_NullParentId_ThrowsException() {
        String paymentUrl = 'https://example.com/pay';
        Test.startTest();
        try {
            InvoiceQRService.saveQRCodeFileForUrl(null, paymentUrl, null);
            System.assert(false, 'Exception expected for null parent Id');
        } catch (InvoiceQRService.CustomQRException e) {
            System.assert(e.getMessage().contains('parent record is required'), 'Correct exception message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveQRCodeFileForUrl_NullTitle_UsesDefault() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String paymentUrl = 'https://example.com/pay';
        Test.startTest();
        Id contentDocId = InvoiceQRService.saveQRCodeFileForUrl(acc.Id, paymentUrl, null);
        Test.stopTest();
        ContentVersion cv = [SELECT Title FROM ContentVersion WHERE ContentDocumentId = :contentDocId LIMIT 1];
        System.assertEquals('Payment QR Code', cv.Title, 'Should use default title when null provided');
    }
}