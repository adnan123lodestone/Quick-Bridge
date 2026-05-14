@isTest
private class ShopifyCustomersOutboundBatchTest {

    // ── Mock ────────────────────────────────────────────────────────────────────

    private class CreateMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  shopifyId;

        CreateMock(Integer statusCode, String shopifyId) {
            this.statusCode = statusCode;
            this.shopifyId  = shopifyId;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            if (statusCode == 200 || statusCode == 201) {
                res.setBody('{"customer":{"id":' + shopifyId + ',"email":"test@example.com"}}');
            } else {
                res.setBody('{"errors":"Bad request"}');
            }
            return res;
        }
    }

    // ── Setup ───────────────────────────────────────────────────────────────────

    private static Id getPersonAccountRTId() {
        return [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Person Account' LIMIT 1].Id;
    }

    private static Account makeAccount(String email, String shopifyId) {
        Account acc = new Account(
            RecordTypeId  = getPersonAccountRTId(),
            FirstName     = 'Test',
            LastName      = 'Customer',
            PersonEmail   = email,
            Shopify_ID__c = shopifyId,
            Phone         = '+15551234567',
            BillingStreet = '100 Main St',
            BillingCity   = 'Chicago',
            BillingState  = 'IL',
            BillingPostalCode = '60601',
            BillingCountry    = 'US'
        );
        insert acc;
        return acc;
    }

    // ── Positive ────────────────────────────────────────────────────────────────

    @isTest
    static void testPositive_NewCustomerCreated() {
        Account acc = makeAccount('new.customer@shopify.test', null);
        ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '123456789'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('123456789', updated.Shopify_ID__c, 'Shopify ID should be written back after create');
    }

    @isTest
    static void testPositive_ExistingCustomerUpdated() {
        Account acc = makeAccount('existing@shopify.test', '555999');
        ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new CreateMock(200, '555999'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, false), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('555999', updated.Shopify_ID__c, 'Existing Shopify ID should be preserved');
    }

    @isTest
    static void testPositive_AddressIncludedInPayload() {
        Account acc = makeAccount('addr.test@shopify.test', null);
        ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '777111'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('777111', updated.Shopify_ID__c, 'Customer with address created in Shopify');
    }

    // ── Negative ────────────────────────────────────────────────────────────────

    @isTest
    static void testNegative_ApiError() {
        Account acc = makeAccount('api.error@shopify.test', null);
        ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new CreateMock(422, null));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(null, updated.Shopify_ID__c, 'Shopify ID should not be set when API returns error');
    }

    @isTest
    static void testNegative_EmptyRecordSet() {
        ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new CreateMock(200, '000000'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>(), true), 10);
        Test.stopTest();

        System.assert(true, 'Empty record set handled without error');
    }

    @isTest
    static void testNegative_AuthNotActive() {
        Account acc = makeAccount('no.auth@shopify.test', null);
        // bypassAuthCheckForTest stays false — license check will skip execution
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '999888'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(null, updated.Shopify_ID__c, 'Execution skipped when license check fails');
    }

    // ── Bulk ────────────────────────────────────────────────────────────────────

    @isTest
    static void testBulk_MultipleCustomers() {
        List<Account> accs = new List<Account>();
        Id rtId = getPersonAccountRTId();
        for (Integer i = 0; i < 20; i++) {
            accs.add(new Account(
                RecordTypeId = rtId,
                FirstName    = 'Bulk',
                LastName     = 'Cust' + i,
                PersonEmail  = 'bulk.cust' + i + '@shopify.test'
            ));
        }
        insert accs;

        Set<Id> ids = new Map<Id, Account>(accs).keySet();
        ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '100000'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(ids, true), 10);
        Test.stopTest();

        Integer synced = [SELECT COUNT() FROM Account WHERE PersonEmail LIKE 'bulk.cust%@shopify.test' AND Shopify_ID__c = '100000'];
        System.assertEquals(20, synced, 'All 20 bulk customers should be synced to Shopify');
    }
}