public with sharing class DHLAuthService {
  public class DHLCredentialConfig {
    public String apiKey;
    public String apiSecret;
    public String accountNumber;
    public String environment;
    public String defaultProductCode;
    public Boolean isActive;
  }

  public static DHLCredentialConfig getCredentialConfig() {
    DHLCredentialConfig config = new DHLCredentialConfig();
    config.apiKey = ConnectorConfigResolver.getValue('dhl', 'DHL_Api_Key__c');
    config.apiSecret = ConnectorConfigResolver.getValue(
      'dhl',
      'DHL_Api_Secret__c'
    );
    if (String.isBlank(config.apiSecret)) {
      config.apiSecret = ConnectorConfigResolver.getValue(
        'dhl',
        'apiSecretRef'
      );
    }
    config.accountNumber = ConnectorConfigResolver.getValue(
      'dhl',
      'DHL_Account_Number__c'
    );
    config.environment = ConnectorConfigResolver.getValue(
      'dhl',
      'DHL_Environment__c'
    );
    config.defaultProductCode = ConnectorConfigResolver.getValue(
      'dhl',
      'DHL_Default_Product_Code__c'
    );
    config.isActive = ConnectorConfigResolver.isActive('dhl');

    if (String.isBlank(config.environment)) {
      config.environment = 'Sandbox';
    }
    if (String.isBlank(config.defaultProductCode)) {
      config.defaultProductCode = 'P';
    }
    validateConfig(config);
    return config;
  }

  public static String getBaseUrl() {
    return getBaseUrl(getCredentialConfig().environment);
  }

  public static String getBaseUrl(String environment) {
    return environment == 'Production'
      ? 'https://express.api.dhl.com/mydhlapi'
      : 'https://express.api.dhl.com/mydhlapi/test';
  }

  public static String getBasicAuthHeader(DHLCredentialConfig config) {
    validateConfig(config);
    return 'Basic ' +
      EncodingUtil.base64Encode(
        Blob.valueOf(config.apiKey + ':' + config.apiSecret)
      );
  }

  private static void validateConfig(DHLCredentialConfig config) {
    if (config == null || config.isActive != true) {
      logConfigFailure('DHL configuration is inactive.');
      throw new CalloutException('DHL configuration is inactive.');
    }
    if (String.isBlank(config.apiKey)) {
      logConfigFailure('DHL API key is missing.');
      throw new CalloutException('DHL API key is missing.');
    }
    if (String.isBlank(config.apiSecret)) {
      logConfigFailure('DHL API secret reference is missing.');
      throw new CalloutException('DHL API secret reference is missing.');
    }
    if (String.isBlank(config.accountNumber)) {
      logConfigFailure('DHL account number is missing.');
      throw new CalloutException('DHL account number is missing.');
    }
  }

  private static void logConfigFailure(String message) {
    ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
    context.gatewayName = 'DHL';
    context.classMethodName = 'DHLAuthService.validateConfig';
    context.errorMessage = message;
    context.errorCategory = 'Configuration Error';
    ErrorLogUtility.logError(context);
  }
}