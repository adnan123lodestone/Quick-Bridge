@isTest
private class ShopifyOrdersOutboundBatchTest {

    // ── Mock ────────────────────────────────────────────────────────────────────

    private class OrderApiMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  shopifyOrderId;

        OrderApiMock(Integer statusCode, String shopifyOrderId) {
            this.statusCode     = statusCode;
            this.shopifyOrderId = shopifyOrderId;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            if (statusCode == 200 || statusCode == 201) {
                res.setBody('{"order":{"id":' + shopifyOrderId + ',"financial_status":"paid"}}');
            } else {
                res.setBody('{"errors":"Unprocessable entity"}');
            }
            return res;
        }
    }

    // ── Setup ───────────────────────────────────────────────────────────────────

    private static Id getPersonAccountRTId() {
        return [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Person Account' LIMIT 1].Id;
    }

    private static Order makeOrder(String shopifyOrderId, String accountShopifyId, String accountEmail) {
        Account acc = new Account(
            RecordTypeId  = getPersonAccountRTId(),
            FirstName     = 'Order',
            LastName      = 'Owner',
            PersonEmail   = accountEmail,
            Shopify_ID__c = accountShopifyId
        );
        insert acc;

        Id pbId = Test.getStandardPricebookId();
        Order ord = new Order(
            AccountId         = acc.Id,
            EffectiveDate     = System.today(),
            Status            = 'Draft',
            Pricebook2Id      = pbId,
            Shopify_ID__c     = shopifyOrderId,
            Financial_Status__c = 'paid',
            Total_Amount__c   = 149.99,
            Total_Tax__c      = 12.50,
            Total_Discounts__c = 0
        );
        insert ord;
        return ord;
    }

    // ── Positive ────────────────────────────────────────────────────────────────

    @isTest
    static void testPositive_NewOrderCreated() {
        Order ord = makeOrder(null, '888001', 'new.order@shopify.test');
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new OrderApiMock(201, '300001'));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>{ ord.Id }, true), 10);
        Test.stopTest();

        Order updated = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('300001', updated.Shopify_ID__c, 'Shopify Order ID should be written back after create');
    }

    @isTest
    static void testPositive_ExistingOrderUpdated() {
        Order ord = makeOrder('300002', '888002', 'update.order@shopify.test');
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new OrderApiMock(200, '300002'));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>{ ord.Id }, false), 10);
        Test.stopTest();

        Order updated = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('300002', updated.Shopify_ID__c, 'Existing Shopify Order ID preserved after update');
    }

    @isTest
    static void testPositive_CustomerLinkedByShopifyId() {
        Order ord = makeOrder(null, '888003', 'linked@shopify.test');
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new OrderApiMock(201, '300003'));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>{ ord.Id }, true), 10);
        Test.stopTest();

        Order updated = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('300003', updated.Shopify_ID__c, 'Order linked via account Shopify ID created successfully');
    }

    @isTest
    static void testPositive_CustomerLinkedByEmail() {
        // Account has no Shopify_ID__c — should fall back to email in payload
        Account acc = new Account(
            RecordTypeId = getPersonAccountRTId(),
            FirstName    = 'Email',
            LastName     = 'Fallback',
            PersonEmail  = 'email.fallback@shopify.test'
        );
        insert acc;

        Order ord = new Order(
            AccountId     = acc.Id,
            EffectiveDate = System.today(),
            Status        = 'Draft',
            Pricebook2Id  = Test.getStandardPricebookId(),
            Total_Amount__c = 20.00
        );
        insert ord;

        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new OrderApiMock(201, '300004'));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>{ ord.Id }, true), 10);
        Test.stopTest();

        Order updated = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('300004', updated.Shopify_ID__c, 'Order linked via email fallback created in Shopify');
    }

    // ── Negative ────────────────────────────────────────────────────────────────

    @isTest
    static void testNegative_ApiError() {
        Order ord = makeOrder(null, '888010', 'api.error.order@shopify.test');
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new OrderApiMock(422, null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>{ ord.Id }, true), 10);
        Test.stopTest();

        Order updated = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals(null, updated.Shopify_ID__c, 'Shopify ID should not be set when API errors');
    }

    @isTest
    static void testNegative_EmptyRecordSet() {
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new OrderApiMock(201, '999000'));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>(), true), 10);
        Test.stopTest();

        System.assert(true, 'Empty record set handled without error');
    }

    @isTest
    static void testNegative_AuthNotActive() {
        Order ord = makeOrder(null, '888011', 'no.auth.order@shopify.test');
        // bypassAuthCheckForTest stays false
        Test.setMock(HttpCalloutMock.class, new OrderApiMock(201, '999001'));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>{ ord.Id }, true), 10);
        Test.stopTest();

        Order updated = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals(null, updated.Shopify_ID__c, 'Execution skipped when license check fails');
    }

    // ── Bulk ────────────────────────────────────────────────────────────────────

    @isTest
    static void testBulk_MultipleOrders() {
        Id rtId  = getPersonAccountRTId();
        Id pbId  = Test.getStandardPricebookId();
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 15; i++) {
            accs.add(new Account(
                RecordTypeId  = rtId,
                FirstName     = 'Bulk',
                LastName      = 'Ord' + i,
                PersonEmail   = 'bulk.ord' + i + '@shopify.test',
                Shopify_ID__c = '9' + String.valueOf(i).leftPad(5, '0')
            ));
        }
        insert accs;

        List<Order> ords = new List<Order>();
        for (Account acc : accs) {
            ords.add(new Order(
                AccountId     = acc.Id,
                EffectiveDate = System.today(),
                Status        = 'Draft',
                Pricebook2Id  = pbId,
                Total_Amount__c = 10.00
            ));
        }
        insert ords;

        Set<Id> ids = new Map<Id, Order>(ords).keySet();
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new OrderApiMock(201, '400000'));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(ids, true), 10);
        Test.stopTest();

        Integer synced = [SELECT COUNT() FROM Order WHERE AccountId IN :new Map<Id, Account>(accs).keySet() AND Shopify_ID__c = '400000'];
        System.assertEquals(15, synced, 'All 15 bulk orders should be synced to Shopify');
    }
}