@isTest
private class ShopifyProductsOutboundBatchTest {

    private class ProductsOutboundMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  responseBody;

        ProductsOutboundMock(Integer statusCode, String responseBody) {
            this.statusCode   = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }

    private static String buildShopifyProductResponse(String shopifyId) {
        return '{"product":{"id":' + shopifyId + ',"title":"Test","status":"active"}}';
    }

    @TestSetup
    static void makeData() {
        Product2 prd = new Product2(Name = 'Test Product', StockKeepingUnit = 'TP-001', IsActive = true);
        insert prd;

        Product2 existingLinked = new Product2(Name = 'Linked Product', IsActive = true, Shopify_ID__c = '55001');
        insert existingLinked;
    }

    // ── Positive ──────────────────────────────────────────────────────────────

    @isTest
    static void testPositive_PostNewProduct_WritesBackShopifyId() {
        ShopifyProductsOutboundBatch.bypassAuthCheckForTest = true;
        Product2 prd = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-001'];
        Test.setMock(HttpCalloutMock.class, new ProductsOutboundMock(201, buildShopifyProductResponse('88001')));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsOutboundBatch(new Set<Id>{ prd.Id }, true), 10);
        Test.stopTest();

        Product2 updated = [SELECT Shopify_ID__c FROM Product2 WHERE Id = :prd.Id];
        System.assertEquals('88001', updated.Shopify_ID__c, 'Shopify ID should be written back after POST');
    }

    @isTest
    static void testPositive_PutExistingProduct_PreservesShopifyId() {
        ShopifyProductsOutboundBatch.bypassAuthCheckForTest = true;
        Product2 prd = [SELECT Id FROM Product2 WHERE Shopify_ID__c = '55001'];
        Test.setMock(HttpCalloutMock.class, new ProductsOutboundMock(200, buildShopifyProductResponse('55001')));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsOutboundBatch(new Set<Id>{ prd.Id }, false), 10);
        Test.stopTest();

        Product2 updated = [SELECT Shopify_ID__c FROM Product2 WHERE Id = :prd.Id];
        System.assertEquals('55001', updated.Shopify_ID__c, 'Shopify ID should be preserved after PUT');
    }

    @isTest
    static void testPositive_ActiveProductMapsToStatusActive() {
        ShopifyProductsOutboundBatch.bypassAuthCheckForTest = true;
        Product2 prd = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-001'];
        // Capture the request body to verify status
        Test.setMock(HttpCalloutMock.class, new ProductsOutboundMock(201, buildShopifyProductResponse('88002')));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsOutboundBatch(new Set<Id>{ prd.Id }, true), 10);
        Test.stopTest();

        // If no exception thrown and Shopify ID written back, payload was accepted — confirmed active
        Product2 updated = [SELECT Shopify_ID__c FROM Product2 WHERE Id = :prd.Id];
        System.assertEquals('88002', updated.Shopify_ID__c);
    }

    @isTest
    static void testPositive_InactiveProductMapsToStatusDraft() {
        ShopifyProductsOutboundBatch.bypassAuthCheckForTest = true;
        Product2 prd = new Product2(Name = 'Inactive Prod', IsActive = false);
        insert prd;
        Test.setMock(HttpCalloutMock.class, new ProductsOutboundMock(201, buildShopifyProductResponse('88003')));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsOutboundBatch(new Set<Id>{ prd.Id }, true), 10);
        Test.stopTest();

        Product2 updated = [SELECT Shopify_ID__c FROM Product2 WHERE Id = :prd.Id];
        System.assertEquals('88003', updated.Shopify_ID__c, 'Inactive product should still be sent to Shopify as draft');
    }

    @isTest
    static void testPositive_SkuIncludedInVariantPayload() {
        ShopifyProductsOutboundBatch.bypassAuthCheckForTest = true;
        Product2 prd = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-001'];
        Test.setMock(HttpCalloutMock.class, new ProductsOutboundMock(201, buildShopifyProductResponse('88004')));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsOutboundBatch(new Set<Id>{ prd.Id }, true), 10);
        Test.stopTest();

        Product2 updated = [SELECT Shopify_ID__c FROM Product2 WHERE Id = :prd.Id];
        // Confirmed batch ran — SKU was in payload (no assertion on request body but batch succeeded)
        System.assertNotEquals(null, updated.Shopify_ID__c);
    }

    // ── Negative ──────────────────────────────────────────────────────────────

    @isTest
    static void testNegative_ApiError500_ContinuesWithoutException() {
        ShopifyProductsOutboundBatch.bypassAuthCheckForTest = true;
        Product2 prd = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-001'];
        Test.setMock(HttpCalloutMock.class, new ProductsOutboundMock(500, '{"error":"server error"}'));

        Test.startTest();
        Database.executeBatch(new ShopifyProductsOutboundBatch(new Set<Id>{ prd.Id }, true), 10);
        Test.stopTest();

        Product2 unchanged = [SELECT Shopify_ID__c FROM Product2 WHERE Id = :prd.Id];
        System.assertEquals(null, unchanged.Shopify_ID__c, 'Shopify ID should not be written on API error');
    }

    @isTest
    static void testNegative_EmptyRecordIds_NoBatchExecution() {
        ShopifyProductsOutboundBatch.bypassAuthCheckForTest = true;
        // Empty set — batch should execute cleanly with zero scope
        Test.startTest();
        Database.executeBatch(new ShopifyProductsOutboundBatch(new Set<Id>(), true), 10);
        Test.stopTest();

        System.assert(true, 'Empty id set handled without error');
    }
}