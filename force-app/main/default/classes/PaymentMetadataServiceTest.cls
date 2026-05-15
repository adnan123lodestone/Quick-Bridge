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

    @IsTest
    static void testUpdatePaymentMetadataForSupportedProviders() {
        Map<String, Map<String, Object>> providerFields = new Map<String, Map<String, Object>>{
            'authorizenet' => new Map<String, Object>{
                'Company_Name__c' => 'TLG',
                'AuthorizeNet_API_Login_ID__c' => 'login',
                'AuthorizeNet_Public_Client_Key__c' => 'client',
                'AuthorizeNet_Webhook_Signing_Key__c' => 'webhook',
                'AuthorizeNet_Active__c' => true,
                'AuthorizeNet_Use_Sandbox__c' => true,
                'AuthorizeNet_Start_Date__c' => '2026-01-01',
                'AuthorizeNet_End_Date__c' => '2026-12-31'
            },
            'paypal' => new Map<String, Object>{
                'Company_Name__c' => 'TLG',
                'PayPal_ClientId__c' => 'client',
                'PayPal_Active__c' => true,
                'PayPal_UseSandbox__c' => true,
                'PayPal_StartDate__c' => '2026-01-01',
                'PayPal_EndDate__c' => '2026-12-31'
            },
            'shopify' => new Map<String, Object>{
                'Company_Name__c' => 'TLG',
                'Shopify_Store_URL__c' => 'https://example.myshopify.com',
                'Shopify_Access_Token__c' => 'token',
                'Shopify_API_Key__c' => 'key',
                'Shopify_API_Secret__c' => 'secret',
                'Shopify_Is_Active__c' => true,
                'Shopify_Start_Date__c' => '2026-01-01',
                'Shopify_End_Date__c' => '2026-12-31'
            },
            'qbo' => new Map<String, Object>{
                'Company_Name__c' => 'TLG',
                'QuickBooks_Realm_ID__c' => 'realm',
                'QuickBooks_Is_Active__c' => true,
                'QuickBooks_Start_Date__c' => '2026-01-01',
                'QuickBooks_End_Date__c' => '2026-12-31'
            },
            'fedex' => new Map<String, Object>{
                'FedEx_Client_Id__c' => 'client',
                'FedEx_Client_Secret__c' => 'secret',
                'FedEx_Account_Number__c' => '123',
                'FedEx_Environment__c' => 'Sandbox',
                'FedEx_Default_Service_Type__c' => 'FEDEX_GROUND',
                'FedEx_Default_Packaging_Type__c' => 'YOUR_PACKAGING',
                'FedEx_Default_Pickup_Type__c' => 'DROPOFF_AT_FEDEX_LOCATION',
                'FedEx_Active__c' => true,
                'FedEx_Start_Date__c' => '2026-01-01',
                'FedEx_End_Date__c' => '2026-12-31'
            },
            'ups' => new Map<String, Object>{
                'UPS_Client_Id__c' => 'client',
                'UPS_Client_Secret__c' => 'secret',
                'UPS_Account_Number__c' => '123',
                'UPS_Environment__c' => 'Sandbox',
                'UPS_Default_Service_Code__c' => '03',
                'UPS_Active__c' => true,
                'UPS_Start_Date__c' => '2026-01-01',
                'UPS_End_Date__c' => '2026-12-31'
            }
        };

        Test.startTest();
        for (String provider : providerFields.keySet()) {
            PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.updatePaymentMetadata(
                provider,
                JSON.serialize(providerFields.get(provider))
            );
            System.assertEquals(true, res.success, provider + ' should be accepted.');
            System.assert(res.message.contains('Configuration save initiated'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testConfigPanelPreferencesCanBeReadAndUpdated() {
        Test.startTest();
        PaymentMetadataService.ConfigPanelPreferences preferences = PaymentMetadataService.getConfigPanelPreferences();
        PaymentMetadataService.MetadataUpdateResponse updateResponse = PaymentMetadataService.updateAvailableProductsVisible(false);
        Test.stopTest();

        System.assertNotEquals(null, preferences, 'Preferences response should always be returned.');
        System.assertNotEquals(null, preferences.availableProductsVisible, 'Available Products preference should have a default.');
        System.assertEquals(true, updateResponse.success, 'Preference update should be accepted.');
    }

    @IsTest
    static void testCheckIntegrationExpiryForSupportedProviders() {
        List<String> providers = new List<String>{ 'authorizenet', 'stripe', 'paypal', 'shopify', 'qbo', 'fedex', 'ups' };

        Test.startTest();
        for (String provider : providers) {
            PaymentMetadataService.IntegrationExpiryAlert alert = PaymentMetadataService.checkIntegrationExpiry(provider);
            System.assertNotEquals(null, alert, provider + ' should return an alert wrapper.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCheckIntegrationExpiryRejectsInvalidProvider() {
        Test.startTest();
        PaymentMetadataService.IntegrationExpiryAlert alert = PaymentMetadataService.checkIntegrationExpiry('bad_provider');
        Test.stopTest();

        System.assertEquals(false, alert.shouldAlert);
        System.assertEquals('error', alert.variant);
        System.assertNotEquals(null, alert.message);
    }

    @IsTest
    static void testSendProductRenewalRequestSuccess() {
        Test.startTest();
        PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.sendProductRenewalRequest(
            new List<String>{ 'qbo', 'stripe' },
            new List<String>{ 'shopify' }
        );
        Test.stopTest();

        System.assertEquals(true, res.success, 'The renewal request email should be sent.');
        System.assert(res.message.contains('adnan@thelodestonegroup.com'), 'The response should identify the recipient.');
    }

    @IsTest
    static void testSendProductRenewalRequestRequiresSelection() {
        Test.startTest();
        PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.sendProductRenewalRequest(
            new List<String>(),
            new List<String>()
        );
        Test.stopTest();

        System.assertEquals(false, res.success, 'At least one selected product should be required.');
        System.assert(res.message.contains('Select at least one product'));
    }

    @IsTest
    static void testSendProductRenewalRequestRejectsUnsupportedProduct() {
        Test.startTest();
        PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.sendProductRenewalRequest(
            new List<String>{ 'unknown_product' },
            null
        );
        Test.stopTest();

        System.assertEquals(false, res.success, 'Unsupported product keys should fail validation.');
        System.assert(res.message.contains('Unsupported product'));
    }

    @IsTest
    static void testRenewalHelperMethods() {
        List<String> labels = PaymentMetadataService.resolveProviderLabels(
            new List<String>{ 'qbo', 'QBO', ' stripe ', null, '' }
        );
        System.assertEquals(new List<String>{ 'QuickBooks', 'Stripe' }, labels);

        String expiredMessage = PaymentMetadataService.buildExpiryMessage('QuickBooks', Date.today().addDays(-1), -1);
        String todayMessage = PaymentMetadataService.buildExpiryMessage('QuickBooks', Date.today(), 0);
        String futureMessage = PaymentMetadataService.buildExpiryMessage('QuickBooks', Date.today().addDays(2), 2);
        System.assert(expiredMessage.contains('expired on'));
        System.assert(todayMessage.contains('expires today'));
        System.assert(futureMessage.contains('expires in 2 days'));

        String body = PaymentMetadataService.buildProductRenewalRequestEmailBody(
            new List<String>{ 'QuickBooks' },
            new List<String>{ 'Shopify', 'Stripe' }
        );
        System.assert(body.contains('Renewal for existing subscriptions'));
        System.assert(body.contains('- QuickBooks'));
        System.assert(body.contains('- Shopify'));

        List<String> emptyLines = PaymentMetadataService.formatProductLines(new List<String>());
        System.assertEquals(new List<String>{ '- None selected' }, emptyLines);
    }

    @IsTest
    static void testRenewalNotificationHelpersHandleAlert() {
        PaymentMetadataService.IntegrationExpiryAlert alert = new PaymentMetadataService.IntegrationExpiryAlert();
        alert.title = 'Integration Expiring Soon';
        alert.message = 'QuickBooks expires soon.';
        alert.providerLabel = 'QuickBooks';
        alert.expiryDate = Date.today().addDays(1);
        alert.daysUntilExpiry = 1;

        Test.startTest();
        List<User> admins = PaymentMetadataService.getActiveSystemAdmins();
        PaymentMetadataService.sendRenewalEmailToSystemAdmins(alert);
        PaymentMetadataService.sendRenewalNotification(alert);
        Test.stopTest();

        System.assertNotEquals(null, admins, 'Admin query should return a list.');
    }
}