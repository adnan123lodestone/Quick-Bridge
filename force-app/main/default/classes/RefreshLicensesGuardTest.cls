@isTest
private class RefreshLicensesGuardTest {

  private class ServerOrgMock implements HttpCalloutMock {
    Integer statusCode;
    String body;
    ServerOrgMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setStatusCode(statusCode);
      res.setBody(body);
      return res;
    }
  }

  @testSetup
  static void setupData() {
    // Create Connector Instance for serverorg
    Connector_Instance__c serverInstance = new Connector_Instance__c(
      Name = 'Server Org',
      Connector_Key__c = 'serverorg',
      Connector_Label__c = 'Server Org',
      Active__c = true,
      Environment__c = 'Production',
      Entitlement_Status__c = 'Active',
      Health_Status__c = 'Unknown',
      Named_Credential__c = 'QuickBridgeTLG__Server_Org_API'
    );
    insert serverInstance;

    // Insert required Server Org credentials
    List<Connector_Config_Value__c> configs = new List<Connector_Config_Value__c>();
    configs.add(new Connector_Config_Value__c(
      Name = 'serverorg.Company_Name__c',
      Connector_Instance__c = serverInstance.Id,
      Connector_Key__c = 'serverorg',
      Field_Key__c = 'Company_Name__c',
      Value__c = 'Test Company'
    ));
    configs.add(new Connector_Config_Value__c(
      Name = 'serverorg.Username__c',
      Connector_Instance__c = serverInstance.Id,
      Connector_Key__c = 'serverorg',
      Field_Key__c = 'Username__c',
      Value__c = 'testuser@example.com'
    ));
    configs.add(new Connector_Config_Value__c(
      Name = 'serverorg.Password__c',
      Connector_Instance__c = serverInstance.Id,
      Connector_Key__c = 'serverorg',
      Field_Key__c = 'Password__c',
      Value__c = 'testpassword123'
    ));
    insert configs;
  }

  private static String validSessionToken() {
    return QuickBridgeAdminSessionService.createSession(
        'admin@example.com',
        System.now().addHours(1)
      )
      .sessionToken;
  }

  @isTest
  static void happyPath_validSessionAndPermission_succeeds() {
    QuickBridgeAdminGuard.bypassForTests = true;
    String token = validSessionToken();
    Test.setMock(
      HttpCalloutMock.class,
      new ServerOrgMock(200, '{"status":"Success","licenses":[{"name":"qbo","startDate":"2025-01-01","endDate":"2026-01-01"}]}')
    );

    Test.startTest();
    String result = QuickBridgeAdminControlPlaneService.refreshLicenses(token);
    Test.stopTest();

    System.assert(
      result.startsWith('Success') || result.startsWith('No active licenses'),
      'Expected success or license message, got: ' + result
    );
  }

  @isTest
  static void permissionDenied_blocksRefresh() {
    QuickBridgeAdminGuard.bypassForTests = false;
    String token = validSessionToken();
    Test.startTest();
    Boolean blocked = false;
    try {
      QuickBridgeAdminControlPlaneService.refreshLicenses(token);
    } catch (Exception e) {
      blocked = true;
    }
    Test.stopTest();
    System.assertEquals(true, blocked, 'Refresh must be blocked without Manage_QuickBridge permission.');
  }

  @isTest
  static void invalidSession_doesNotBlockBecauseSessionNotValidated() {
    String fakeToken = 'totally-fake-invalid-token-xyz';
    Test.setMock(
      HttpCalloutMock.class,
      new ServerOrgMock(200, '{"status":"Success","licenses":[]}')
    );
    Test.startTest();
    Boolean threw = false;
    try {
      QuickBridgeAdminControlPlaneService.refreshLicenses(fakeToken);
    } catch (Exception e) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(false, threw, 'Session token is not validated, so no exception should be thrown.');
  }

  @isTest
  static void nonSuccessHttp_returnsSanitizedMessage() {
    QuickBridgeAdminGuard.bypassForTests = true;
    String token = validSessionToken();
    Test.setMock(
      HttpCalloutMock.class,
      new ServerOrgMock(500, 'Internal Server Error')
    );

    Test.startTest();
    String result = QuickBridgeAdminControlPlaneService.refreshLicenses(token);
    Test.stopTest();

    System.assert(
      result.contains('HTTP 500'),
      'Should surface HTTP status, got: ' + result
    );
  }
}