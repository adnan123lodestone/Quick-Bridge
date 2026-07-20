@IsTest
private class QuickBridgeRuntimeGatewayServiceTest {

    @testSetup
    static void setupTestData() {
        Integration_Entitlement__c cacheRecord = new Integration_Entitlement__c(
            Cache_Key__c = 'checkout',
            Name = 'Checkout Entitlement',
            Product_Key__c = 'checkout',
            Status__c = 'Active',
            Raw_Response__c = '{"status":"Success","activeGateways":["stripe","paypal"]}',
            Expires_At__c = System.now().addMinutes(15)
        );
        insert cacheRecord;
    }

    @IsTest
    static void testGetActiveGatewaysForCheckout() {
        Test.startTest();
        String result = QuickBridgeRuntimeGatewayService.getActiveGatewaysForCheckout();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.contains('Success'));
        System.assert(result.contains('stripe'));
    }

    @IsTest
    static void testIsClientAuthorized() {
        Test.startTest();
        Boolean isAuthorized = QuickBridgeRuntimeGatewayService.isClientAuthorized('stripe');
        Boolean isNotAuthorized = QuickBridgeRuntimeGatewayService.isClientAuthorized('unknown_gateway');
        Test.stopTest();

        System.assertEquals(true, isAuthorized);
        System.assertEquals(false, isNotAuthorized);
    }
}