@IsTest
private class PaymentMetadataServiceTest {

  // Data setup to ensure config methods and expiry calculations have real data to process
  @TestSetup
  static void setupData() {
    Connector_Instance__c inst = new Connector_Instance__c(
      Name = 'Stripe',
      Connector_Key__c = 'stripe',
      // Set to 3 days to hit the "warning" expiry branch and notification logic
      Expiry_Date__c = Date.today().addDays(3) 
    );
    insert inst;

    Connector_Config_Value__c val1 = new Connector_Config_Value__c(
      Connector_Instance__c = inst.Id,
      Field_Key__c = 'Stripe_Publishable_Key__c',
      Value__c = 'pk_test_123',
      Is_Secret_Reference__c = false,
      Connector_Key__c = 'stripe'
    );
    Connector_Config_Value__c val2 = new Connector_Config_Value__c(
      Connector_Instance__c = inst.Id,
      Field_Key__c = 'stripe_secret_key',
      Value__c = 'sk_test_123',
      Is_Secret_Reference__c = true,
      Connector_Key__c = 'stripe'
    );
    insert new List<Connector_Config_Value__c>{ val1, val2 };
  }

  @IsTest
  static void testGetPaymentMetadataConfigsSuccess() {
    Test.startTest();
    List<PaymentMetadataService.MetadataConfig> configs = PaymentMetadataService.getPaymentMetadataConfigs();
    Test.stopTest();

    System.assertNotEquals(0, configs.size(), 'Configurations should be returned for supported providers.');
  }

  @IsTest
  static void testGetConnectorConfigs() {
    Test.startTest();
    List<PaymentMetadataService.MetadataConfig> configs = PaymentMetadataService.getConnectorConfigs();
    Test.stopTest();

    System.assertNotEquals(null, configs, 'Configs list should not be null.');
    System.assert(configs.size() > 0, 'Configs list should contain elements.');

    Boolean foundStripe = false;
    for (PaymentMetadataService.MetadataConfig cfg : configs) {
      if (cfg.provider == 'stripe') {
        foundStripe = true;
        System.assertNotEquals(null, cfg.fields, 'Fields map should be initialized.');
      }
    }
    System.assert(foundStripe, 'Stripe config should be processed and returned from test data.');
  }

  @IsTest
  static void testSaveConnectorConfig() {
    String token = sessionToken();
    Map<String, Object> fields = new Map<String, Object>{
      'Stripe_Publishable_Key__c' => 'pk_test_updated',
      'Stripe_Active__c' => true // Should be skipped inherently by logic
    };

    Test.startTest();
    PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.saveConnectorConfig(
      'stripe', 
      JSON.serialize(fields), 
      token
    );
    Test.stopTest();

    System.assertEquals(true, res.success, 'Save connector config should succeed.');
    System.assert(res.message.contains('Configuration saved'), 'Success message should be returned.');
  }

  @IsTest
  static void testMetadataDeployQueueable() {
    Map<String, Object> fieldValues = new Map<String, Object>{
      'Test_Field__c' => 'TestValue',
      'Test_Date__c' => '2026-01-01'
    };
    List<String> allowedFields = new List<String>{'Test_Field__c', 'Test_Date__c'};

    Test.startTest();
    PaymentMetadataService.MetadataDeployQueueable queueable = new PaymentMetadataService.MetadataDeployQueueable(
      'stripe', fieldValues, allowedFields, 'Stripe_Config', 'Connector_Config__mdt'
    );
    
    Boolean exceptionCaught = false;
    try {
      queueable.execute(null);
    } catch (Exception e) {
      exceptionCaught = true;
      System.assert(e.getMessage().contains('Metadata cannot be deployed'), 'Expected metadata restriction error in test context');
    }
    Test.stopTest();

    System.assert(exceptionCaught, 'Exception must be caught to cover the catch block successfully.');
  }
  
  @IsTest
  static void testCheckIntegrationExpiryWithExpiringConfig() {
    Test.startTest();
    PaymentMetadataService.IntegrationExpiryAlert alert = PaymentMetadataService.checkIntegrationExpiry('stripe');
    Test.stopTest();

    System.assertEquals(true, alert.shouldAlert, 'Alert should be triggered for config expiring in 3 days.');
    System.assertEquals(3, alert.daysUntilExpiry, 'Days until expiry should be correctly calculated.');
    System.assertEquals('warning', alert.variant, 'Variant should be warning for future expiry.');
    System.assertNotEquals(null, alert.message, 'Alert message should be generated.');
  }

  @IsTest
  static void testUpdatePaymentMetadataSuccess() {
    String token = sessionToken();
    Map<String, Object> fields = new Map<String, Object>{
      'Stripe_Publishable_Key__c' => 'test_key_123',
      'Stripe_Active__c' => true
    };

    Test.startTest();
    PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.updatePaymentMetadata(
      'stripe',
      JSON.serialize(fields),
      token
    );
    Test.stopTest();

    System.assertEquals(true, res.success, 'The update request should be processed successfully.');
  }

