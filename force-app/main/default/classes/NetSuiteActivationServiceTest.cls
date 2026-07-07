@IsTest
private class NetSuiteActivationServiceTest {
  @IsTest
  static void setupCreatesIdempotentNetSuiteInstanceAndConfigValues() {
    NetSuiteActivationService.SetupRequest request = phaseOneRequest();

    Test.startTest();
    NetSuiteActivationService.ActivationResult firstResult = NetSuiteActivationService.setupPhaseOne(request);
    NetSuiteActivationService.ActivationResult secondResult = NetSuiteActivationService.setupPhaseOne(request);
    Test.stopTest();

    System.assertEquals(true, firstResult.success);
    System.assertEquals(true, secondResult.success);
    System.assertEquals(1, [SELECT COUNT() FROM Connector_Instance__c WHERE Connector_Key__c = 'netsuite']);
    System.assertEquals(
      'NetSuite_TBA',
      [
        SELECT Named_Credential__c
        FROM Connector_Instance__c
        WHERE Connector_Key__c = 'netsuite'
        LIMIT 1
      ].Named_Credential__c
    );
    Connector_Config_Value__c salesOrderToggle = [
      SELECT Value__c
      FROM Connector_Config_Value__c
      WHERE Connector_Key__c = 'netsuite'
      AND Field_Key__c = 'enable_sales_order_sync'
      LIMIT 1
    ];
    System.assertEquals('false', salesOrderToggle.Value__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Connector_Config_Value__c
        WHERE Connector_Key__c = 'netsuite'
        AND Field_Key__c = 'token_secret_reference'
        AND Is_Secret_Reference__c = true
      ]
    );
  }

  @IsTest
  static void validationFailsForMissingRuntimeRows() {
    Test.startTest();
    NetSuiteActivationService.ActivationResult result = NetSuiteActivationService.validatePhaseOne();
    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assert(containsMessage(result, 'Connector_Instance__c'), result.messages + ' ' + result.warnings);
  }

  @IsTest
  static void validationFailsForPlaceholdersAndSecretReferenceFlags() {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'NetSuite',
      Connector_Key__c = 'netsuite',
      Connector_Label__c = 'NetSuite',
      Active__c = true,
      Environment__c = 'Sandbox',
      Entitlement_Status__c = 'Active',
      Health_Status__c = 'Unknown',
      Named_Credential__c = 'NetSuite_TBA'
    );
    insert instanceRecord;
    insert new List<Connector_Config_Value__c>{
      configValue(instanceRecord.Id, 'account_id', 'REPLACE_WITH_NETSUITE_ACCOUNT_ID', false),
      configValue(instanceRecord.Id, 'named_credential_name', 'NetSuite_TBA', false),
      configValue(instanceRecord.Id, 'suiteql_url', '/services/rest/query/v1/suiteql', false),
      configValue(instanceRecord.Id, 'token_secret_reference', 'NetSuite_Token_Secret', false)
    };

    Test.startTest();
    NetSuiteActivationService.ActivationResult result = NetSuiteActivationService.validatePhaseOne();
    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assert(containsMessage(result, 'Placeholder value remains'), result.messages + ' ' + result.warnings);
    System.assert(containsMessage(result, 'secret reference'), result.messages + ' ' + result.warnings);
  }

  @IsTest
  static void validationPassesForPhaseOneRuntimeConfig() {
    NetSuiteActivationService.setupPhaseOne(phaseOneRequest());

    Test.startTest();
    NetSuiteActivationService.ActivationResult result = NetSuiteActivationService.validatePhaseOne();
    Test.stopTest();

    System.assertEquals(true, result.success, result.messages + ' ' + result.warnings);
  }

  private static NetSuiteActivationService.SetupRequest phaseOneRequest() {
    NetSuiteActivationService.SetupRequest request = new NetSuiteActivationService.SetupRequest();
    request.accountId = '123456_SB1';
    request.environment = 'Sandbox';
    request.restWebServicesUrl = 'https://123456-sb1.suitetalk.api.netsuite.com';
    request.suiteqlUrl = '/services/rest/query/v1/suiteql';
    request.namedCredentialName = 'NetSuite_TBA';
    request.externalCredentialName = 'NetSuite_External';
    request.authType = 'TBA';
    request.consumerKeyReference = 'NetSuite_Consumer_Key';
    request.consumerSecretReference = 'NetSuite_Consumer_Secret';
    request.tokenIdReference = 'NetSuite_Token_Id';
    request.tokenSecretReference = 'NetSuite_Token_Secret';
    request.pollingIntervalMinutes = 60;
    return request;
  }

  private static Connector_Config_Value__c configValue(
    Id instanceId,
    String fieldKey,
    String value,
    Boolean secretReference
  ) {
    return new Connector_Config_Value__c(
      Name = 'netsuite:' + fieldKey,
      Connector_Instance__c = instanceId,
      Connector_Key__c = 'netsuite',
      Field_Key__c = fieldKey,
      Value__c = value,
      Is_Secret_Reference__c = secretReference
    );
  }

  private static Boolean containsMessage(NetSuiteActivationService.ActivationResult result, String expected) {
    for (String message : result.messages) {
      if (message != null && message.contains(expected)) {
        return true;
      }
    }
    for (String warning : result.warnings) {
      if (warning != null && warning.contains(expected)) {
        return true;
      }
    }
    return false;
  }
}
