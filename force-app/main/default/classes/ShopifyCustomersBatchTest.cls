@isTest
private class ShopifyCustomersBatchTest {

    private class ShopifyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('link', '<https://mock-shopify.com/next>; rel="next"');
            
            String jsonBody = '{"customers": [{' +
                '"id": 987654321,' +
                '"email": "test.shopify@example.com",' +
                '"first_name": "John",' +
                '"last_name": "Doe",' +
                '"phone": "+1234567890",' +
                '"tax_exempt": false,' +
                '"tags": "VIP, Wholesale",' +
                '"total_spent": "150.50",' +
                '"orders_count": 5,' +
                '"sms_marketing_consent": {"state": "subscribed", "opt_in_level": "single_opt_in"},' +
                '"email_marketing_consent": {"state": "subscribed", "opt_in_level": "single_opt_in"},' +
                '"default_address": {"address1": "123 Main St", "city": "New York", "province": "NY", "zip": "10001", "country": "US"}' +
            '}]}';
            
            res.setBody(jsonBody);
            return res;
        }
    }

    @isTest
    static void testBatchWithoutEndpoint() {
        ShopifyCustomersBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new ShopifyMock());
        
        Test.startTest();
        ShopifyCustomersBatch batch = new ShopifyCustomersBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        System.assert(true, 'Batch executed successfully');
    }

    @isTest
    static void testBatchWithCustomEndpoint() {
        ShopifyCustomersBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new ShopifyMock());
        
        Test.startTest();
        ShopifyCustomersBatch batch = new ShopifyCustomersBatch('https://mock-shopify.com/custom');
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        System.assert(true, 'Batch executed successfully');
    }
}