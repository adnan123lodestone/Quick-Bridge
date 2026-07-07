@IsTest
private class NetSuiteConfigServiceTest {
  @IsTest
  static void readsNormalizedConfigAndRejectsMissingRequiredValues() {
    Connector_Instance__c instanceRecord = insertConfiguredInstance();
    insertConfig(instanceRecord.Id, 'account_id', '123456_SB1');
    insertConfig(instanceRecord.Id, 'rest_web_services_url', 'https://123456-sb1.suitetalk.api.netsuite.com');
    insertConfig(instanceRecord.Id, 'suiteql_url', '/services/rest/query/v1/suiteql');
    insertConfig(instanceRecord.Id, 'auth_type', 'TBA');
    insertConfig(instanceRecord.Id, 'enable_customer_sync', 'true');
    insertConfig(instanceRecord.Id, 'enable_item_sync', 'true');

    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();

    System.assertEquals('netsuite', config.connectorKey);
    System.assertEquals('123456_SB1', config.accountId);
    System.assertEquals('NetSuite_TBA', config.namedCredentialName);
    System.assertEquals('TBA', config.authType);
    System.assertEquals(true, config.enableCustomerSync);
    System.assertEquals(true, config.enableItemSync);
  }

  @IsTest
  static void missingAccountIdFailsWithUserSafeMessage() {
    insertConfiguredInstance();

    try {
      NetSuiteConfigService.requireConfigured();
      System.assert(false, 'Expected missing account id to fail.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Expected a user-safe setup exception.');
    }
  }

  @IsTest
  static void missingNamedCredentialFailsWithUserSafeMessage() {
    Connector_Instance__c instanceRecord = insertConfiguredInstance();
    instanceRecord.Named_Credential__c = null;
    update instanceRecord;
    insertConfig(instanceRecord.Id, 'account_id', '123456_SB1');

    try {
      NetSuiteConfigService.requireConfigured();
      System.assert(false, 'Expected missing named credential to fail.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Expected a user-safe setup exception.');
    }
  }

  @IsTest
  static void invalidPollingIntervalFailsWithHandledMessage() {
    Connector_Instance__c instanceRecord = insertConfiguredInstance();
    insertConfig(instanceRecord.Id, 'account_id', '123456_SB1');
    insertConfig(instanceRecord.Id, 'polling_interval_minutes', 'not-a-number');

    try {
      NetSuiteConfigService.load();
      System.assert(false, 'Expected invalid polling interval to fail.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected);
    }
  }

  @IsTest
  static void invalidLastSuccessfulSyncAtFailsWithHandledMessage() {
    Connector_Instance__c instanceRecord = insertConfiguredInstance();
    insertConfig(instanceRecord.Id, 'account_id', '123456_SB1');
    insertConfig(instanceRecord.Id, 'last_successful_sync_at', 'not-a-date');

    try {
      NetSuiteConfigService.load();
      System.assert(false, 'Expected invalid last sync date to fail.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected);
    }
  }

  @IsTest
  static void runtimeConfigDefaultsPhaseOneBooleansAndSuiteQlUrl() {
    Connector_Instance__c instanceRecord = insertConfiguredInstance();
    insertConfig(instanceRecord.Id, 'account_id', '123456_SB1');

    NetSuiteConfigService.Config config = NetSuiteConfigService.load();

    System.assertEquals('/services/rest/query/v1/suiteql', config.suiteqlUrl);
    System.assertEquals(true, config.enableCustomerSync);
    System.assertEquals(true, config.enableItemSync);
    System.assertEquals(false, config.enableSalesOrderSync);
    System.assertEquals(false, config.enableInvoiceSync);
    System.assertEquals(false, config.enablePaymentSync);
    System.assertEquals(false, config.enableFulfillmentSync);
  }

  @IsTest
  static void credentialResolverReturnsReferenceNamesOnly() {
    Connector_Instance__c instanceRecord = insertConfiguredInstance();
    insertConfig(instanceRecord.Id, 'account_id', '123456_SB1');
    insertConfig(instanceRecord.Id, 'consumer_key_reference', 'NetSuite_Consumer_Key');
    insertConfig(instanceRecord.Id, 'consumer_secret_reference', 'NetSuite_Consumer_Secret');
    insertConfig(instanceRecord.Id, 'token_id_reference', 'NetSuite_Token_Id');
    insertConfig(instanceRecord.Id, 'token_secret_reference', 'NetSuite_Token_Secret');

    NetSuiteCredentialResolver.CredentialConfig credentials = NetSuiteCredentialResolver.resolve();

    System.assertEquals('NetSuite_TBA', credentials.namedCredentialName);
    System.assertEquals('NetSuite_External', credentials.externalCredentialName);
    System.assertEquals('NetSuite_Consumer_Key', credentials.consumerKeyReference);
    System.assertEquals('NetSuite_Token_Secret', credentials.tokenSecretReference);
  }

  private static Connector_Instance__c insertConfiguredInstance() {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'NetSuite',
      Connector_Key__c = 'netsuite',
      Connector_Label__c = 'NetSuite',
      Active__c = true,
      Environment__c = 'Sandbox',
      Entitlement_Status__c = 'Active',
      Health_Status__c = 'Unknown',
      Named_Credential__c = 'NetSuite_TBA',
      External_Credential__c = 'NetSuite_External'
    );
    insert instanceRecord;
    return instanceRecord;
  }

  private static void insertConfig(Id instanceId, String fieldKey, String value) {
    insert new Connector_Config_Value__c(
      Name = 'netsuite:' + fieldKey,
      Connector_Instance__c = instanceId,
      Connector_Key__c = 'netsuite',
      Field_Key__c = fieldKey,
      Value__c = value,
      Is_Secret_Reference__c = fieldKey.contains('reference')
    );
  }
}