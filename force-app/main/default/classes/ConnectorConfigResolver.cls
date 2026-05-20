public with sharing class ConnectorConfigResolver {
  public class MissingConfigException extends Exception {
  }

  public static String getValue(
    String connectorKey,
    String fieldKeyOrLegacyName
  ) {
    return ConnectorConfigService.getConfigValue(
      connectorKey,
      fieldKeyOrLegacyName
    );
  }

  public static String requireValue(
    String connectorKey,
    String fieldKeyOrLegacyName
  ) {
    String value = getValue(connectorKey, fieldKeyOrLegacyName);
    if (String.isBlank(value)) {
      throw new AuraHandledException(
        'Missing connector config for ' +
          connectorKey +
          '.' +
          fieldKeyOrLegacyName +
          '. Configure this value on the connector instance or migrate legacy QuickBridge metadata.'
      );
    }
    return value;
  }

  public static Boolean getBoolean(
    String connectorKey,
    String fieldKeyOrLegacyName
  ) {
    String value = getValue(connectorKey, fieldKeyOrLegacyName);
    if (String.isBlank(value)) {
      return false;
    }
    return value.equalsIgnoreCase('true') ||
      value.equalsIgnoreCase('yes') ||
      value == '1';
  }

  public static Date getDate(String connectorKey, String fieldKeyOrLegacyName) {
    String value = getValue(connectorKey, fieldKeyOrLegacyName);
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return Date.valueOf(value);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Invalid date connector config for ' +
          connectorKey +
          '.' +
          fieldKeyOrLegacyName +
          ': ' +
          value
      );
    }
  }

  public static Boolean isActive(String connectorKey) {
    return ConnectorConfigService.isActive(connectorKey);
  }
}