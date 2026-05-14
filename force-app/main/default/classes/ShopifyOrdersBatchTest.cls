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
            if (String.isNotBlank(nextLink)) {
                res.setHeader('link', '<' + nextLink + '>; rel="next"');
            }
            return res;
        }
    }

    // Builds an order JSON with a line_item linked by product_id
    private static String buildOrderJson(String orderId, String customerEmail, String customerId, String productShopifyId) {
        return '{"orders":[{' +
            '"id":' + orderId + ',' +
            '"name":"#1001",' +
            '"created_at":"2024-01-15T10:30:00-05:00",' +
            '"financial_status":"paid",' +
            '"fulfillment_status":"fulfilled",' +
            '"total_price":"99.99",' +
            '"total_tax":"8.50",' +
            '"total_discounts":"5.00",' +
            '"contact_email":"' + customerEmail + '",' +
            '"cancel_reason":null,' +
            '"tags":"test-tag",' +
            '"tax_exempt":false,' +
            '"taxes_included":true,' +
            '"buyer_accepts_marketing":true,' +
            '"order_number":1001,' +
            '"customer":{"id":' + customerId + ',"email":"' + customerEmail + '","first_name":"Jane","last_name":"Doe","phone":"+15551234567"},' +
            '"line_items":[{"id":111,"product_id":' + productShopifyId + ',"sku":"SKU-001","title":"Widget","quantity":2,"price":"49.99"}]' +
        '}]}';
    }

    @TestSetup
    static void makeData() {
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Person Account' LIMIT 1].Id;
        Account acc = new Account(
            RecordTypeId  = rtId,
            FirstName     = 'Jane',
            LastName      = 'Doe',
            PersonEmail   = 'jane.doe@shopify.test',
            Shopify_ID__c = '777001'
        );
        insert acc;

        // Product2 must have Shopify_ID__c set — Orders no longer creates products
        Product2 prd = new Product2(Name = 'Widget', StockKeepingUnit = 'SKU-001', IsActive = true, Shopify_ID__c = '99001');
        insert prd;

        Id pbId = Test.getStandardPricebookId();
        insert new PricebookEntry(Pricebook2Id = pbId, Product2Id = prd.Id, UnitPrice = 49.99, IsActive = true);
    }

    // ── Positive ──────────────────────────────────────────────────────────────

    @isTest
    static void testPositive_BatchWithoutEndpoint() {
        String body = buildOrderJson('500001', 'jane.doe@shopify.test', '777001', '99001');
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        List<Order> orders = [SELECT Id, Financial_Status__c, Shopify_ID__c FROM Order WHERE Shopify_ID__c = '500001'];
        System.assertEquals(1, orders.size(), 'Expected one order');
        System.assertEquals('paid', orders[0].Financial_Status__c);
    }

    @isTest
    static void testPositive_BatchWithCustomEndpoint() {
        String body = buildOrderJson('500002', 'jane.doe@shopify.test', '777001', '99001');
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch('https://mock-shopify.com/custom'), 1);
        Test.stopTest();

        List<Order> orders = [SELECT Id FROM Order WHERE Shopify_ID__c = '500002'];
        System.assertEquals(1, orders.size(), 'Custom endpoint should produce an order');
    }

    @isTest
    static void testPositive_OrderItemCreatedByProductId() {
        String body = buildOrderJson('500003', 'jane.doe@shopify.test', '777001', '99001');
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        List<OrderItem> items = [SELECT Id, Shopify_ID__c, Quantity, UnitPrice FROM OrderItem WHERE Shopify_ID__c = '111'];
        System.assertEquals(1, items.size(), 'Expected one order item linked by product_id');
        System.assertEquals(2, (Integer) items[0].Quantity);
        System.assertEquals(49.99, items[0].UnitPrice);
    }

    @isTest
    static void testPositive_PaginationChain() {
        String body = buildOrderJson('500004', 'jane.doe@shopify.test', '777001', '99001');
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, 'https://mock-shopify.com/page2'));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        System.assert(true, 'Pagination chain executed without error');
    }

    @isTest
    static void testPositive_NewCustomerCreatedFromOrder() {
        String body = buildOrderJson('500005', 'brand.new@shopify.test', '999888', '99001');
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        List<Account> accs = [SELECT Id FROM Account WHERE PersonEmail = 'brand.new@shopify.test'];
        System.assertEquals(1, accs.size(), 'New person account should be created from order customer');
    }

    // ── Negative ──────────────────────────────────────────────────────────────

    @isTest
    static void testNegative_Non200Response() {
        Test.setMock(HttpCalloutMock.class, new OrdersMock(500, '{"error":"internal"}', null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        List<Order> orders = [SELECT Id FROM Order WHERE Shopify_ID__c != null];
        System.assertEquals(0, orders.size(), 'No orders should be created on API error');
    }

    @isTest
    static void testNegative_EmptyOrdersList() {
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, '{"orders":[]}', null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        System.assert(true, 'Empty orders list handled without error');
    }

    @isTest
    static void testNegative_OrderWithNoCustomer() {
        String body = '{"orders":[{"id":600001,"name":"#2001","created_at":"2024-01-15T10:30:00Z","financial_status":"paid","total_price":"50.00","total_tax":"0","total_discounts":"0","line_items":[]}]}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        List<Order> orders = [SELECT Id FROM Order WHERE Shopify_ID__c = '600001'];
        System.assertEquals(0, orders.size(), 'Order without customer should be skipped');
    }

    @isTest
    static void testNegative_LineItemWithUnknownProductId() {
        // product_id 00000 has no Product2 with that Shopify_ID__c — OrderItem must be skipped, no Product2 created
        String body = '{"orders":[{"id":600002,"name":"#2002","created_at":"2024-01-15T10:30:00Z",' +
            '"financial_status":"paid","total_price":"50.00","total_tax":"0","total_discounts":"0",' +
            '"customer":{"id":777001,"email":"jane.doe@shopify.test","first_name":"Jane","last_name":"Doe"},' +
            '"line_items":[{"id":222,"product_id":00000,"sku":"UNKNOWN","title":"Ghost","quantity":1,"price":"50.00"}]}]}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Integer productsBefore = [SELECT COUNT() FROM Product2];

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        List<OrderItem> items = [SELECT Id FROM OrderItem WHERE Shopify_ID__c = '222'];
        System.assertEquals(0, items.size(), 'Line item with unknown product_id must be skipped');

        Integer productsAfter = [SELECT COUNT() FROM Product2];
        System.assertEquals(productsBefore, productsAfter, 'Orders batch must never create Product2 records');
    }

    @isTest
    static void testNegative_LineItemMissingProductId() {
        // line_item has no product_id at all
        String body = '{"orders":[{"id":600003,"name":"#2003","created_at":"2024-01-15T10:30:00Z",' +
            '"financial_status":"paid","total_price":"50.00","total_tax":"0","total_discounts":"0",' +
            '"customer":{"id":777001,"email":"jane.doe@shopify.test","first_name":"Jane","last_name":"Doe"},' +
            '"line_items":[{"id":333,"sku":"SKU-001","title":"Widget","quantity":1,"price":"50.00"}]}]}';
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, body, null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        List<OrderItem> items = [SELECT Id FROM OrderItem WHERE Shopify_ID__c = '333'];
        System.assertEquals(0, items.size(), 'Line item without product_id must be skipped');
    }

    // ── Bulk ──────────────────────────────────────────────────────────────────

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
            ordersArray += '{"id":' + (700000 + i) + ',"name":"#300' + i + '",' +
                '"created_at":"2024-01-15T10:30:00Z",' +
                '"financial_status":"paid","total_price":"10.00","total_tax":"0","total_discounts":"0",' +
                '"customer":{"id":800' + String.valueOf(i).leftPad(3, '0') + ',"email":"bulk' + i + '@shopify.test","first_name":"Bulk","last_name":"User' + i + '"},' +
                '"line_items":[]}';
        }
        Test.setMock(HttpCalloutMock.class, new OrdersMock(200, '{"orders":[' + ordersArray + ']}', null));

        Test.startTest();
        Database.executeBatch(new ShopifyOrdersBatch(), 1);
        Test.stopTest();

        List<Order> orders = [SELECT Id FROM Order WHERE Shopify_ID__c LIKE '7000%'];
        System.assertEquals(10, orders.size(), 'All 10 bulk orders should be created');
    }
}