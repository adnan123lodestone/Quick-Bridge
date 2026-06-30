@isTest
private class ShopifyOrdersBatchTest {

    private class OrdersMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  body;
        private String  nextLink;

        OrdersMock(Integer statusCode, String body, String nextLink) {
            this.statusCode = statusCode;
            this.body       = body;
            this.nextLink   = nextLink;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            if (String.isNotBlank(nextLink) && !req.getEndpoint().contains('page2')) {
                res.setHeader('link', '<' + nextLink + '>; rel="next"');
            }
            return res;
        }
    }

    private static String getSafeOrderJson(String orderId) {
        return '{' +
            '"id":' + orderId + ',' +
            '"created_at":"2024-01-15T10:30:00Z",' +
            '"financial_status":"paid",' +
            '"total_price":99.99,' +
            '"buyer_accepts_marketing":false,' +
            '"estimated_taxes":false,' +
            '"tax_exempt":false,' +
            '"taxes_included":false,' +
            '"customer":{"id":777001,"email":"jane.doe@shopify.test","first_name":"Jane","last_name":"Doe"},' +
            '"line_items":[{"id":111,"product_id":99001,"sku":"SKU-001","quantity":2,"price":49.99}]' +
        '}';
    }

    @TestSetup
    static void makeData() {
        insert new Integration_Entitlement__c(
            Name = 'Checkout Entitlement',
            Cache_Key__c = 'checkout',
            Product_Key__c = 'checkout',
            Status__c = 'Active',
            Raw_Response__c = '{"status":"Success","activeGateways":["Shopify"],"message":"ok"}',
            Active_Gateways_JSON__c = '["Shopify"]',
            Last_Refreshed_At__c = System.now(),
            Expires_At__c = System.now().addDays(1),
            TTL_Minutes__c = 1440,
            Refresh_Status__c = 'Success',
            Fail_Policy__c = 'Fail Open'
        );

        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Person Account' LIMIT 1].Id;
        insert new Account(
            RecordTypeId  = rtId,
            FirstName     = 'Jane',
            LastName      = 'Doe',
            PersonEmail   = 'jane.doe@shopify.test',
            Shopify_ID__c = '777001'
        );

        Product2 prd = new Product2(Name = 'Widget', StockKeepingUnit = 'SKU-001', IsActive = true, Shopify_ID__c = '99001');
        insert prd;

        Id pbId = Test.getStandardPricebookId();
        update new Pricebook2(Id = pbId, IsActive = true);
        insert new PricebookEntry(Pricebook2Id = pbId, Product2Id = prd.Id, UnitPrice = 49.99, IsActive = true);
    }

    @isTest
    static void testPositive_BatchComprehensive() {
        String body = '{"orders":[' + getSafeOrderJson('500001') + ']}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Shopify_ID__c = '500001']);
        System.assertEquals(1, [SELECT COUNT() FROM OrderItem WHERE Shopify_ID__c = '111']);
    }

    @isTest
    static void testPositive_RelativeEndpoint() {
        String body = '{"orders":[' + getSafeOrderJson('500002') + ']}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch('/admin/api/2024-04/orders.json?status=open'), 1);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Shopify_ID__c = '500002']);
    }

    @isTest
    static void testPositive_AbsoluteEndpoint() {
        String body = '{"orders":[' + getSafeOrderJson('500003') + ']}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch('https://mock-shopify.com/custom'), 1);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Shopify_ID__c = '500003']);
    }

    @isTest
    static void testPositive_PaginationChain() {
        String body = '{"orders":[' + getSafeOrderJson('500004') + ']}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, 'https://mock-shopify.com/page2'));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Shopify_ID__c = '500004']);
    }

    @isTest
    static void testNegative_Non200Response() {
        Test.setMock(HttpCalloutMock.class, new OrdersMock(500, '{"error":"internal"}', null));
        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Order WHERE Shopify_ID__c != null]);
    }

    @isTest
    static void testNegative_EmptyOrdersList() {
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, '{"orders":[]}', null));
        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Order WHERE Shopify_ID__c != null]);
    }

    @isTest
    static void testNegative_OrderWithNoCustomer() {
        String body = '{"orders":[{"id":600001,"created_at":"2024-01-15T10:30:00Z","buyer_accepts_marketing":false,"estimated_taxes":false,"tax_exempt":false,"taxes_included":false,"line_items":[]}]}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));
        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Order WHERE Shopify_ID__c = '600001']);
    }

    @isTest
    static void testNegative_MappingExceptions() {
        String body = '{"orders":[{"id":600002,"created_at":"2024-01-15T10:30:00Z","total_price":"NOT_A_DECIMAL","buyer_accepts_marketing":false,"estimated_taxes":false,"tax_exempt":false,"taxes_included":false,"customer":{"id":777001,"email":"jane.doe@shopify.test"}}]}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));
        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Shopify_ID__c = '600002']);
    }
    
    @isTest
    static void testNegative_OuterCatchBlock() {
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, 'INVALID JSON', null));
        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Order WHERE Shopify_ID__c != null]);
    }

    @isTest
    static void testNegative_InnerMappingCatchBlock() {
        String body = '{"orders":[{"id":600005,"total_price":{},"buyer_accepts_marketing":false,"estimated_taxes":false,"tax_exempt":false,"taxes_included":false,"customer":{"id":777001,"email":"jane.doe@shopify.test"}}]}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));
        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Shopify_ID__c = '600005']);
    }

    @isTest
    static void testSyncOrderFromShopify_Success() {
        String body = '{"order":' + getSafeOrderJson('500010') + '}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        ShopifyOrdersBatch.syncOrderFromShopify('500010');
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Shopify_ID__c = '500010']);
    }

    @isTest
    static void testSyncOrderFromShopify_MappingException() {
        String body = '{"order":{' +
            '"id":500012,' +
            '"created_at":"2024-01-15T10:30:00Z",' +
            '"total_price":"NOT_A_DECIMAL",' +
            '"buyer_accepts_marketing":false,' +
            '"estimated_taxes":false,' +
            '"tax_exempt":false,' +
            '"taxes_included":false,' +
            '"customer":{"id":777001,"email":"jane.doe@shopify.test"}' +
        '}}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        ShopifyOrdersBatch.syncOrderFromShopify('500012');
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Shopify_ID__c = '500012']);
    }

    @isTest
    static void testSyncOrderFromShopify_Error() {
        Test.setMock(HttpCalloutMock.class, new OrdersMock(404, '{"error":"not found"}', null));
        Boolean thrown = false;
        try {
            ShopifyOrdersBatch.syncOrderFromShopify('000');
        } catch(CalloutException e) {
            thrown = true;
        }
        System.assert(thrown);
    }

    @isTest
    static void testSyncOrderFromShopify_NoCustomerMatch() {
        String body = '{"order":{"id":500011,"buyer_accepts_marketing":false,"estimated_taxes":false,"tax_exempt":false,"taxes_included":false,"customer":{"id":999999,"email":"nomatch@test.com"}}}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));
        Boolean thrown = false;
        try {
            ShopifyOrdersBatch.syncOrderFromShopify('500011');
        } catch(CalloutException e) {
            thrown = true;
        }
        System.assert(thrown);
    }

    @isTest
    static void testBulk_MultipleOrders() {
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Person Account' LIMIT 1].Id;
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 10; i++) {
            accs.add(new Account(
                RecordTypeId  = rtId,
                FirstName     = 'Bulk',
                LastName      = 'User' + i,
                PersonEmail   = 'bulk' + i + '@shopify.test',
                Shopify_ID__c = '800' + String.valueOf(i).leftPad(3, '0')
            ));
        }
        insert accs;

        String ordersArray = '';
        for (Integer i = 0; i < 10; i++) {
            if (i > 0) ordersArray += ',';
            ordersArray += '{"id":' + (700000 + i) + ',' +
                '"created_at":"2024-01-15T10:30:00Z",' +
                '"financial_status":"paid","total_price":10.00,' +
                '"buyer_accepts_marketing":false,' +
                '"estimated_taxes":false,' +
                '"tax_exempt":false,' +
                '"taxes_included":false,' +
                '"customer":{"id":800' + String.valueOf(i).leftPad(3, '0') + ',"email":"bulk' + i + '@shopify.test","first_name":"Bulk","last_name":"User' + i + '"},' +
                '"line_items":[]}';
        }
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, '{"orders":[' + ordersArray + ']}', null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        System.assertEquals(10, [SELECT COUNT() FROM Account WHERE Shopify_ID__c LIKE '800%']);
    }
}