@IsTest
private class NetSuiteConnectionValidatorTest {
  @TestSetup
  static void setupData() {
    insertConfiguredInstance();
  }

  @IsTest
  static void validationUpdatesHealthAndWritesAudit() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    Test.setMock(HttpCalloutMock.class, new ValidationMock(200, '{"items":[{"status":"ok"}],"hasMore":false}'));

    Test.startTest();
    NetSuiteConnectionValidator.ValidationResult result =
      NetSuiteConnectionValidator.validateConnection();
    Test.stopTest();

    System.assertEquals(true, result.success);
    Connector_Instance__c refreshed = [
      SELECT Health_Status__c, Last_Health_Check_At__c
      FROM Connector_Instance__c
      WHERE Connector_Key__c = 'netsuite'
      LIMIT 1
    ];
    System.assertEquals('Healthy', refreshed.Health_Status__c);
    System.assertNotEquals(null, refreshed.Last_Health_Check_At__c);
    System.assertEquals(
      1,
      [SELECT count() FROM QuickBridge_Admin_Audit__c WHERE Connector_Key__c = 'netsuite' AND Action__c = 'CONNECTION_VALIDATE']
    );
  }

  @IsTest
  static void validationFailureUpdatesHealthAndWritesAudit() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    Test.setMock(HttpCalloutMock.class, new ValidationMock(401, '{"title":"Invalid login","detail":"token_secret=abc123"}'));

    Test.startTest();
    NetSuiteConnectionValidator.ValidationResult result =
      NetSuiteConnectionValidator.validateConnection();
    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assertEquals('Error', result.status);
    System.assert(!result.message.contains('abc123'), 'Failure messages must not expose secrets.');
    Connector_Instance__c refreshed = [
      SELECT Health_Status__c
      FROM Connector_Instance__c
      WHERE Connector_Key__c = 'netsuite'
      LIMIT 1
    ];
    System.assertEquals('Error', refreshed.Health_Status__c);
  }

  @IsTest
  static void validationFailureFromMissingConfigUpdatesHealthAndAudits() {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.accountId = null;
    NetSuiteConfigService.setTestConfig(config);

    Test.startTest();
    NetSuiteConnectionValidator.ValidationResult result = NetSuiteConnectionValidator.validateConnection();
    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assertNotEquals(null, result.message);
    Connector_Instance__c refreshed = [
      SELECT Health_Status__c
      FROM Connector_Instance__c
      WHERE Connector_Key__c = 'netsuite'
      LIMIT 1
    ];
    System.assertEquals('Error', refreshed.Health_Status__c);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM QuickBridge_Admin_Audit__c WHERE Connector_Key__c = 'netsuite' AND Action__c = 'CONNECTION_VALIDATE']
    );
  }

  private class ValidationMock implements HttpCalloutMock {
    Integer statusCode;
    String responseBody;
    ValidationMock(Integer statusCode, String responseBody) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(responseBody);
      return response;
    }
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
      Named_Credential__c = 'NetSuite_TBA'
    );
    insert instanceRecord;
    return instanceRecord;
  }

}
