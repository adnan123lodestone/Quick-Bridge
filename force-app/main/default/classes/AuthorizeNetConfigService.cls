public with sharing class AuthorizeNetConfigService {
  private static final String CONNECTOR_KEY = 'authorizenet';
  private static final String TEST_WEBHOOK_SIGNING_KEY = '00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF';

  public class Config {
    public Boolean active;
    public Boolean useSandbox;
    public String apiLoginId;
    public String publicClientKey;
    public String webhookSigningKey;
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

    Config gatewayConfig = getGatewayLegacyConfig();
    if (gatewayConfig != null) {
      return gatewayConfig;
    }

    throw new AuraHandledException('Authorize.Net configuration record was not found.');
  }

  public static String getWebhookSigningKey() {
    Config config = getConfig();
    return config == null ? null : config.webhookSigningKey;
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
    config.apiLoginId = getValue(
      rawConfig,
      new List<String>{ 'AuthorizeNet_API_Login_ID__c' }
    );
    config.publicClientKey = getValue(
      rawConfig,
      new List<String>{ 'AuthorizeNet_Public_Client_Key__c' }
    );
    config.webhookSigningKey = getValue(
      rawConfig,
      new List<String>{ 'AuthorizeNet_Webhook_Signing_Key__c' }
    );
    config.useSandbox = parseBoolean(
      getValue(rawConfig, new List<String>{ 'AuthorizeNet_Use_Sandbox__c' })
    );
    config.startDate = parseDate(
      getValue(rawConfig, new List<String>{ 'AuthorizeNet_Start_Date__c' })
    );
    config.endDate = rawConfig.expiryDate == null
      ? parseDate(getValue(rawConfig, new List<String>{ 'AuthorizeNet_End_Date__c' }))
      : rawConfig.expiryDate;
    return config;
  }

  private static Config getQuickbridgeLegacyConfig() {
    Quickbridge_Config__mdt legacy;
    try {
      legacy = Quickbridge_Config__mdt.getInstance('AuthorizeNet');
    } catch (Exception e) {
      legacy = null;
    }
    if (legacy == null) {
      return null;
    }

    Config config = new Config();
    config.fromNormalizedConfig = false;
    config.fromLegacyConfig = true;
    config.active = legacy.AuthorizeNet_Active__c;
    config.apiLoginId = legacy.AuthorizeNet_API_Login_ID__c;
    config.publicClientKey = legacy.AuthorizeNet_Public_Client_Key__c;
    config.webhookSigningKey = legacy.AuthorizeNet_Webhook_Signing_Key__c;
    config.useSandbox = legacy.AuthorizeNet_Use_Sandbox__c;
    config.startDate = legacy.AuthorizeNet_Start_Date__c;
    config.endDate = legacy.AuthorizeNet_End_Date__c;
    return config;
  }

  private static Config getGatewayLegacyConfig() {
    AuthorizeNet_Config__mdt legacy;
    try {
      legacy = AuthorizeNet_Config__mdt.getInstance('Default');
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
    config.apiLoginId = legacy.APILoginId__c;
    config.publicClientKey = legacy.PublicClientKey__c;
    config.webhookSigningKey = legacy.WebhookSigningKey__c;
    config.useSandbox = legacy.UseSandbox__c;
    config.startDate = legacy.StartDate__c;
    config.endDate = legacy.EndDate__c;
    return config;
  }

  private static Config getDefaultTestConfig() {
    Config config = new Config();
    config.active = true;
    config.apiLoginId = 'test_api_login_id';
    config.publicClientKey = 'test_public_client_key';
    config.webhookSigningKey = TEST_WEBHOOK_SIGNING_KEY;
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
    copy.apiLoginId = source.apiLoginId;
    copy.publicClientKey = source.publicClientKey;
    copy.webhookSigningKey = source.webhookSigningKey;
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
      throw new AuraHandledException('Invalid Authorize.Net connector config date: ' + value);
    }
  }
}