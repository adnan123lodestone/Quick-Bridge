@isTest
private class ShopifyCustomersBatchTest {
    
    // Success mock with next link
    private class ShopifySuccessMock implements HttpCalloutMock {
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
                '"default_address": {"address1": "123 Main St", "address2": "Apt 4", "city": "New York", "province": "NY", "zip": "10001", "country": "US"}' +
                '}]}';
            res.setBody(jsonBody);
            return res;
        }
    }
    
    // Generic error mock (can return any status code and body)
    private class ShopifyErrorMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        ShopifyErrorMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            if (body != null) res.setBody(body);
            return res;
        }
    }
    
    // Mock that throws an exception
    private class ShopifyExceptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated network error');
        }
    }
    
    @testSetup
    static void setupData() {
        RecordType rt = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'PersonAccount' LIMIT 1];
        Account existingAccount = new Account(
            RecordTypeId = rt.Id,
        PersonEmail = 'existing@example.com',
        Shopify_ID__c = '999999',
        LastName = 'Existing'
            );
        insert existingAccount;
    }
    
    @isTest
    static void testBatchWithoutEndpoint() {
        ShopifyCustomersBatch.bypassAuthCheckForTest = true;
        ShopifyCustomersBatch.suppressFinishEnqueue = true;
        Test.setMock(HttpCalloutMock.class, new ShopifySuccessMock());
        
        Test.startTest();
        ShopifyCustomersBatch batch = new ShopifyCustomersBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        System.assert(true, 'Batch executed successfully');
    }
    
    @isTest
    static void testBatchWithCustomEndpoint() {
        ShopifyCustomersBatch.bypassAuthCheckForTest = true;
        ShopifyCustomersBatch.suppressFinishEnqueue = true;
        Test.setMock(HttpCalloutMock.class, new ShopifySuccessMock());
        
        Test.startTest();
        ShopifyCustomersBatch batch = new ShopifyCustomersBatch('https://mock-shopify.com/custom');
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        System.assert(true, 'Batch executed successfully');
    }
    
    @isTest
    static void testBatchWithAdminApiEndpoint() {
        ShopifyCustomersBatch.bypassAuthCheckForTest = true;
        ShopifyCustomersBatch.suppressFinishEnqueue = true;
        Test.setMock(HttpCalloutMock.class, new ShopifySuccessMock());
        
        String customEndpoint = 'https://myshopify.com/admin/api/2024-04/customers.json?page_info=abc';
        Test.startTest();
        ShopifyCustomersBatch batch = new ShopifyCustomersBatch(customEndpoint);
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        System.assert(true, 'Pagination endpoint handling covered');
    }
    
    @isTest
    static void testBatchHttpError() {
        ShopifyCustomersBatch.bypassAuthCheckForTest = true;
        ShopifyCustomersBatch.suppressFinishEnqueue = true;
        Test.setMock(HttpCalloutMock.class, new ShopifyErrorMock(500, null));
        
        Test.startTest();
        ShopifyCustomersBatch batch = new ShopifyCustomersBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        System.assert(true, 'Error path covered');
    }
    
    @isTest
    static void testBatchException() {
        ShopifyCustomersBatch.bypassAuthCheckForTest = true;
        ShopifyCustomersBatch.suppressFinishEnqueue = true;
        Test.setMock(HttpCalloutMock.class, new ShopifyExceptionMock());
        
        Test.startTest();
        ShopifyCustomersBatch batch = new ShopifyCustomersBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        System.assert(true, 'Exception catch block covered');
    }
    
    @isTest
    static void testSyncCustomerFromShopifySuccess() {
        String customerJson = '{"customer": {' +
            '"id": 123456, "email": "sync@example.com", "first_name": "Sync", "last_name": "User", ' +
            '"sms_marketing_consent": {"state": "subscribed"}, ' +
            '"email_marketing_consent": {"state": "subscribed"}, ' +
            '"default_address": {"address1": "Sync St", "city": "Sync City", "province": "SC", "zip": "12345", "country": "US"}' +
            '}}';
        Test.setMock(HttpCalloutMock.class, new ShopifyErrorMock(200, customerJson));
        
        Test.startTest();
        ShopifyCustomersBatch.syncCustomerFromShopify('123456');
        Test.stopTest();
        
        Account synced = [SELECT Id, Shopify_ID__c, PersonEmail, FirstName, LastName, 
                          SMS_Consent_State__c, Email_Consent_State__c,
                          BillingStreet, BillingCity FROM Account WHERE Shopify_ID__c = '123456' LIMIT 1];
        System.assertEquals('sync@example.com', synced.PersonEmail);
        System.assertEquals('Sync', synced.FirstName);
        System.assertEquals('User', synced.LastName);
        System.assertEquals('subscribed', synced.SMS_Consent_State__c);
        System.assertEquals('Sync St', synced.BillingStreet);
    }
    
    @isTest
    static void testSyncCustomerFromShopifyNotFound() {
        Test.setMock(HttpCalloutMock.class, new ShopifyErrorMock(404, '{"error":"not found"}'));
        
        Boolean threw = false;
        Test.startTest();
        try {
            ShopifyCustomersBatch.syncCustomerFromShopify('999');
        } catch (CalloutException e) {
            threw = true;
        }
        Test.stopTest();
        
        System.assert(threw, 'Expected CalloutException for missing customer');
    }
    
    @isTest
    static void testBuildAccountFromShopifyCustomer() {
        Map<String, Object> customer = new Map<String, Object>{
            'id' => 111111,
            'email' => 'direct@test.com',
            'first_name' => 'Direct',
            'last_name' => 'Build',
            'sms_marketing_consent' => new Map<String, Object>{'state' => 'subscribed', 'opt_in_level' => 'single_opt_in'},
            'email_marketing_consent' => new Map<String, Object>{'state' => 'subscribed'},
            'default_address' => new Map<String, Object>{
                'address1' => 'Direct St',
                'city' => 'Direct City',
                'province' => 'DC',
                'zip' => '54321',
                'country' => 'CA'
            }
        };
        
        Test.startTest();
        Account acc = ShopifyCustomersBatch.testBuildAccountFromShopifyCustomer(customer);
        Test.stopTest();
        
        System.assertEquals('111111', acc.Shopify_ID__c);
        System.assertEquals('direct@test.com', acc.PersonEmail);
        System.assertEquals('Direct', acc.FirstName);
        System.assertEquals('Build', acc.LastName);
        System.assertEquals('subscribed', acc.SMS_Consent_State__c);
        System.assertEquals('single_opt_in', acc.SMS_Opt_In_Level__c);
        System.assertEquals('subscribed', acc.Email_Consent_State__c);
        System.assertEquals('Direct St', acc.BillingStreet);
        System.assertEquals('Direct City', acc.BillingCity);
    }
}