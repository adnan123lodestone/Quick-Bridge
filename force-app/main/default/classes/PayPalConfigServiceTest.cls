@IsTest
private class PayPalConfigServiceTest {
  @IsTest
  static void normalizedConfigIsPreferredOverLegacyDefaults() {
    Connector_Instance__c instanceRecord = createPayPalInstance(true, Date.today().addDays(30));
    insertValue(instanceRecord, 'PayPal_ClientId__c', 'test_client_id', false);
    insertValue(instanceRecord, 'WebhookId__c', 'WH-TEST-123', false);
    insertValue(instanceRecord, 'PayPal_UseSandbox__c', 'false', false);

    PayPalConfigService.Config config = PayPalConfigService.getConfig();

    System.assertEquals(true, config.fromNormalizedConfig);
    System.assertEquals('test_client_id', config.clientId);
    System.assertEquals('WH-TEST-123', config.webhookId);
    System.assertEquals(false, config.useSandbox);
    System.assertEquals(true, config.active);
  }

  @IsTest
  static void getWebhookIdReturnsIdFromConfig() {
    Connector_Instance__c instanceRecord = createPayPalInstance(true, Date.today().addDays(30));
    insertValue(instanceRecord, 'WebhookId__c', 'WH-NORMALIZED-456', false);

    String webhookId = PayPalConfigService.getWebhookId();

    System.assertEquals('WH-NORMALIZED-456', webhookId);
  }

  @IsTest
  static void getUseSandboxReturnsValueFromConfig() {
    Connector_Instance__c instanceRecord = createPayPalInstance(true, Date.today().addDays(30));
    insertValue(instanceRecord, 'PayPal_UseSandbox__c', 'true', false);

    Boolean useSandbox = PayPalConfigService.getUseSandbox();

    System.assertEquals(true, useSandbox);
  }

  @IsTest
  static void inactiveAndExpiredNormalizedConfigAreNotActive() {
    Connector_Instance__c inactiveInstance = createPayPalInstance(false, Date.today().addDays(30));
    insertValue(inactiveInstance, 'PayPal_ClientId__c', 'client_inactive', false);

    PayPalConfigService.Config inactiveConfig = PayPalConfigService.getConfig();
    System.assertEquals(false, inactiveConfig.active);

    delete [SELECT Id FROM Connector_Config_Value__c WHERE Connector_Key__c = 'paypal'];
    delete inactiveInstance;

    Connector_Instance__c expiredInstance = createPayPalInstance(true, Date.today().addDays(-1));
    insertValue(expiredInstance, 'PayPal_ClientId__c', 'client_expired', false);

    PayPalConfigService.Config expiredConfig = PayPalConfigService.getConfig();
    System.assertEquals(false, expiredConfig.active);
    System.assertEquals(Date.today().addDays(-1), expiredConfig.endDate);
  }

  @IsTest
  static void testConfigOverrideIsReturnedWhenSet() {
    PayPalConfigService.Config injected = new PayPalConfigService.Config();
    injected.active = true;
    injected.clientId = 'override_client_id';
    injected.webhookId = 'WH-OVERRIDE';
    injected.useSandbox = false;
    injected.fromNormalizedConfig = false;
    PayPalConfigService.testConfig = injected;

    PayPalConfigService.Config result = PayPalConfigService.getConfig();

    System.assertEquals('override_client_id', result.clientId);
    System.assertEquals('WH-OVERRIDE', result.webhookId);
    System.assertEquals(false, result.useSandbox);
  }

  @IsTest
  static void defaultTestConfigIsReturnedWhenNoNormalizedOrOverrideExists() {
    PayPalConfigService.Config config = PayPalConfigService.getConfig();

    System.assertNotEquals(null, config);
    System.assertEquals(true, config.active);
    System.assertNotEquals(null, config.webhookId);
  }

  private static Connector_Instance__c createPayPalInstance(Boolean active, Date expiryDate) {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'PayPal',
      Connector_Key__c = 'paypal',
      Connector_Label__c = 'PayPal',
      Active__c = active,
      Environment__c = active ? 'Production' : 'Sandbox',
      Entitlement_Status__c = active ? 'Active' : 'Inactive',
      Expiry_Date__c = expiryDate,
      Health_Status__c = 'Unknown'
    );
    insert instanceRecord;
    return instanceRecord;
  }

  private static void insertValue(
    Connector_Instance__c instanceRecord,
    String fieldKey,
    String value,
    Boolean isSecretReference
  ) {
    insert new Connector_Config_Value__c(
      Name = 'paypal:' + fieldKey,
      Connector_Instance__c = instanceRecord.Id,
      Connector_Key__c = 'paypal',
      Field_Key__c = fieldKey,
      Value__c = value,
      Is_Secret_Reference__c = isSecretReference
    );
  }
}