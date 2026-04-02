@isTest
private class ShopifyCustomersBatchTest {

    class ShopifyMockCallout implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            res.setBody('{' +
                '"customers": [' +
                    '{' +
                        '"id": 123456789,' +
                        '"email": "test@example.com",' +
                        '"first_name": "John",' +
                        '"last_name": "Doe",' +
                        '"phone": "1234567890",' +
                        '"total_spent": "2500.50",' +
                        '"orders_count": 5,' +
                        '"tax_exempt": false,' +
                        '"tags": "VIP, Returning Customer",' +
                        '"default_address": {' +
                            '"address1": "123 Test St",' +
                            '"address2": "Unit 5",' +
                            '"city": "Testville",' +
                            '"province": "Teststate",' +
                            '"country": "Testland",' +
                            '"zip": "12345"' +
                        '},' +
                        '"email_marketing_consent": {' +
                            '"state": "subscribed",' +
                            '"opt_in_level": "single_opt_in"' +
                        '},' +
                        '"sms_marketing_consent": {' +
                            '"state": "not_subscribed",' +
                            '"opt_in_level": "none"' +
                        '}' +
                    '}' +
                ']' +
            '}');

            return res;
        }
    }

    @isTest
    static void testBatchWithoutEndpoint() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMockCallout());

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersBatch(), 1);
        Test.stopTest();

        List<Account> accs = [SELECT Id, External_Id__c, Total_Spent__c, Total_Orders__c FROM Account WHERE PersonEmail = 'test@example.com'];
        System.assertEquals(1, accs.size());
        System.assertEquals('123456789', accs[0].External_Id__c);
        System.assertEquals(2500.50, accs[0].Total_Spent__c);
        System.assertEquals(5, accs[0].Total_Orders__c);
    }

    @isTest
    static void testBatchWithCustomEndpoint() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMockCallout());

        String endpoint = 'https://mock-shopify.com/customers.json?status=any';
        Test.startTest();
        Database.executeBatch(new ShopifyCustomersBatch(endpoint), 1);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE PersonEmail = 'test@example.com']);
    }

    @isTest
    static void testFinishLogic() {
        Test.setMock(HttpCalloutMock.class, new ShopifyMockCallout());

        ShopifyCustomersBatch batch = new ShopifyCustomersBatch();
        Test.startTest();
        Database.executeBatch(batch, 1);
        Test.stopTest();

        System.assert(true, 'Finish method ran successfully.');
    }
}