@IsTest
private class InvoiceDisputeServiceTest {

    /**
     * @description Sets up the initial test data required for all test methods.
     * This runs once before any test method executes.
     */
    @testSetup
    static void setupTestData() {
        // Create a dummy Account
        Account acc = new Account(Name = 'Test Dispute Account');
        insert acc;

        // Create Orders with different Payment Gateways
        Order orderStripe = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', Payment_Gateway__c = 'Stripe');
        Order orderPayPal = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', Payment_Gateway__c = 'PayPal');
        Order orderAuthNet = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', Payment_Gateway__c = 'Authorize.Net');
        Order orderInvalid = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', Payment_Gateway__c = 'Cash');
        insert new List<Order>{ orderStripe, orderPayPal, orderAuthNet, orderInvalid };

        // Create Invoices linked to the Orders
        Invoice__c invStripe = new Invoice__c(Order__c = orderStripe.Id);
        Invoice__c invPayPal = new Invoice__c(Order__c = orderPayPal.Id);
        Invoice__c invAuthNet = new Invoice__c(Order__c = orderAuthNet.Id);
        Invoice__c invInvalid = new Invoice__c(Order__c = orderInvalid.Id);
        Invoice__c invNoOrder = new Invoice__c(); // Invoice without an Order
        insert new List<Invoice__c>{ invStripe, invPayPal, invAuthNet, invInvalid, invNoOrder };

        // Create Portal Payment Transactions linked to the Orders
        Portal_Payment_Transaction__c transStripe = new Portal_Payment_Transaction__c(
            Order__c = orderStripe.Id, 
            Stripe_Charge_Id__c = 'ch_test_stripe_123', 
            Gateway_Currency__c = 'USD',
            Payment_Type__c = 'Stripe'
        );
        Portal_Payment_Transaction__c transPayPal = new Portal_Payment_Transaction__c(
            Order__c = orderPayPal.Id, 
            Gateway_Transaction_Id__c = 'txn_test_paypal_123', 
            Gateway_Currency__c = 'USD',
            Payment_Type__c = 'PayPal'
        );
        Portal_Payment_Transaction__c transAuthNet = new Portal_Payment_Transaction__c(
            Order__c = orderAuthNet.Id, 
            Gateway_Transaction_Id__c = 'txn_test_authnet_123', 
            Gateway_Currency__c = 'USD',
            Payment_Type__c = 'Authorize.Net'
        );
        insert new List<Portal_Payment_Transaction__c>{ transStripe, transPayPal, transAuthNet };
    }

    /**
     * @description Mock Callout class to simulate HTTP responses from different payment gateways.
     */
    private class GatewayCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            // Simulate Stripe API Response
            if (endpoint.contains('stripe.com') || endpoint.contains('Stripe_API')) {
                res.setBody('{"data": [{"status": "needs_response", "reason": "fraudulent", "amount": 5000}]}');
            } 
            // Simulate PayPal API Response
            else if (endpoint.contains('paypal') || endpoint.contains('PayPal_API')) {
                res.setBody('{"items": [{"status": "UNDER_REVIEW", "dispute_reason": "MERCHANDISE_OR_SERVICE_NOT_AS_DESCRIBED", "dispute_amount": {"value": "50.00"}}]}');
            } 
            // Simulate Authorize.Net API Response
            else if (endpoint.contains('AuthorizeNet')) {
                res.setBody('{"transaction": {"transactionStatus": "chargeback", "settleAmount": 50.00}}');
            } 
            else {
                res.setStatusCode(400); // Bad Request for unknown endpoints
            }
            return res;
        }
    }

    /**
     * @description Tests the successful retrieval of a Stripe dispute.
     */
    @IsTest
    static void testStripeDisputeSuccess() {
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__r.Payment_Gateway__c = 'Stripe' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new GatewayCalloutMock());

        Test.startTest();
        InvoiceDisputeService.DisputeWrapper result = InvoiceDisputeService.getDisputeDetails(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.hasDispute, 'Dispute should be found for Stripe');
        System.assertEquals('needs_response', result.status, 'Status should match mock response');
        System.assertEquals('50', result.amount, 'Amount should be converted from cents (5000 / 100)');
    }

    /**
     * @description Tests the retrieval of a PayPal dispute.
     */
    @IsTest
    static void testPayPalDispute() {
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__r.Payment_Gateway__c = 'PayPal' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new GatewayCalloutMock());

        Test.startTest();
        InvoiceDisputeService.DisputeWrapper result = InvoiceDisputeService.getDisputeDetails(inv.Id);
        Test.stopTest();
        
        System.assertEquals(true, result.hasDispute, 'Dispute should be found for PayPal');
    }

    /**
     * @description Tests the retrieval of an Authorize.Net dispute.
     */
    @IsTest
    static void testAuthNetDispute() {
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__r.Payment_Gateway__c = 'Authorize.Net' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new GatewayCalloutMock());

        Test.startTest();
        InvoiceDisputeService.DisputeWrapper result = InvoiceDisputeService.getDisputeDetails(inv.Id);
        Test.stopTest();
        
        System.assertEquals(true, result.hasDispute, 'Dispute should be found for AuthNet');
        System.assertEquals('chargeback', result.status, 'Status should be chargeback');
    }

    /**
     * @description Tests the scenario where an Invoice is not linked to an Order.
     */
    @IsTest
    static void testInvoiceWithoutOrder() {
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__c = null LIMIT 1];

        Test.startTest();
        try {
            InvoiceDisputeService.getDisputeDetails(inv.Id);
            System.assert(false, 'Exception should have been thrown for missing Order.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not linked to any Order'), 'Correct error message should be returned.');
        }
        Test.stopTest();

        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log__c
            WHERE Invoice__c = :inv.Id
            AND Class_Method_Name__c = 'InvoiceDisputeService.getDisputeDetails'
        ]);
    }

    /**
     * @description Tests the scenario where an Order exists but has no Payment Transaction.
     */
    @IsTest
    static void testMissingTransaction() {
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__r.Payment_Gateway__c = 'Cash' LIMIT 1];

        Test.startTest();
        try {
            InvoiceDisputeService.getDisputeDetails(inv.Id);
            System.assert(false, 'Exception should have been thrown for missing Transaction.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('No Payment Transaction found'), 'Correct error message should be returned.');
        }
        Test.stopTest();
    }

    /**
     * @description Tests an unsupported payment gateway scenario.
     */
    @IsTest
    static void testUnsupportedGateway() {
        Order unsupportedOrder = [SELECT Id FROM Order WHERE Payment_Gateway__c = 'Cash' LIMIT 1];
        Portal_Payment_Transaction__c trans = new Portal_Payment_Transaction__c(
            Order__c = unsupportedOrder.Id, 
            Gateway_Transaction_Id__c = 'txn_fake',
            Payment_Type__c = 'Cash' 
        );
        insert trans;

        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Order__c = :unsupportedOrder.Id LIMIT 1];

        Test.startTest();
        try {
            InvoiceDisputeService.getDisputeDetails(inv.Id);
            System.assert(false, 'Exception should have been thrown for unsupported gateway.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Unsupported Payment Gateway'), 'Correct error message should be returned.');
        }
        Test.stopTest();
    }
}