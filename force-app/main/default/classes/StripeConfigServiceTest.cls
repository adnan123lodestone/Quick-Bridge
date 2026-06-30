@IsTest
private class StripeConfigServiceTest {
  @IsTest
  static void normalizedConfigIsPreferredOverLegacyDefaults() {
    Connector_Instance__c instanceRecord = createStripeInstance(true, Date.today().addDays(30));
    insertValue(instanceRecord, 'Stripe_Publishable_Key__c', 'pk_normalized', false);
    insertValue(instanceRecord, 'Stripe_Webhook_Signing_Secret__c', 'whsec_alias', true);
    insertValue(instanceRecord, 'Stripe_Use_Sandbox__c', 'false', false);

    StripeConfigService.Config config = StripeConfigService.getConfig();

    System.assertEquals(true, config.fromNormalizedConfig);
    System.assertEquals('pk_normalized', config.publishableKey);
    System.assertEquals('whsec_alias', config.webhookSigningSecret);
    System.assertEquals(false, config.useSandbox);
    System.assertEquals(true, config.active);
  }

  @IsTest
  static void webhookSigningSecretRefWinsOverCompatibilityAlias() {
    Connector_Instance__c instanceRecord = createStripeInstance(true, Date.today().addDays(30));
    insertValue(instanceRecord, 'Stripe_Publishable_Key__c', 'pk_normalized', false);
    insertValue(instanceRecord, 'Stripe_Webhook_Signing_Secret__c', 'whsec_alias', true);
    insertValue(instanceRecord, 'webhookSigningSecretRef', 'whsec_reference', true);

    StripeConfigService.Config config = StripeConfigService.getConfig();

    System.assertEquals('whsec_reference', config.webhookSigningSecret);
    System.assertEquals('whsec_reference', StripeConfigService.getWebhookSigningSecret());
  }

  @IsTest
  static void inactiveAndExpiredNormalizedConfigAreNotActive() {
    Connector_Instance__c inactiveInstance = createStripeInstance(false, Date.today().addDays(30));
    insertValue(inactiveInstance, 'Stripe_Publishable_Key__c', 'pk_inactive', false);

    StripeConfigService.Config inactiveConfig = StripeConfigService.getConfig();
    System.assertEquals(false, inactiveConfig.active);

    delete [SELECT Id FROM Connector_Config_Value__c WHERE Connector_Key__c = 'stripe'];
    delete inactiveInstance;

    Connector_Instance__c expiredInstance = createStripeInstance(true, Date.today().addDays(-1));
    insertValue(expiredInstance, 'Stripe_Publishable_Key__c', 'pk_expired', false);

    StripeConfigService.Config expiredConfig = StripeConfigService.getConfig();
    System.assertEquals(false, expiredConfig.active);
    System.assertEquals(Date.today().addDays(-1), expiredConfig.endDate);
  }

  @IsTest
  static void missingPublishableKeyReturnsIncompleteClientConfig() {
    StripeConfigService.Config testConfig = new StripeConfigService.Config();
    testConfig.active = true;
    testConfig.useSandbox = true;
    testConfig.webhookSigningSecret = 'whsec_test';
    StripeConfigService.testConfig = testConfig;

    StripePaymentService.ClientConfigResponse response = StripePaymentService.getClientConfig();

    System.assertEquals(true, response.active);
    System.assertEquals(false, response.configured);
    System.assert(response.message.contains('Publishable Key'));
  }

  @IsTest
  static void inactiveAndExpiredConfigBlockClientAvailability() {
    StripeConfigService.Config inactiveConfig = new StripeConfigService.Config();
    inactiveConfig.active = false;
    inactiveConfig.publishableKey = 'pk_test';
    StripeConfigService.testConfig = inactiveConfig;

    StripePaymentService.ClientConfigResponse inactiveResponse = StripePaymentService.getClientConfig();
    System.assertEquals(false, inactiveResponse.active);
    System.assertEquals('Stripe is currently inactive.', inactiveResponse.message);

    StripeConfigService.Config expiredConfig = new StripeConfigService.Config();
    expiredConfig.active = true;
    expiredConfig.publishableKey = 'pk_test';
    expiredConfig.endDate = Date.today().addDays(-1);
    StripeConfigService.testConfig = expiredConfig;

    StripePaymentService.ClientConfigResponse expiredResponse = StripePaymentService.getClientConfig();
    System.assertEquals(false, expiredResponse.active);
    System.assertEquals('Stripe contract has expired.', expiredResponse.message);
  }

  @IsTest
  static void webhookVerificationUsesNormalizedSecret() {
    Connector_Instance__c instanceRecord = createStripeInstance(true, Date.today().addDays(30));
    insertValue(instanceRecord, 'Stripe_Publishable_Key__c', 'pk_normalized', false);
    insertValue(instanceRecord, 'webhookSigningSecretRef', 'whsec_normalized', true);

    String payload = '{"id":"evt_normalized","type":"payment_intent.payment_failed"}';
    RestRequest request = new RestRequest();
    request.requestURI = '/services/apexrest/payment-webhook/stripe';
    request.httpMethod = 'POST';
    request.addHeader('Content-Type', 'application/json');
    request.addHeader(
      'Stripe-Signature',
      buildStripeSignatureHeader(payload, 'whsec_normalized')
    );
    request.requestBody = Blob.valueOf(payload);
    RestContext.request = request;
    RestContext.response = new RestResponse();

    PaymentWebhookRestResource.WebhookResponse response = PaymentWebhookRestResource.handlePost();

    System.assertEquals(200, RestContext.response.statusCode);
    System.assertEquals(true, response.success);
    System.assertEquals(false, response.recordCreated);
  }

  private static Connector_Instance__c createStripeInstance(Boolean active, Date expiryDate) {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'Stripe',
      Connector_Key__c = 'stripe',
      Connector_Label__c = 'Stripe',
      Active__c = active,
      Environment__c = 'Sandbox',
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
      Name = 'stripe:' + fieldKey,
      Connector_Instance__c = instanceRecord.Id,
      Connector_Key__c = 'stripe',
      Field_Key__c = fieldKey,
      Value__c = value,
      Is_Secret_Reference__c = isSecretReference
    );
  }

  private static String buildStripeSignatureHeader(String payload, String signingSecret) {
    String timestamp = String.valueOf(Datetime.now().getTime() / 1000);
    String signedPayload = timestamp + '.' + payload;
    String signature = EncodingUtil.convertToHex(
      Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf(signedPayload),
        Blob.valueOf(signingSecret)
      )
    ).toLowerCase();
    return 't=' + timestamp + ',v1=' + signature;
  }
}