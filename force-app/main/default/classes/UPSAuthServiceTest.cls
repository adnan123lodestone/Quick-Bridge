@IsTest
private class UPSAuthServiceTest {
  private static String lastEndpoint;
  private static String lastAuthorization;
  private static String lastBody;

  private class TokenMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      lastEndpoint = request.getEndpoint();
      lastAuthorization = request.getHeader('Authorization');
      lastBody = request.getBody();

      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"access_token":"ups-token","token_type":"Bearer","expires_in":"3600"}');
      return response;
    }
  }

  private class AuthFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(401);
      response.setStatus('Unauthorized');
      response.setBody('{"response":{"errors":[{"code":"AUTH","message":"bad credentials"}]}}');
      return response;
    }
  }

  private class SendFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      throw new CalloutException('ups network failure');
    }
  }

  @IsTest
  static void activeConfigBuildsTokenRequestAndUrls() {
    Connector_Instance__c instanceRecord = createUpsInstance(true);
    insertValue(instanceRecord, 'UPS_Client_Id__c', 'ups-client', false);
    insertValue(instanceRecord, 'UPS_Client_Secret__c', 'ups-secret', true);
    insertValue(instanceRecord, 'UPS_Account_Number__c', 'A12345', false);
    insertValue(instanceRecord, 'UPS_Environment__c', 'Production', false);
    insertValue(instanceRecord, 'UPS_Default_Service_Code__c', '02', false);
    Test.setMock(HttpCalloutMock.class, new TokenMock());

    Test.startTest();
    String token = UPSAuthService.getAccessToken();
    Test.stopTest();

    System.assertEquals('ups-token', token);
    System.assertEquals(
      'https://onlinetools.ups.com/security/v1/oauth/token',
      lastEndpoint
    );
    System.assertEquals(
      'Basic ' + EncodingUtil.base64Encode(Blob.valueOf('ups-client:ups-secret')),
      lastAuthorization
    );
    System.assertEquals('grant_type=client_credentials', lastBody);

    UPSAuthService.UPSCredentialConfig config = UPSAuthService.getCredentialConfig();
    System.assertEquals('A12345', config.accountNumber);
    System.assertEquals('02', config.defaultServiceCode);
    System.assertEquals('https://onlinetools.ups.com', UPSAuthService.getBaseUrl());
    System.assertEquals('https://onlinetools.ups.com/api', UPSAuthService.getApiBaseUrl());
    System.assertEquals('https://wwwcie.ups.com', UPSAuthService.getBaseUrl('Sandbox'));
    System.assertEquals(32, UPSAuthService.generateTransId().length());
  }

  @IsTest
  static void fallbackConfigIsInactiveWhenNoNormalizedValuesExist() {
    UPSAuthService.UPSCredentialConfig config = UPSAuthService.getCredentialConfig();

    System.assertEquals(false, config.isActive);
    System.assertEquals('Sandbox', config.environment);
    System.assertEquals('03', config.defaultServiceCode);
    assertAccessTokenFailsWith('inactive');
  }

  @IsTest
  static void inactiveNormalizedConfigIsRejected() {
    Connector_Instance__c instanceRecord = createUpsInstance(false);
    insertValue(instanceRecord, 'UPS_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'UPS_Client_Secret__c', 'secret', true);
    insertValue(instanceRecord, 'UPS_Account_Number__c', 'account', false);

    assertAccessTokenFailsWith('inactive');
  }

  @IsTest
  static void missingClientIdIsRejected() {
    Connector_Instance__c instanceRecord = createUpsInstance(true);
    insertValue(instanceRecord, 'UPS_Client_Secret__c', 'secret', true);
    insertValue(instanceRecord, 'UPS_Account_Number__c', 'account', false);

    assertAccessTokenFailsWith('Client ID');
  }

  @IsTest
  static void missingClientSecretIsRejected() {
    Connector_Instance__c instanceRecord = createUpsInstance(true);
    insertValue(instanceRecord, 'UPS_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'UPS_Account_Number__c', 'account', false);

    assertAccessTokenFailsWith('Client Secret');
  }

  @IsTest
  static void missingAccountNumberIsRejected() {
    Connector_Instance__c instanceRecord = createUpsInstance(true);
    insertValue(instanceRecord, 'UPS_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'UPS_Client_Secret__c', 'secret', true);

    assertAccessTokenFailsWith('Account Number');
  }

  @IsTest
  static void authFailureResponseIsReported() {
    Connector_Instance__c instanceRecord = createUpsInstance(true);
    insertValue(instanceRecord, 'UPS_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'UPS_Client_Secret__c', 'secret', true);
    insertValue(instanceRecord, 'UPS_Account_Number__c', 'account', false);
    Test.setMock(HttpCalloutMock.class, new AuthFailureMock());

    Test.startTest();
    assertAccessTokenFailsWith('UPS Auth Failed');
    Test.stopTest();
  }

  @IsTest
  static void sendFailureIsLoggedAndRethrown() {
    Connector_Instance__c instanceRecord = createUpsInstance(true);
    insertValue(instanceRecord, 'UPS_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'UPS_Client_Secret__c', 'secret', true);
    insertValue(instanceRecord, 'UPS_Account_Number__c', 'account', false);
    Test.setMock(HttpCalloutMock.class, new SendFailureMock());

    Test.startTest();
    assertAccessTokenFailsWith('ups network failure');
    Test.stopTest();
  }

  private static void assertAccessTokenFailsWith(String expectedMessagePart) {
    Boolean didThrow = false;
    try {
      UPSAuthService.getAccessToken();
    } catch (CalloutException e) {
      didThrow = true;
      System.assert(
        e.getMessage().contains(expectedMessagePart),
        'Expected message to contain ' + expectedMessagePart + ' but got: ' + e.getMessage()
      );
    }
    System.assertEquals(true, didThrow);
  }

  private static Connector_Instance__c createUpsInstance(Boolean active) {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'UPS',
      Connector_Key__c = 'ups',
      Connector_Label__c = 'UPS',
      Active__c = active,
      Environment__c = 'Sandbox',
      Entitlement_Status__c = active ? 'Active' : 'Inactive',
      Expiry_Date__c = Date.today().addDays(30),
      Health_Status__c = 'Unknown'
    );
    insert instanceRecord;
    return instanceRecord;
  }

  private static void insertValue(
    Connector_Instance__c instanceRecord,
    String fieldKey,
    String value,
    Boolean isSecretReference
  ) {
    insert new Connector_Config_Value__c(
      Name = 'ups:' + fieldKey,
      Connector_Instance__c = instanceRecord.Id,
      Connector_Key__c = 'ups',
      Field_Key__c = fieldKey,
      Value__c = value,
      Is_Secret_Reference__c = isSecretReference
    );
  }
}