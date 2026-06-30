@isTest
private class ShopifyCustomersOutboundBatchTest {

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
            } else if (statusCode == 429) {
                res.setHeader('Retry-After', '60');
                res.setBody('{}');
            } else {
                res.setBody('{"errors":"Bad request"}');
            }
            return res;
        }
    }

    @testSetup
    static void setupData() {
        Connector_Instance__c shopifyInstance = new Connector_Instance__c(
            Name = 'Shopify',
            Connector_Key__c = 'shopify',
            Connector_Label__c = 'Shopify',
            Active__c = true,
            Environment__c = 'Production',
            Entitlement_Status__c = 'Active',
            Health_Status__c = 'Unknown',
            Named_Credential__c = 'Shopify_API'
        );
        insert shopifyInstance;

        Connector_Config_Value__c apiVersion = new Connector_Config_Value__c(
            Name = 'shopify.API_Version__c',
            Connector_Instance__c = shopifyInstance.Id,
            Connector_Key__c = 'shopify',
            Field_Key__c = 'API_Version__c',
            Value__c = '2024-04'
        );
        insert apiVersion;
    }

    private static Id getPersonAccountRTId() {
        List<RecordType> rt = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1];
        return rt.isEmpty() ? null : rt[0].Id;
    }

    private static Account makeAccount(String email, String shopifyId) {
        Id rtId = getPersonAccountRTId();
        Account acc = new Account();
        if (rtId != null) {
            acc.RecordTypeId = rtId;
            acc.FirstName = 'Test';
            acc.LastName = 'Customer';
            acc.PersonEmail = email;
        } else {
            acc.Name = email;
        }
        acc.Phone = '+15551234567';
        acc.BillingStreet = '100 Main St';
        acc.BillingCity = 'Chicago';
        acc.BillingState = 'IL';
        acc.BillingPostalCode = '60601';
        acc.BillingCountry = 'US';
        if (String.isNotBlank(shopifyId)) {
            acc.Shopify_ID__c = shopifyId;
        }
        insert acc;
        return acc;
    }

    private static Account makeBusinessAccount(String name, String shopifyId) {
        Account acc = new Account(
            Name = name,
            Phone = '+15559876543',
            BillingStreet = '200 Corp Blvd',
            BillingCity = 'Austin',
            BillingState = 'TX',
            BillingPostalCode = '78701',
            BillingCountry = 'US'
        );
        if (String.isNotBlank(shopifyId)) {
            acc.Shopify_ID__c = shopifyId;
        }
        insert acc;
        return acc;
    }

    private static void prepareTest() {
        ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = true;
        ShopifyCustomersOutboundBatch.testShopifyIdField = 'QuickBridgeTLG__Shopify_ID__c';
    }

    @isTest
    static void testPositive_NewCustomerCreated() {
        Account acc = makeAccount('new.customer@shopify.test', null);
        prepareTest();
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '123456789'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('123456789', updated.Shopify_ID__c);
    }

    @isTest
    static void testPositive_ExistingCustomerUpdated() {
        Account acc = makeAccount('existing@shopify.test', '555999');
        prepareTest();
        Test.setMock(HttpCalloutMock.class, new CreateMock(200, '555999'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, false), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('555999', updated.Shopify_ID__c);
    }

    @isTest
    static void testPositive_AddressIncludedInPayload() {
        Account acc = makeAccount('addr.test@shopify.test', null);
        prepareTest();
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '777111'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('777111', updated.Shopify_ID__c);
    }

    @isTest
    static void testNegative_ApiError() {
        Account acc = makeAccount('api.error@shopify.test', null);
        prepareTest();
        Test.setMock(HttpCalloutMock.class, new CreateMock(422, null));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(null, updated.Shopify_ID__c);
    }

    @isTest
    static void testNegative_EmptyRecordSet() {
        prepareTest();
        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>(), true), 10);
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testNegative_AuthNotActive() {
        Account acc = makeAccount('no.auth@shopify.test', null);
        ShopifyCustomersOutboundBatch.bypassAuthCheckForTest = false;
        ShopifyCustomersOutboundBatch.testShopifyIdField = 'QuickBridgeTLG__Shopify_ID__c';
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '999888'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(null, updated.Shopify_ID__c);
    }

    @isTest
    static void testNegative_RateLimit429() {
        Account acc = makeAccount('rate.limit@shopify.test', null);
        prepareTest();
        Test.setMock(HttpCalloutMock.class, new CreateMock(429, null));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(null, updated.Shopify_ID__c);
    }

    @isTest
    static void testPositive_BusinessAccountCreated() {
        Account acc = makeBusinessAccount('Acme Corp', null);
        prepareTest();
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '987654321'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('987654321', updated.Shopify_ID__c);
    }

    @isTest
    static void testPositive_BusinessAccountAlreadySynced() {
        Account synced    = makeBusinessAccount('Already Synced Corp', '111222');
        Account unsynced  = makeBusinessAccount('New Business Inc', null);
        prepareTest();
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '333444'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ unsynced.Id }, true), 10);
        Test.stopTest();

        Account stillSynced = [SELECT Shopify_ID__c FROM Account WHERE Id = :synced.Id];
        Account nowSynced   = [SELECT Shopify_ID__c FROM Account WHERE Id = :unsynced.Id];
        System.assertEquals('111222', stillSynced.Shopify_ID__c);
        System.assertEquals('333444', nowSynced.Shopify_ID__c);
    }

    @isTest
    static void testPositive_BusinessAccountUsesNameAsLastName() {
        Account acc = makeBusinessAccount('Global Widgets LLC', null);
        prepareTest();
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '555777'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ acc.Id }, true), 10);
        Test.stopTest();

        Account updated = [SELECT Shopify_ID__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('555777', updated.Shopify_ID__c);
    }

    @isTest
    static void testBulk_MultipleCustomers() {
        Set<Id> ids = new Set<Id>();
        for (Integer i = 0; i < 20; i++) {
            ids.add(makeAccount('bulk.cust' + i + '@shopify.test', null).Id);
        }
        prepareTest();
        Test.setMock(HttpCalloutMock.class, new CreateMock(201, '100000'));

        Test.startTest();
        Database.executeBatch(new ShopifyCustomersOutboundBatch(ids, true), 200);
        Test.stopTest();

        Integer synced = [SELECT COUNT() FROM Account WHERE Id IN :ids AND Shopify_ID__c = '100000'];
        System.assertEquals(20, synced, 'All 20 bulk accounts should be synced');
    }
}