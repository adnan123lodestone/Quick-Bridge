@IsTest
private class PaymentMetadataServiceTest {

    @IsTest
    static void testGetPaymentMetadataConfigsSuccess() {
        Test.startTest();
        List<PaymentMetadataService.MetadataConfig> configs = PaymentMetadataService.getPaymentMetadataConfigs();
        Test.stopTest();

        System.assertNotEquals(0, configs.size(), 'Configurations should be returned for supported providers.');

        PaymentMetadataService.MetadataConfig authNet;
        for (PaymentMetadataService.MetadataConfig c : configs) {
            if (c.provider == 'authorizenet') authNet = c;
        }

        System.assertNotEquals(null, authNet, 'AuthorizeNet config should exist.');
        System.assertEquals('Authorize.Net', authNet.label);
    }

    @IsTest
    static void testUpdatePaymentMetadataSuccess() {
        Map<String, Object> fields = new Map<String, Object>{
            'Stripe_Publishable_Key__c' => 'test_key_123',
            'Stripe_Active__c' => true
        };

        Test.startTest();
        PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.updatePaymentMetadata(
            'stripe', JSON.serialize(fields)
        );
        Test.stopTest();

        System.assertEquals(true, res.success, 'The update request should be processed successfully.');
    }

    @IsTest
    static void testUpdatePaymentMetadataInvalidProvider() {
        Map<String, Object> fields = new Map<String, Object>();

        Test.startTest();
        PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.updatePaymentMetadata(
            'invalid_gateway', JSON.serialize(fields)
        );
        Test.stopTest();

        System.assertEquals(false, res.success, 'Update should fail for unknown providers.');
        System.assert(res.message.contains('Unsupported payment provider'), 'Error message should indicate unsupported provider.');
    }

    @IsTest
    static void testUpdatePaymentMetadataNullRequest() {
        Test.startTest();
        PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.updatePaymentMetadata(null, null);
        Test.stopTest();

        System.assertEquals(false, res.success);
        System.assertNotEquals(null, res.message);
    }
}