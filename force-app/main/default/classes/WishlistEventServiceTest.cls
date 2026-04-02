@isTest
private class WishlistEventServiceTest {

    @testSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(
            FirstName = 'Test',
            LastName = 'User',
            PersonEmail = 'test@example.com'
        );
        insert testAccount;

        // Create test product
        Product2 testProduct = new Product2(
            Name = 'Test Product',
            StockKeepingUnit = 'SKU123',
            IsActive = true
        );
        insert testProduct;
    }

    @isTest
    static void testCreateWishlistEvent_Success() {
        // Build request body
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'customer_ids' => new Map<String, Object>{ 'email_id' => 'test@example.com' },
            'properties' => new Map<String, Object>{
                'product_id' => 'P001',
                'variant_id' => 'V001',
                'variant_info' => 'Color: Red, Size: M',
                'product_name' => 'Red Shirt',
                'product_price' => 49.99,
                'product_quantity' => 2,
                'product_url' => 'https://example.com/product/red-shirt',
                'image_url' => 'https://example.com/product/red-shirt.jpg',
                'variant_sku' => 'SKU123'
            },
            'timestamp' => '2025-04-29T23:17:39.000Z',
            'event_type' => 'add_to_wishlist'
        });

        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf(jsonBody);
        RestContext.request.httpMethod = 'POST';
        RestContext.request.addHeader('X-Access-Token', 'test-token');

        Test.startTest();
        WishlistEventService.createEvent();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        WishlistEventService.ApiResponse result =
            (WishlistEventService.ApiResponse)JSON.deserialize(
                RestContext.response.responseBody.toString(),
                WishlistEventService.ApiResponse.class
            );

        System.assertEquals(true, result.success);
        System.assertEquals(200, result.statusCode);
        System.assert(result.message.contains('Wishlist Event created'));

        List<Wishlist_Event__c> events = [SELECT Id, Product_Name__c FROM Wishlist_Event__c];
        System.assertEquals(1, events.size());
    }

    @isTest
    static void testMissingTokenHeader_Throws401() {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.httpMethod = 'POST';
        RestContext.request.requestBody = Blob.valueOf('{}');

        Test.startTest();
        WishlistEventService.createEvent();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
        System.assert(RestContext.response.responseBody.toString().contains('X-Access-Token'));
    }

    @isTest
    static void testInvalidTokenHeader_Throws401() {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.httpMethod = 'POST';
        RestContext.request.addHeader('X-Access-Token', 'wrong-token');
        RestContext.request.requestBody = Blob.valueOf('{}');

        Test.startTest();
        WishlistEventService.createEvent();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
        System.assert(RestContext.response.responseBody.toString().contains('unauthorized token'));
    }

    @isTest
    static void testMissingFields_Throws400() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'customer_ids' => new Map<String, Object>{ 'email_id' => 'test@example.com' },
            'properties' => new Map<String, Object>{},
            'timestamp' => '2025-04-29T23:17:39.000Z',
            'event_type' => 'add_to_wishlist'
        });

        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf(jsonBody);
        RestContext.request.httpMethod = 'POST';
        RestContext.request.addHeader('X-Access-Token', 'test-token');

        Test.startTest();
        WishlistEventService.createEvent();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(RestContext.response.responseBody.toString().contains('Missing required fields'));
    }

    @isTest
    static void testInvalidJson_Throws400() {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf('invalid json');
        RestContext.request.httpMethod = 'POST';
        RestContext.request.addHeader('X-Access-Token', 'test-token');

        Test.startTest();
        WishlistEventService.createEvent();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(RestContext.response.responseBody.toString().contains('Invalid request payload'));
    }
}