  @IsTest
  static void testUpdatePaymentMetadataInvalidProvider() {
    String token = sessionToken();
    Map<String, Object> fields = new Map<String, Object>();

    Test.startTest();
    PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.updatePaymentMetadata(
      'invalid_gateway',
      JSON.serialize(fields),
      token
    );
    Test.stopTest();

    System.assertEquals(false, res.success, 'Update should fail for unknown providers.');
    System.assertNotEquals(null, res.message, 'Error message should be populated for unsupported providers.');
  }

  @IsTest
  static void testUpdatePaymentMetadataNullRequest() {
    String token = sessionToken();
    Test.startTest();
    PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.updatePaymentMetadata(
      null,
      null,
      token
    );
    Test.stopTest();

    System.assertEquals(false, res.success);
    System.assertNotEquals(null, res.message);
  }

  @IsTest
  static void testUpdatePaymentMetadataForSupportedProviders() {
    String token = sessionToken();
    Map<String, Map<String, Object>> providerFields = new Map<String, Map<String, Object>>{
      'authorizenet' => new Map<String, Object>{
        'Company_Name__c' => 'TLG',
        'AuthorizeNet_API_Login_ID__c' => 'login'
      },
      'paypal' => new Map<String, Object>{
        'Company_Name__c' => 'TLG',
        'PayPal_ClientId__c' => 'client'
      }
    };

    Test.startTest();
    for (String provider : providerFields.keySet()) {
      PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.updatePaymentMetadata(
        provider,
        JSON.serialize(providerFields.get(provider)),
        token
      );
      System.assertEquals(true, res.success, provider + ' should be accepted.');
      System.assert(res.message.contains('Configuration saved'));
    }
    Test.stopTest();
  }

  @IsTest
  static void testConfigPanelPreferencesCanBeReadAndUpdated() {
    String token = sessionToken();
    Test.startTest();
    PaymentMetadataService.ConfigPanelPreferences preferences = PaymentMetadataService.getConfigPanelPreferences();
    PaymentMetadataService.MetadataUpdateResponse updateResponse = PaymentMetadataService.updateAvailableProductsVisible(
      false,
      token
    );
    Test.stopTest();

    System.assertNotEquals(null, preferences, 'Preferences response should always be returned.');
    System.assertEquals(true, updateResponse.success, 'Preference update should be accepted.');
  }

  @IsTest
  static void testCheckIntegrationExpiryRejectsInvalidProvider() {
    Test.startTest();
    PaymentMetadataService.IntegrationExpiryAlert alert = PaymentMetadataService.checkIntegrationExpiry(
      'bad_provider'
    );
    Test.stopTest();

    System.assertEquals(false, alert.shouldAlert);
    System.assertEquals('error', alert.variant);
    System.assertNotEquals(null, alert.message);
  }

  @IsTest
  static void testSendProductRenewalRequestSuccess() {
    String token = sessionToken();
    Test.startTest();
    PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.sendProductRenewalRequest(
      new List<String>{ 'qbo', 'stripe' },
      new List<String>{ 'shopify' },
      token
    );
    Test.stopTest();

    System.assertEquals(true, res.success, 'The renewal request email should be sent.');
    System.assert(res.message.contains('adnan@thelodestonegroup.com'), 'The response should identify the recipient.');
  }

  @IsTest
  static void testSendProductRenewalRequestRequiresSelection() {
    String token = sessionToken();
    Test.startTest();
    PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.sendProductRenewalRequest(
      new List<String>(),
      new List<String>(),
      token
    );
    Test.stopTest();

    System.assertEquals(false, res.success, 'At least one selected product should be required.');
    System.assert(res.message.contains('Select at least one product'));
  }

  @IsTest
  static void testSendProductRenewalRequestRejectsUnsupportedProduct() {
    String token = sessionToken();
    Test.startTest();
    PaymentMetadataService.MetadataUpdateResponse res = PaymentMetadataService.sendProductRenewalRequest(
      new List<String>{ 'unknown_product' },
      null,
      token
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

  @IsTest
  static void testMutationMethodsRequireAdminSession() {
    Test.startTest();
    PaymentMetadataService.MetadataUpdateResponse updateResponse = PaymentMetadataService.updatePaymentMetadata(
      'stripe', '{}', null
    );
    PaymentMetadataService.MetadataUpdateResponse preferenceResponse = PaymentMetadataService.updateAvailableProductsVisible(
      true, null
    );
    PaymentMetadataService.MetadataUpdateResponse renewalResponse = PaymentMetadataService.sendProductRenewalRequest(
      new List<String>{ 'stripe' }, null, null
    );
    Test.stopTest();

    System.assertEquals(false, updateResponse.success);
    System.assert(updateResponse.message.toLowerCase().contains('session'));
    System.assertEquals(false, preferenceResponse.success);
    System.assert(preferenceResponse.message.toLowerCase().contains('session'));
    System.assertEquals(false, renewalResponse.success);
    System.assert(renewalResponse.message.toLowerCase().contains('session'));
  }

  private static String sessionToken() {
    return QuickBridgeAdminSessionService.createSession(
        'admin@example.com',
        System.now().addHours(1)
      )
      .sessionToken;
  }
}