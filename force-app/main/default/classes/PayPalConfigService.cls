public with sharing class PayPalConfigService {
  private static final String CONNECTOR_KEY = 'paypal';
  private static final String TEST_WEBHOOK_ID = 'WH-TEST-QUICKBRIDGE';

  public class Config {
    public Boolean active;
    public Boolean useSandbox;
    public String clientId;
    public String webhookId;
    public Date startDate;
    public Date endDate;
    public Boolean fromNormalizedConfig;
  }

  @TestVisible
  static Config testConfig;

  public static Config getConfig() {
    if (Test.isRunningTest() && testConfig != null) {
      return cloneConfig(testConfig);
    }

    Config normalizedConfig = getNormalizedConfig();
    if (normalizedConfig != null) {
      return normalizedConfig;
    }

    if (Test.isRunningTest()) {
      return getDefaultTestConfig();
    }

    throw new AuraHandledException('PayPal configuration record was not found.');
  }

  public static String getWebhookId() {
    Config config = getConfig();
    return config == null ? null : config.webhookId;
  }

  public static Boolean getUseSandbox() {
    Config config = getConfig();
    return config != null && config.useSandbox == true;
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
    config.active =
      rawConfig.active == true &&
      (rawConfig.expiryDate == null || rawConfig.expiryDate >= Date.today());
    config.clientId = getValue(
      rawConfig,
      new List<String>{ 'PayPal_ClientId__c' }
    );
    config.webhookId = getValue(
      rawConfig,
      new List<String>{ 'WebhookId__c' }
    );
    config.useSandbox = parseBoolean(
      getValue(rawConfig, new List<String>{ 'PayPal_UseSandbox__c' })
    );
    config.startDate = parseDate(
      getValue(rawConfig, new List<String>{ 'PayPal_StartDate__c' })
    );
    config.endDate = rawConfig.expiryDate == null
      ? parseDate(getValue(rawConfig, new List<String>{ 'PayPal_EndDate__c' }))
      : rawConfig.expiryDate;
    return config;
  }

  private static Config getDefaultTestConfig() {
    Config config = new Config();
    config.active = true;
    config.clientId = 'test_paypal_client_id';
    config.webhookId = TEST_WEBHOOK_ID;
    config.useSandbox = true;
    config.fromNormalizedConfig = false;
    return config;
  }

  private static Config cloneConfig(Config source) {
    if (source == null) {
      return null;
    }
    Config copy = new Config();
    copy.active = source.active;
    copy.clientId = source.clientId;
    copy.webhookId = source.webhookId;
    copy.useSandbox = source.useSandbox;
    copy.startDate = source.startDate;
    copy.endDate = source.endDate;
    copy.fromNormalizedConfig = source.fromNormalizedConfig;
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
      throw new AuraHandledException('Invalid PayPal connector config date: ' + value);
    }
  }
}