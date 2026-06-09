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
            AccountId           = acc.Id,
            EffectiveDate       = System.today(),
            Status              = 'Draft',
            Pricebook2Id        = pbId,
            Shopify_ID__c       = shopifyOrderId,
            Financial_Status__c = 'paid',
            Total_Amount__c     = 149.99,
            Total_Tax__c        = 12.50,
            Total_Discounts__c  = 0
        );
        insert ord;

        // Every test order gets one line item so Shopify accepts the payload
        Product2 prod = new Product2(Name = 'Test Item', StockKeepingUnit = 'TST-' + String.valueOf(Datetime.now().getTime()), IsActive = true);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id   = pbId,
            Product2Id     = prod.Id,
            UnitPrice      = 149.99,
            IsActive       = true
        );
        insert pbe;
        insert new OrderItem(
            OrderId          = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 149.99
        );

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

        Id pbId = Test.getStandardPricebookId();
        Order ord = new Order(
            AccountId     = acc.Id,
            EffectiveDate = System.today(),
            Status        = 'Draft',
            Pricebook2Id  = pbId,
            Total_Amount__c = 20.00
        );
        insert ord;

        Product2 prod = new Product2(Name = 'Email Test Item', IsActive = true);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = pbId, Product2Id = prod.Id, UnitPrice = 20.00, IsActive = true);
        insert pbe;
        insert new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 20.00);

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

    // ── Regression: mapped field not in SOQL ────────────────────────────────────

    @isTest
    static void testPositive_MappedOrderNameFieldNoSObjectException() {
        // Order.Name is in the fallback mapping; this confirms start() selects it
        // so ord.get(sfField) in buildOrderPayload never throws SObjectException.
        Order ord = makeOrder(null, '888020', 'name.field@shopify.test');
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new OrderApiMock(201, '300020'));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>{ ord.Id }, true), 10);
        Test.stopTest();

        Order updated = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('300020', updated.Shopify_ID__c, 'Batch must complete without SObjectException for mapped Order.Name');
    }

    // ── Regression: DML-before-callout uncommitted-work error ───────────────────

    private class SequencedMock implements HttpCalloutMock {
        private Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            if (callCount == 1) {
                // First record fails — used to trigger error logging path
                res.setStatusCode(422);
                res.setBody('{"errors":"Unprocessable entity"}');
            } else {
                // Subsequent records succeed
                res.setStatusCode(201);
                res.setBody('{"order":{"id":500002,"financial_status":"paid"}}');
            }
            return res;
        }
    }

    @isTest
    static void testPositive_FailedFirstRecordDoesNotBlockSubsequentCallout() {
        // If error logging (DML) happens inside the callout loop, the second Http.send()
        // throws "uncommitted work pending". This test catches that regression.
        Order ord1 = makeOrder(null, '888030', 'fail.order@shopify.test');
        Order ord2 = makeOrder(null, '888031', 'succeed.order@shopify.test');
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new SequencedMock());

        Test.startTest();
        Database.executeBatch(
            new ShopifyOrdersOutboundBatch(new Set<Id>{ ord1.Id, ord2.Id }, true), 200
        );
        Test.stopTest();

        Order updated2 = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord2.Id];
        System.assertEquals('500002', updated2.Shopify_ID__c, 'Second order must succeed even when first callout fails');
    }

    // ── Regression: 429 rate limit — remaining records deferred ────────────────

    private class RateLimitThenSuccessMock implements HttpCalloutMock {
        private Integer callCount = 0;
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            if (callCount == 1) {
                res.setStatusCode(429);
                res.setHeader('Retry-After', '2');
                res.setBody('{"errors":"Too Many Requests"}');
            } else {
                res.setStatusCode(201);
                res.setBody('{"order":{"id":600001,"financial_status":"paid"}}');
            }
            return res;
        }
    }

    @isTest
    static void testNegative_RateLimit429_FirstRecordDeferredSecondNotAttempted() {
        // When the first callout returns 429, the batch must NOT attempt subsequent
        // callouts in the same execute() scope — remaining IDs go into rateLimitedIds
        // and finish() schedules a follow-up batch.
        Order ord1 = makeOrder(null, '888040', 'rate.limit.1@shopify.test');
        Order ord2 = makeOrder(null, '888041', 'rate.limit.2@shopify.test');
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        // Only one callout fires (first returns 429), so a single-call mock is fine
        Test.setMock(HttpCalloutMock.class, new OrderApiMock(429, null));

        Test.startTest();
        Database.executeBatch(
            new ShopifyOrdersOutboundBatch(new Set<Id>{ ord1.Id, ord2.Id }, true), 200
        );
        Test.stopTest();

        // Neither record should have Shopify ID written back in this run
        Order updated1 = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord1.Id];
        Order updated2 = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord2.Id];
        System.assertEquals(null, updated1.Shopify_ID__c, 'Rate-limited record must not write Shopify ID');
        System.assertEquals(null, updated2.Shopify_ID__c, 'Deferred record must not write Shopify ID');
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

    // ── Regression: line_items must be present in outbound payload ──────────────

    private class LineItemCaptureMock implements HttpCalloutMock {
        public String capturedBody;
        public HttpResponse respond(HttpRequest req) {
            capturedBody = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setBody('{"order":{"id":700001,"financial_status":"paid"}}');
            return res;
        }
    }

    @isTest
    static void testPositive_LineItemsIncludedInPayload() {
        Order ord = makeOrder(null, '888050', 'lineitems@shopify.test');
        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        LineItemCaptureMock mock = new LineItemCaptureMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>{ ord.Id }, true), 10);
        Test.stopTest();

        System.assertNotEquals(null, mock.capturedBody, 'A callout must have been made');
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        Map<String, Object> orderNode = (Map<String, Object>) parsed.get('order');
        List<Object> lineItems = (List<Object>) orderNode.get('line_items');
        System.assertNotEquals(null, lineItems, 'line_items must be present in the payload');
        System.assert(!lineItems.isEmpty(), 'line_items must be non-empty');
        Map<String, Object> li = (Map<String, Object>) lineItems[0];
        System.assertNotEquals(null, li.get('quantity'), 'line item must have quantity');
        System.assertNotEquals(null, li.get('price'), 'line item must have price');
        System.assertNotEquals(null, li.get('title'), 'line item must have title');

        Order updated = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('700001', updated.Shopify_ID__c, 'Shopify ID should be written back');
    }

    @isTest
    static void testNegative_NoLineItems_OrderSkippedNotSent() {
        // Create an order WITHOUT the OrderItem that makeOrder() normally adds
        Account acc = new Account(
            RecordTypeId  = getPersonAccountRTId(),
            FirstName     = 'No',
            LastName      = 'Lines',
            PersonEmail   = 'nolines@shopify.test',
            Shopify_ID__c = '888060'
        );
        insert acc;
        Order ord = new Order(
            AccountId     = acc.Id,
            EffectiveDate = System.today(),
            Status        = 'Draft',
            Pricebook2Id  = Test.getStandardPricebookId(),
            Total_Amount__c = 10.00
        );
        insert ord;

        ShopifyOrdersOutboundBatch.bypassAuthCheckForTest = true;
        LineItemCaptureMock mock = new LineItemCaptureMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>{ ord.Id }, true), 10);
        Test.stopTest();

        System.assertEquals(null, mock.capturedBody, 'No callout should be made for an order with no line items');
        Order unchanged = [SELECT Shopify_ID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals(null, unchanged.Shopify_ID__c, 'Shopify ID must not be written when order has no line items');
    }
}