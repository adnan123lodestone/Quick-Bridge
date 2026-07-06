public with sharing class NetSuiteCredentialResolver {
  public class CredentialConfig {
    public String namedCredentialName;
    public String externalCredentialName;
    public String authType;
    public String consumerKeyReference;
    public String consumerSecretReference;
    public String tokenIdReference;
    public String tokenSecretReference;
  }

  public static CredentialConfig resolve() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    CredentialConfig credentials = new CredentialConfig();
    credentials.namedCredentialName = config.namedCredentialName;
    credentials.externalCredentialName = config.externalCredentialName;
    credentials.authType = config.authType;
    credentials.consumerKeyReference = ConnectorConfigService.getConfigValue(
      NetSuiteConfigService.CONNECTOR_KEY,
      'consumer_key_reference'
    );
    credentials.consumerSecretReference = ConnectorConfigService.getConfigValue(
      NetSuiteConfigService.CONNECTOR_KEY,
      'consumer_secret_reference'
    );
    credentials.tokenIdReference = ConnectorConfigService.getConfigValue(
      NetSuiteConfigService.CONNECTOR_KEY,
      'token_id_reference'
    );
    credentials.tokenSecretReference = ConnectorConfigService.getConfigValue(
      NetSuiteConfigService.CONNECTOR_KEY,
      'token_secret_reference'
    );
    return credentials;
  }
}
