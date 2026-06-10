@IsTest
private class FedExAuthServiceTest {
  private static String lastEndpoint;
  private static String lastBody;

  private class TokenMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      lastEndpoint = request.getEndpoint();
      lastBody = request.getBody();

      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"access_token":"fedex-token","token_type":"bearer","expires_in":3600}');
      return response;
    }
  }

  private class AuthFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(401);
      response.setStatus('Unauthorized');
      response.setBody('{"errors":[{"code":"AUTH","message":"bad credentials"}]}');
      return response;
    }
  }

  private class SendFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      throw new CalloutException('network failure');
    }
  }

  @IsTest
  static void normalizedConfigIsPreferredAndUsesClientSecretRef() {
    Connector_Instance__c instanceRecord = createFedExInstance(true);
    insertValue(instanceRecord, 'FedEx_Client_Id__c', 'normalized client', false);
    insertValue(instanceRecord, 'clientSecretRef', 'normalized secret', true);
    insertValue(instanceRecord, 'FedEx_Account_Number__c', 'normalized account', false);
    insertValue(instanceRecord, 'FedEx_Environment__c', 'Production', false);
    insertValue(instanceRecord, 'FedEx_Default_Service_Type__c', 'FEDEX_GROUND', false);

    Test.setMock(HttpCalloutMock.class, new TokenMock());

    Test.startTest();
    String token = FedExAuthService.getAccessToken();
    Test.stopTest();

    System.assertEquals('fedex-token', token);
    System.assertEquals(
      'https://apis.fedex.com/oauth/token',
      lastEndpoint
    );
    System.assert(
      lastBody.contains(
        'client_id=' + EncodingUtil.urlEncode('normalized client', 'UTF-8')
      )
    );
    System.assert(
      lastBody.contains(
        'client_secret=' +
        EncodingUtil.urlEncode('normalized secret', 'UTF-8')
      )
    );

    FedExAuthService.FedExCredentialConfig config = FedExAuthService.getCredentialConfig();
    System.assertEquals('normalized account', config.accountNumber);
    System.assertEquals('FEDEX_GROUND', config.defaultServiceType);
  }

  @IsTest
  static void fedExClientSecretLegacyFieldIsAccepted() {
    Connector_Instance__c instanceRecord = createFedExInstance(true);
    insertValue(instanceRecord, 'FedEx_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'FedEx_Client_Secret__c', 'secret', false);
    insertValue(instanceRecord, 'FedEx_Account_Number__c', 'account', false);

    Test.startTest();
    FedExAuthService.FedExCredentialConfig config = FedExAuthService.getCredentialConfig();
    Test.stopTest();

    System.assertEquals('client', config.clientId);
    System.assertEquals('secret', config.clientSecret);
    System.assertEquals('account', config.accountNumber);
    System.assertEquals('Sandbox', config.environment);
    System.assertEquals(
      'https://apis-sandbox.fedex.com',
      FedExAuthService.getBaseUrl()
    );
  }

  @IsTest
  static void authFailureResponseIsReported() {
    Connector_Instance__c instanceRecord = createFedExInstance(true);
    insertValue(instanceRecord, 'FedEx_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'clientSecretRef', 'secret', true);
    insertValue(instanceRecord, 'FedEx_Account_Number__c', 'account', false);
    Test.setMock(HttpCalloutMock.class, new AuthFailureMock());

    Test.startTest();
    assertAccessTokenFailsWith('FedEx Auth Failed');
    Test.stopTest();
  }

  @IsTest
  static void sendFailureIsLoggedAndRethrown() {
    Connector_Instance__c instanceRecord = createFedExInstance(true);
    insertValue(instanceRecord, 'FedEx_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'clientSecretRef', 'secret', true);
    insertValue(instanceRecord, 'FedEx_Account_Number__c', 'account', false);
    Test.setMock(HttpCalloutMock.class, new SendFailureMock());

    Test.startTest();
    assertAccessTokenFailsWith('network failure');
    Test.stopTest();
  }

  @IsTest
  static void metadataFallbackReturnsAConfigWhenNoNormalizedValuesExist() {
    FedExAuthService.FedExCredentialConfig config = FedExAuthService.getCredentialConfig();

    System.assertNotEquals(null, config);
    System.assertNotEquals(null, config.environment);
    System.assertEquals(
      'https://apis-sandbox.fedex.com',
      FedExAuthService.getBaseUrl('Sandbox')
    );
    System.assertEquals(
      'https://apis.fedex.com',
      FedExAuthService.getBaseUrl('Production')
    );
  }

  @IsTest
  static void inactiveNormalizedConfigIsRejected() {
    Connector_Instance__c instanceRecord = createFedExInstance(false);
    insertValue(instanceRecord, 'FedEx_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'clientSecretRef', 'secret', true);
    insertValue(instanceRecord, 'FedEx_Account_Number__c', 'account', false);

    assertAccessTokenFailsWith('inactive');
  }

  @IsTest
  static void missingClientIdIsRejected() {
    Connector_Instance__c instanceRecord = createFedExInstance(true);
    insertValue(instanceRecord, 'clientSecretRef', 'secret', true);
    insertValue(instanceRecord, 'FedEx_Account_Number__c', 'account', false);

    assertAccessTokenFailsWith('Client ID');
  }

  @IsTest
  static void missingClientSecretIsRejected() {
    Connector_Instance__c instanceRecord = createFedExInstance(true);
    insertValue(instanceRecord, 'FedEx_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'FedEx_Account_Number__c', 'account', false);

    assertAccessTokenFailsWith('Client Secret');
  }

  @IsTest
  static void missingAccountNumberIsRejected() {
    Connector_Instance__c instanceRecord = createFedExInstance(true);
    insertValue(instanceRecord, 'FedEx_Client_Id__c', 'client', false);
    insertValue(instanceRecord, 'clientSecretRef', 'secret', true);

    assertAccessTokenFailsWith('Account Number');
  }

  private static void assertAccessTokenFailsWith(String expectedMessagePart) {
    Boolean didThrow = false;
    try {
      FedExAuthService.getAccessToken();
    } catch (CalloutException e) {
      didThrow = true;
      System.assert(
        e.getMessage().contains(expectedMessagePart),
        'Expected message to contain ' +
          expectedMessagePart +
          ' but got: ' +
          e.getMessage()
      );
    }
    System.assertEquals(true, didThrow);
  }

  private static Connector_Instance__c createFedExInstance(Boolean active) {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'FedEx',
      Connector_Key__c = 'fedex',
      Connector_Label__c = 'FedEx',
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
      Name = 'fedex:' + fieldKey,
      Connector_Instance__c = instanceRecord.Id,
      Connector_Key__c = 'fedex',
      Field_Key__c = fieldKey,
      Value__c = value,
      Is_Secret_Reference__c = isSecretReference
    );
  }
}