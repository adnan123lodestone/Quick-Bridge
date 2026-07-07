public with sharing class NetSuiteConfigService {
  public static final String CONNECTOR_KEY = 'netsuite';
  @TestVisible
  private static Config testConfig;

  public class Config {
    public String connectorKey;
    public String accountId;
    public String environment;
    public String restWebServicesUrl;
    public String suiteqlUrl;
    public String namedCredentialName;
    public String externalCredentialName;
    public String authType;
    public String defaultSubsidiary;
    public String defaultCurrency;
    public String defaultPriceLevel;
    public String defaultLocation;
    public String defaultDepartment;
    public String defaultClass;
    public String defaultItemRecordType;
    public String paymentAccountReference;
    public String arAccountReference;
    public String defaultFulfillmentLocation;
    public String syncDirection;
    public Boolean enableCustomerSync;
    public Boolean enableItemSync;
    public Boolean enableSalesOrderSync;
    public Boolean enableInvoiceSync;
    public Boolean enablePaymentSync;
    public Boolean enableFulfillmentSync;
    public Integer pollingIntervalMinutes;
    public Boolean webhookEnabled;
    public Datetime lastSuccessfulSyncAt;
  }

  public static Config requireConfigured() {
    Config config = load();
    List<String> missing = new List<String>();
    if (String.isBlank(config.accountId)) {
      missing.add('NetSuite account ID is required.');
    }
    if (String.isBlank(config.namedCredentialName)) {
      missing.add('NetSuite Named Credential is required.');
    }
    if (!missing.isEmpty()) {
      throw new AuraHandledException(String.join(missing, ' '));
    }
    return config;
  }

  public static Config load() {
    if (Test.isRunningTest() && testConfig != null) {
      return copyOf(testConfig);
    }
    ConnectorConfigService.ConnectorConfig raw = ConnectorConfigService.getConfig(CONNECTOR_KEY);
    Config config = new Config();
    config.connectorKey = CONNECTOR_KEY;
    config.accountId = value(raw, 'account_id');
    config.environment = firstNonBlank(raw.environment, value(raw, 'environment'));
    config.restWebServicesUrl = value(raw, 'rest_web_services_url');
    config.suiteqlUrl = firstNonBlank(value(raw, 'suiteql_url'), '/services/rest/query/v1/suiteql');
    config.namedCredentialName = firstNonBlank(raw.namedCredential, value(raw, 'named_credential_name'));
    config.externalCredentialName = raw.externalCredential;
    config.authType = firstNonBlank(value(raw, 'auth_type'), 'TBA');
    config.defaultSubsidiary = value(raw, 'default_subsidiary');
    config.defaultCurrency = value(raw, 'default_currency');
    config.defaultPriceLevel = value(raw, 'default_price_level');
    config.defaultLocation = value(raw, 'default_location');
    config.defaultDepartment = value(raw, 'default_department');
    config.defaultClass = value(raw, 'default_class');
    config.defaultItemRecordType = firstNonBlank(value(raw, 'default_item_record_type'), 'inventoryItem');
    config.paymentAccountReference = value(raw, 'payment_account_reference');
    config.arAccountReference = value(raw, 'ar_account_reference');
    config.defaultFulfillmentLocation = value(raw, 'default_fulfillment_location');
    config.syncDirection = firstNonBlank(value(raw, 'sync_direction'), 'Inbound');
    config.enableCustomerSync = booleanValue(raw, 'enable_customer_sync', true);
    config.enableItemSync = booleanValue(raw, 'enable_item_sync', true);
    config.enableSalesOrderSync = booleanValue(raw, 'enable_sales_order_sync', false);
    config.enableInvoiceSync = booleanValue(raw, 'enable_invoice_sync', false);
    config.enablePaymentSync = booleanValue(raw, 'enable_payment_sync', false);
    config.enableFulfillmentSync = booleanValue(raw, 'enable_fulfillment_sync', false);
    config.pollingIntervalMinutes = integerValue(raw, 'polling_interval_minutes', 60);
    config.webhookEnabled = booleanValue(raw, 'webhook_enabled', false);
    config.lastSuccessfulSyncAt = datetimeValue(raw, 'last_successful_sync_at');
    return config;
  }

  public static void markSuccessfulSync(Datetime syncAt) {
    Datetime value = syncAt == null ? Datetime.now() : syncAt;
    if (Test.isRunningTest() && testConfig != null) {
      testConfig.lastSuccessfulSyncAt = value;
      return;
    }
    List<Connector_Instance__c> instances = [
      SELECT Id
      FROM Connector_Instance__c
      WHERE Connector_Key__c = :CONNECTOR_KEY
      LIMIT 1
    ];
    Id instanceId = instances.isEmpty() ? null : instances[0].Id;
    List<Connector_Config_Value__c> existing = [
      SELECT Id
      FROM Connector_Config_Value__c
      WHERE Connector_Key__c = :CONNECTOR_KEY
      AND Field_Key__c = 'last_successful_sync_at'
      LIMIT 1
    ];
    Connector_Config_Value__c row = existing.isEmpty()
      ? new Connector_Config_Value__c()
      : existing[0];
    row.Name = CONNECTOR_KEY + ':last_successful_sync_at';
    row.Connector_Instance__c = instanceId;
    row.Connector_Key__c = CONNECTOR_KEY;
    row.Field_Key__c = 'last_successful_sync_at';
    row.Value__c = value.formatGmt('yyyy-MM-dd HH:mm:ss');
    row.Is_Secret_Reference__c = false;
    upsert row;
  }

  private static String value(ConnectorConfigService.ConnectorConfig config, String key) {
    if (config == null || config.values == null || !config.values.containsKey(key)) {
      return null;
    }
    return config.values.get(key);
  }

  private static Boolean booleanValue(
    ConnectorConfigService.ConnectorConfig config,
    String key,
    Boolean defaultValue
  ) {
    String raw = value(config, key);
    if (String.isBlank(raw)) {
      return defaultValue;
    }
    return raw.equalsIgnoreCase('true') || raw.equalsIgnoreCase('yes') || raw == '1';
  }

  private static Integer integerValue(
    ConnectorConfigService.ConnectorConfig config,
    String key,
    Integer defaultValue
  ) {
    String raw = value(config, key);
    if (String.isBlank(raw)) {
      return defaultValue;
    }
    try {
      return Integer.valueOf(raw);
    } catch (Exception e) {
      throw new AuraHandledException('Invalid NetSuite integer config for ' + key + ': ' + raw);
    }
  }

  private static Datetime datetimeValue(ConnectorConfigService.ConnectorConfig config, String key) {
    String raw = value(config, key);
    if (String.isBlank(raw)) {
      return null;
    }
    try {
      return Datetime.valueOfGmt(raw);
    } catch (Exception ignored) {
      try {
        return (Datetime) JSON.deserialize('"' + raw + '"', Datetime.class);
      } catch (Exception e) {
        throw new AuraHandledException('Invalid NetSuite datetime config for ' + key + ': ' + raw);
      }
    }
  }

  private static String firstNonBlank(String firstValue, String secondValue) {
    return String.isBlank(firstValue) ? secondValue : firstValue;
  }

  @TestVisible
  private static void setTestConfig(Config config) {
    testConfig = config;
  }

  @TestVisible
  private static Config testConfigured() {
    Config config = new Config();
    config.connectorKey = CONNECTOR_KEY;
    config.accountId = '123456_SB1';
    config.environment = 'Sandbox';
    config.suiteqlUrl = '/services/rest/query/v1/suiteql';
    config.namedCredentialName = 'NetSuite_TBA';
    config.authType = 'TBA';
    config.syncDirection = 'Inbound';
    config.enableCustomerSync = true;
    config.enableItemSync = true;
    config.defaultItemRecordType = 'inventoryItem';
    config.pollingIntervalMinutes = 60;
    config.webhookEnabled = false;
    return config;
  }

  private static Config copyOf(Config source) {
    Config config = new Config();
    config.connectorKey = source.connectorKey;
    config.accountId = source.accountId;
    config.environment = source.environment;
    config.restWebServicesUrl = source.restWebServicesUrl;
    config.suiteqlUrl = source.suiteqlUrl;
    config.namedCredentialName = source.namedCredentialName;
    config.externalCredentialName = source.externalCredentialName;
    config.authType = source.authType;
    config.defaultSubsidiary = source.defaultSubsidiary;
    config.defaultCurrency = source.defaultCurrency;
    config.defaultPriceLevel = source.defaultPriceLevel;
    config.defaultLocation = source.defaultLocation;
    config.defaultDepartment = source.defaultDepartment;
    config.defaultClass = source.defaultClass;
    config.defaultItemRecordType = source.defaultItemRecordType;
    config.paymentAccountReference = source.paymentAccountReference;
    config.arAccountReference = source.arAccountReference;
    config.defaultFulfillmentLocation = source.defaultFulfillmentLocation;
    config.syncDirection = source.syncDirection;
    config.enableCustomerSync = source.enableCustomerSync;
    config.enableItemSync = source.enableItemSync;
    config.enableSalesOrderSync = source.enableSalesOrderSync;
    config.enableInvoiceSync = source.enableInvoiceSync;
    config.enablePaymentSync = source.enablePaymentSync;
    config.enableFulfillmentSync = source.enableFulfillmentSync;
    config.pollingIntervalMinutes = source.pollingIntervalMinutes;
    config.webhookEnabled = source.webhookEnabled;
    config.lastSuccessfulSyncAt = source.lastSuccessfulSyncAt;
    return config;
  }
}