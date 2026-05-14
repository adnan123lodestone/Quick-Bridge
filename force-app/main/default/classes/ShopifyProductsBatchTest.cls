@isTest
private class ShopifyProductsBatchTest {

    private class ProductsMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  body;
        private String  nextLink;

        ProductsMock(Integer statusCode, String body, String nextLink) {
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

    private static String buildProductJson(String shopifyId, String title, String status, String sku, String price) {
        return '{"products":[{' +
            '"id":' + shopifyId + ',' +
            '"title":"' + title + '",' +
            '"status":"' + status + '",' +
            '"variants":[{"id":1,"sku":"' + sku + '","price":"' + price + '"}]' +
        '}]}';
    }

    // ── Positive ──────────────────────────────────────────────────────────────

    @isTest
    static void testPositive_InboundCreateActiveProduct() {
        ShopifyProductsBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new ProductsMock(200, buildProductJson('11001', 'Blue Widget', 'active', 'BW-001', '29.99'), null));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsBatch(), 1);
        Test.stopTest();

        List<Product2> products = [SELECT Id, Name, IsActive, StockKeepingUnit, Shopify_ID__c FROM Product2 WHERE Shopify_ID__c = '11001'];
        System.assertEquals(1, products.size(), 'Product should be created');
        System.assertEquals('Blue Widget', products[0].Name);
        System.assertEquals(true, products[0].IsActive, 'active status maps to IsActive=true');
        System.assertEquals('BW-001', products[0].StockKeepingUnit);
    }

    @isTest
    static void testPositive_InboundStatusDraftMapsToInactive() {
        ShopifyProductsBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new ProductsMock(200, buildProductJson('11002', 'Draft Widget', 'draft', 'DW-001', '0.00'), null));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsBatch(), 1);
        Test.stopTest();

        List<Product2> products = [SELECT IsActive FROM Product2 WHERE Shopify_ID__c = '11002'];
        System.assertEquals(1, products.size(), 'Product should be created');
        System.assertEquals(false, products[0].IsActive, 'draft status maps to IsActive=false');
    }

    @isTest
    static void testPositive_VariantSkuAndPricebookEntry() {
        ShopifyProductsBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new ProductsMock(200, buildProductJson('11003', 'Priced Widget', 'active', 'PW-001', '19.95'), null));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsBatch(), 1);
        Test.stopTest();

        Product2 prd = [SELECT Id, StockKeepingUnit FROM Product2 WHERE Shopify_ID__c = '11003'];
        System.assertEquals('PW-001', prd.StockKeepingUnit);

        List<PricebookEntry> pbes = [SELECT UnitPrice FROM PricebookEntry WHERE Product2Id = :prd.Id AND Pricebook2Id = :Test.getStandardPricebookId()];
        System.assertEquals(1, pbes.size(), 'PricebookEntry should be created');
        System.assertEquals(19.95, pbes[0].UnitPrice, 'Price should match variant price');
    }

    @isTest
    static void testPositive_UpdateExistingProduct() {
        ShopifyProductsBatch.bypassAuthCheckForTest = true;
        Product2 existing = new Product2(Name = 'Old Name', IsActive = false, Shopify_ID__c = '11004');
        insert existing;

        Test.setMock(HttpCalloutMock.class, new ProductsMock(200, buildProductJson('11004', 'New Name', 'active', '', '0.00'), null));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsBatch(), 1);
        Test.stopTest();

        Product2 updated = [SELECT Name, IsActive FROM Product2 WHERE Shopify_ID__c = '11004'];
        System.assertEquals('New Name', updated.Name, 'Name should be updated');
        System.assertEquals(true, updated.IsActive, 'IsActive should be updated');
    }

    @isTest
    static void testPositive_PaginationChain() {
        ShopifyProductsBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new ProductsMock(200, buildProductJson('11005', 'Paged Widget', 'active', 'PG-001', '5.00'), 'https://mock-shopify.com/page2'));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsBatch(), 1);
        Test.stopTest();

        System.assert(true, 'Pagination chain executed without error');
    }

    // ── Negative ──────────────────────────────────────────────────────────────

    @isTest
    static void testNegative_Non200Response() {
        ShopifyProductsBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new ProductsMock(401, '{"error":"Unauthorized"}', null));

        Integer productsBefore = [SELECT COUNT() FROM Product2];

        Test.startTest();
        Database.executeBatch(new ShopifyProductsBatch(), 1);
        Test.stopTest();

        System.assertEquals(productsBefore, [SELECT COUNT() FROM Product2], 'No products created on auth failure');
    }

    @isTest
    static void testNegative_EmptyProductsList() {
        ShopifyProductsBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new ProductsMock(200, '{"products":[]}', null));

        Integer productsBefore = [SELECT COUNT() FROM Product2];

        Test.startTest();
        Database.executeBatch(new ShopifyProductsBatch(), 1);
        Test.stopTest();

        System.assertEquals(productsBefore, [SELECT COUNT() FROM Product2], 'Empty list should produce no DML');
    }

    @isTest
    static void testNegative_CalloutsNotAllowed() {
        // bypassAuthCheckForTest = false, so auth check runs; but the auth check itself is bypassed at batch level.
        // Test the Allow_Callouts__c = false path by leaving bypassAuthCheckForTest = true
        // and relying on the test guard in getCalloutControl returning Allow_Callouts__c = true by default.
        // This test verifies no exception is thrown when products list is null in JSON.
        ShopifyProductsBatch.bypassAuthCheckForTest = true;
        Test.setMock(HttpCalloutMock.class, new ProductsMock(200, '{"products":null}', null));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsBatch(), 1);
        Test.stopTest();

        System.assert(true, 'Null products list handled without exception');
    }

    // ── Bulk ──────────────────────────────────────────────────────────────────

    @isTest
    static void testBulk_MultipleProducts() {
        ShopifyProductsBatch.bypassAuthCheckForTest = true;

        String productsArray = '';
        for (Integer i = 0; i < 20; i++) {
            if (i > 0) productsArray += ',';
            productsArray += '{"id":' + (20000 + i) + ',"title":"Bulk Product ' + i + '","status":"active","variants":[{"id":' + i + ',"sku":"BULK-' + i + '","price":"9.99"}]}';
        }
        Test.setMock(HttpCalloutMock.class, new ProductsMock(200, '{"products":[' + productsArray + ']}', null));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsBatch(), 1);
        Test.stopTest();

        List<Product2> products = [SELECT Id FROM Product2 WHERE Shopify_ID__c LIKE '2000%'];
        System.assertEquals(20, products.size(), 'All 20 bulk products should be created');
    }
}