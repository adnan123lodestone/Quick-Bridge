public with sharing class StripeConfigService {
  private static final String CONNECTOR_KEY = 'stripe';
  private static final String TEST_WEBHOOK_SIGNING_SECRET = 'whsec_test_inventorymagic';

  public class Config {
    public Boolean active;
    public Boolean useSandbox;
    public String publishableKey;
    public String webhookSigningSecret;
    public Date startDate;
    public Date endDate;
    public Boolean fromNormalizedConfig;
    public Boolean fromLegacyConfig;
  }

  @TestVisible
  static Config testConfig;
  @TestVisible
  static Boolean useLegacyFallbackInTests = false;
  @TestVisible
  static Boolean skipQuickbridgeLegacyInTests = false;

  public static Config getConfig() {
    if (Test.isRunningTest() && testConfig != null) {
      return cloneConfig(testConfig);
    }

    Config normalizedConfig = getNormalizedConfig();
    if (normalizedConfig != null) {
      return normalizedConfig;
    }

    if (Test.isRunningTest() && useLegacyFallbackInTests != true) {
      return getDefaultTestConfig();
    }

    Config quickbridgeConfig = Test.isRunningTest() && skipQuickbridgeLegacyInTests == true
      ? null
      : getQuickbridgeLegacyConfig();
    if (quickbridgeConfig != null) {
      return quickbridgeConfig;
    }

    Config stripeConfig = getStripeLegacyConfig();
    if (stripeConfig != null) {
      return stripeConfig;
    }

    throw new AuraHandledException('Stripe configuration record was not found.');
  }

  public static String getWebhookSigningSecret() {
    Config config = getConfig();
    return config == null ? null : config.webhookSigningSecret;
  }

  private static Config getNormalizedConfig() {
    ConnectorConfigService.ConnectorConfig rawConfig;
    try {
      rawConfig = ConnectorConfigService.getAuthoritativeConfig(CONNECTOR_KEY);
    } catch (Exception e) {
      rawConfig = null;
    }

    if (rawConfig == null || rawConfig.fromNormalizedConfig != true) {
      return null;
    }

    Config config = new Config();
    config.fromNormalizedConfig = true;
    config.fromLegacyConfig = false;
    config.active =
      rawConfig.active == true &&
      (rawConfig.expiryDate == null || rawConfig.expiryDate >= Date.today());
    config.publishableKey = getValue(
      rawConfig,
      new List<String>{ 'Stripe_Publishable_Key__c' }
    );
    config.webhookSigningSecret = getValue(
      rawConfig,
      new List<String>{
        'webhookSigningSecretRef',
        'Stripe_Webhook_Signing_Secret__c'
      }
    );
    config.useSandbox = parseBoolean(
      getValue(rawConfig, new List<String>{ 'Stripe_Use_Sandbox__c' })
    );
    config.startDate = parseDate(
      getValue(rawConfig, new List<String>{ 'Stripe_Start_Date__c' })
    );
    config.endDate = rawConfig.expiryDate == null
      ? parseDate(getValue(rawConfig, new List<String>{ 'Stripe_End_Date__c' }))
      : rawConfig.expiryDate;
    return config;
  }

  private static Config getQuickbridgeLegacyConfig() {
    Quickbridge_Config__mdt legacy;
    try {
      legacy = Quickbridge_Config__mdt.getInstance('Stripe');
    } catch (Exception e) {
      legacy = null;
    }
    if (legacy == null) {
      return null;
    }

    Config config = new Config();
    config.fromNormalizedConfig = false;
    config.fromLegacyConfig = true;
    config.active = legacy.Stripe_Active__c;
    config.publishableKey = legacy.Stripe_Publishable_Key__c;
    config.webhookSigningSecret = legacy.Stripe_Webhook_Signing_Secret__c;
    config.useSandbox = legacy.Stripe_Use_Sandbox__c;
    config.startDate = legacy.Stripe_Start_Date__c;
    config.endDate = legacy.Stripe_End_Date__c;
    return config;
  }

  private static Config getStripeLegacyConfig() {
    Stripe_Config__mdt legacy;
    try {
      legacy = Stripe_Config__mdt.getInstance('Default');
    } catch (Exception e) {
      legacy = null;
    }
    if (legacy == null) {
      return null;
    }

    Config config = new Config();
    config.fromNormalizedConfig = false;
    config.fromLegacyConfig = true;
    config.active = legacy.Active__c;
    config.publishableKey = legacy.PublishableKey__c;
    config.webhookSigningSecret = legacy.WebhookSigningSecret__c;
    config.useSandbox = legacy.UseSandbox__c;
    config.startDate = legacy.StartDate__c;
    config.endDate = legacy.EndDate__c;
    return config;
  }

  private static Config getDefaultTestConfig() {
    Config config = new Config();
    config.active = true;
    config.publishableKey = 'pk_test_123';
    config.webhookSigningSecret = TEST_WEBHOOK_SIGNING_SECRET;
    config.useSandbox = true;
    config.fromNormalizedConfig = false;
    config.fromLegacyConfig = false;
    return config;
  }

  private static Config cloneConfig(Config source) {
    if (source == null) {
      return null;
    }
    Config copy = new Config();
    copy.active = source.active;
    copy.publishableKey = source.publishableKey;
    copy.webhookSigningSecret = source.webhookSigningSecret;
    copy.useSandbox = source.useSandbox;
    copy.startDate = source.startDate;
    copy.endDate = source.endDate;
    copy.fromNormalizedConfig = source.fromNormalizedConfig;
    copy.fromLegacyConfig = source.fromLegacyConfig;
    return copy;
  }

  private static String getValue(
    ConnectorConfigService.ConnectorConfig config,
    List<String> keys
  ) {
    if (config == null || config.values == null || keys == null) {
      return null;
    }
    for (String key : keys) {
      if (config.values.containsKey(key) && String.isNotBlank(config.values.get(key))) {
        return config.values.get(key);
      }
    }
    return null;
  }

  private static Boolean parseBoolean(String value) {
    if (String.isBlank(value)) {
      return false;
    }
    return value.equalsIgnoreCase('true') ||
      value.equalsIgnoreCase('yes') ||
      value == '1';
  }

  private static Date parseDate(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return Date.valueOf(value);
    } catch (Exception e) {
      throw new AuraHandledException('Invalid Stripe connector config date: ' + value);
    }
  }
}