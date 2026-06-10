@IsTest
private class AuthorizeNetConfigServiceTest {
  @IsTest
  static void normalizedConfigIsPreferredOverLegacyDefaults() {
    Connector_Instance__c instanceRecord = createAuthorizeNetInstance(true, Date.today().addDays(30));
    insertValue(instanceRecord, 'AuthorizeNet_API_Login_ID__c', 'test_login_id', false);
    insertValue(instanceRecord, 'AuthorizeNet_Public_Client_Key__c', 'test_public_key', false);
    insertValue(instanceRecord, 'AuthorizeNet_Webhook_Signing_Key__c', 'test_signing_key', true);
    insertValue(instanceRecord, 'AuthorizeNet_Use_Sandbox__c', 'false', false);

    AuthorizeNetConfigService.Config config = AuthorizeNetConfigService.getConfig();

    System.assertEquals(true, config.fromNormalizedConfig);
    System.assertEquals('test_login_id', config.apiLoginId);
    System.assertEquals('test_public_key', config.publicClientKey);
    System.assertEquals('test_signing_key', config.webhookSigningKey);
    System.assertEquals(false, config.useSandbox);
    System.assertEquals(true, config.active);
  }

  @IsTest
  static void getWebhookSigningKeyReturnsKeyFromConfig() {
    Connector_Instance__c instanceRecord = createAuthorizeNetInstance(true, Date.today().addDays(30));
    insertValue(instanceRecord, 'AuthorizeNet_Webhook_Signing_Key__c', 'hmac_signing_key', true);

    String signingKey = AuthorizeNetConfigService.getWebhookSigningKey();

    System.assertEquals('hmac_signing_key', signingKey);
  }

  @IsTest
  static void inactiveAndExpiredNormalizedConfigAreNotActive() {
    Connector_Instance__c inactiveInstance = createAuthorizeNetInstance(false, Date.today().addDays(30));
    insertValue(inactiveInstance, 'AuthorizeNet_API_Login_ID__c', 'login_inactive', false);

    AuthorizeNetConfigService.Config inactiveConfig = AuthorizeNetConfigService.getConfig();
    System.assertEquals(false, inactiveConfig.active);

    delete [SELECT Id FROM Connector_Config_Value__c WHERE Connector_Key__c = 'authorizenet'];
    delete inactiveInstance;

    Connector_Instance__c expiredInstance = createAuthorizeNetInstance(true, Date.today().addDays(-1));
    insertValue(expiredInstance, 'AuthorizeNet_API_Login_ID__c', 'login_expired', false);

    AuthorizeNetConfigService.Config expiredConfig = AuthorizeNetConfigService.getConfig();
    System.assertEquals(false, expiredConfig.active);
    System.assertEquals(Date.today().addDays(-1), expiredConfig.endDate);
  }

  @IsTest
  static void testConfigOverrideIsReturnedWhenSet() {
    AuthorizeNetConfigService.Config injected = new AuthorizeNetConfigService.Config();
    injected.active = true;
    injected.apiLoginId = 'override_login';
    injected.webhookSigningKey = 'override_key';
    injected.useSandbox = false;
    injected.fromNormalizedConfig = false;
    injected.fromLegacyConfig = false;
    AuthorizeNetConfigService.testConfig = injected;

    AuthorizeNetConfigService.Config result = AuthorizeNetConfigService.getConfig();

    System.assertEquals('override_login', result.apiLoginId);
    System.assertEquals('override_key', result.webhookSigningKey);
    System.assertEquals(false, result.useSandbox);
  }

  @IsTest
  static void legacyFallbackCanBeExercisedWhenNoNormalizedConfigExists() {
    AuthorizeNetConfigService.useLegacyFallbackInTests = true;

    AuthorizeNetConfigService.Config config = AuthorizeNetConfigService.getConfig();

    System.assertNotEquals(null, config);
    System.assertEquals(false, config.fromNormalizedConfig);
    System.assertEquals(true, config.fromLegacyConfig);
  }

  @IsTest
  static void gatewayLegacyFallbackCanBeExercisedWhenQuickbridgeIsSkipped() {
    AuthorizeNetConfigService.useLegacyFallbackInTests = true;
    AuthorizeNetConfigService.skipQuickbridgeLegacyInTests = true;

    AuthorizeNetConfigService.Config config = AuthorizeNetConfigService.getConfig();

    System.assertNotEquals(null, config);
    System.assertEquals(false, config.fromNormalizedConfig);
    System.assertEquals(true, config.fromLegacyConfig);
  }

  @IsTest
  static void defaultTestConfigIsReturnedWhenNoNormalizedOrOverrideExists() {
    AuthorizeNetConfigService.Config config = AuthorizeNetConfigService.getConfig();

    System.assertNotEquals(null, config);
    System.assertEquals(true, config.active);
    System.assertNotEquals(null, config.webhookSigningKey);
  }

  private static Connector_Instance__c createAuthorizeNetInstance(Boolean active, Date expiryDate) {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'Authorize.Net',
      Connector_Key__c = 'authorizenet',
      Connector_Label__c = 'Authorize.Net',
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
      Name = 'authorizenet:' + fieldKey,
      Connector_Instance__c = instanceRecord.Id,
      Connector_Key__c = 'authorizenet',
      Field_Key__c = fieldKey,
      Value__c = value,
      Is_Secret_Reference__c = isSecretReference
    );
  }
}