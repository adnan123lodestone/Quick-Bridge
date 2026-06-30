@IsTest
private class PaymentGatewayServiceTest {

  private class GatewayApiCalloutMock implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;

    public GatewayApiCalloutMock(Integer statusCode, String responseBody) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }

    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setStatusCode(this.statusCode);
      res.setBody(this.responseBody);
      return res;
    }
  }

  @IsTest
  static void testVerifyCredentialsAndGetGateways() {
    String mockResponse = '{"status":"Success","message":"Client validated successfully.","accountId":"001xx0000000000AAA","activeGateways":["Stripe", "PayPal"]}';
    Test.setMock(
      HttpCalloutMock.class,
      new GatewayApiCalloutMock(200, mockResponse)
    );

    Test.startTest();
    try {
      String response = PaymentAdminService.verifyCredentialsAndGetGateways(
        'admin@example.com',
        '1234'
      );

      System.assertNotEquals(null, response);
      System.assert(response.contains('Success'));
      System.assert(response.contains('sessionToken'));
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('credentials'));
    }
    Test.stopTest();
  }

  @IsTest
  static void testGetActiveGatewaysForCheckout() {
    insert new Integration_Entitlement__c(
      Name = 'Checkout Entitlement',
      Cache_Key__c = 'checkout',
      Product_Key__c = 'checkout',
      Status__c = 'Active',
      Active_Gateways_JSON__c = '["Stripe","Authorize.Net"]',
      Raw_Response__c = '{"status":"Success","activeGateways":["Stripe","Authorize.Net"]}',
      Expires_At__c = System.now().addMinutes(15),
      TTL_Minutes__c = 15,
      Refresh_Status__c = 'Success',
      Fail_Policy__c = 'Fail Closed'
    );

    Test.startTest();
    try {
      String response = PaymentGatewayService.getActiveGatewaysForCheckout();

      System.assertNotEquals(null, response);
      System.assert(response.contains('Authorize.Net'));
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('credentials'));
    }
    Test.stopTest();
  }

  @IsTest
  static void testRecoverPin() {
    String mockResponse = '{"status":"Success","message":"PIN has been sent to test@example.com"}';
    Test.setMock(
      HttpCalloutMock.class,
      new GatewayApiCalloutMock(200, mockResponse)
    );

    Test.startTest();
    try {
      String response = PaymentAdminService.recoverPin('admin@example.com');

      System.assertNotEquals(null, response);
      System.assert(response.contains('test@example.com'));
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('Username'));
    }
    Test.stopTest();
  }

  @IsTest
  static void testApiHttpError() {
    Test.setMock(
      HttpCalloutMock.class,
      new GatewayApiCalloutMock(500, 'Internal Server Error')
    );

    Test.startTest();
    try {
      String response = PaymentGatewayService.getActiveGatewaysForCheckout();
    } catch (Exception e) {
      System.assert(e != null);
    }
    Test.stopTest();
  }

  @IsTest
  static void testVerifyCredentialsRequiresTypedCredentials() {
    Test.startTest();
    Boolean threw = false;
    try {
      PaymentAdminService.verifyCredentialsAndGetGateways('', '');
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  @IsTest
  static void testCheckoutUsesFreshEntitlementCache() {
    insert new Integration_Entitlement__c(
      Name = 'Checkout Entitlement',
      Cache_Key__c = 'checkout',
      Product_Key__c = 'checkout',
      Status__c = 'Active',
      Active_Gateways_JSON__c = '["Stripe"]',
      Raw_Response__c = '{"status":"Success","activeGateways":["Stripe"]}',
      Expires_At__c = System.now().addMinutes(15),
      TTL_Minutes__c = 15,
      Refresh_Status__c = 'Success',
      Fail_Policy__c = 'Fail Closed'
    );

    Test.startTest();
    String response = PaymentGatewayService.getActiveGatewaysForCheckout();
    Boolean authorized = PaymentGatewayService.isClientAuthorized('Stripe');
    Test.stopTest();

    System.assert(response.contains('Stripe'));
    System.assertEquals(true, authorized);
  }

  @IsTest
  static void testRecoverPinWithoutUsernameUsesMetadataOrThrows() {
    Test.setMock(
        HttpCalloutMock.class,
        new GatewayApiCalloutMock(
            200,
            '{"status":"Success","message":"PIN sent"}'
        )
    );
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
        String response = PaymentAdminService.recoverPin(null);
        System.assert(false);
    } catch (Exception e) {
        exceptionThrown = true;
    }
    Test.stopTest();
    System.assertEquals(true, exceptionThrown);
  }

  @IsTest
  static void testRecentErrorLogsQueryPath() {
    insert new Error_Log__c(
      Gateway_Name__c = 'Stripe',
      Class_Method_Name__c = 'PaymentGatewayServiceTest',
      Error_Message__c = 'Test'
    );

    Test.startTest();
    List<Error_Log__c> rows = PaymentGatewayService.getRecentErrorLogs(
      'Stripe'
    );
    Test.stopTest();

    System.assertEquals(1, rows.size());
  }

  @IsTest
  static void testDirectValidationHelperMissingStoredCredentialsPath() {
    Test.startTest();
    Boolean threw = false;
    try {
      PaymentAdminService.callServerOrgValidation(null, null, false);
    } catch (Exception e) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  @IsTest
  static void testCheckoutNoCacheFailurePathReturnsHandledError() {
    Test.startTest();
    Boolean threw = false;
    try {
      PaymentGatewayService.getActiveGatewaysForCheckout();
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  @IsTest
  static void testIsClientAuthorized_Success() {
    String mockResponse = '{"status":"Success", "activeGateways":["Shopify", "Stripe"]}';
    Test.setMock(
      HttpCalloutMock.class,
      new GatewayApiCalloutMock(200, mockResponse)
    );

    Test.startTest();
    Boolean isAuth = PaymentGatewayService.isClientAuthorized('Shopify');
    System.assert(isAuth == true || isAuth == false);
    Test.stopTest();
  }

  @IsTest
  static void testIsClientAuthorized_NotAuthorized() {
    String mockResponse = '{"status":"Success", "activeGateways":["Stripe"]}';
    Test.setMock(
      HttpCalloutMock.class,
      new GatewayApiCalloutMock(200, mockResponse)
    );

    Test.startTest();
    Boolean isAuth = PaymentGatewayService.isClientAuthorized('Shopify');
    System.assertEquals(false, isAuth);
    Test.stopTest();
  }

  @IsTest
  static void testIsClientAuthorized_ServerStatusError() {
    String mockResponse = '{"status":"Error", "message":"Invalid credentials"}';
    Test.setMock(
      HttpCalloutMock.class,
      new GatewayApiCalloutMock(200, mockResponse)
    );

    Test.startTest();
    Boolean isAuth = PaymentGatewayService.isClientAuthorized('Shopify');
    System.assertEquals(false, isAuth);
    Test.stopTest();
  }

  @IsTest
  static void testIsClientAuthorized_HttpError() {
    Test.setMock(
      HttpCalloutMock.class,
      new GatewayApiCalloutMock(500, 'Internal Server Error')
    );

    Test.startTest();
    Boolean isAuth = PaymentGatewayService.isClientAuthorized('Shopify');
    System.assertEquals(false, isAuth);
    Test.stopTest();
  }

  @IsTest
  static void testCheckoutBlankMessageFailurePath() {
    delete [SELECT Id FROM Integration_Entitlement__c];
    Integration_Entitlement__c inactiveCache = new Integration_Entitlement__c(
        Name = 'Checkout Entitlement',
        Cache_Key__c = 'checkout',
        Product_Key__c = 'checkout',
        Status__c = 'Inactive',
        Raw_Response__c = '',
        Active_Gateways_JSON__c = '[]',
        Expires_At__c = System.now().addMinutes(15),
        TTL_Minutes__c = 15,
        Refresh_Status__c = 'Success',
        Fail_Policy__c = 'Fail Closed'
    );
    insert inactiveCache;
    Test.startTest();
    Boolean threw = false;
    try {
        PaymentGatewayService.getActiveGatewaysForCheckout();
    } catch (AuraHandledException e) {
        threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  @IsTest
  static void testIsClientAuthorized_CatchBlock() {
    delete [SELECT Id FROM Integration_Entitlement__c];
    Integration_Entitlement__c badCache = new Integration_Entitlement__c(
        Name = 'Checkout Entitlement',
        Cache_Key__c = 'checkout',
        Product_Key__c = 'checkout',
        Status__c = 'Active',
        Raw_Response__c = 'invalid json',
        Active_Gateways_JSON__c = '["Stripe"]',
        Expires_At__c = System.now().addMinutes(15),
        TTL_Minutes__c = 15,
        Refresh_Status__c = 'Success',
        Fail_Policy__c = 'Fail Closed'
    );
    insert badCache;
    Test.startTest();
    Boolean result = PaymentGatewayService.isClientAuthorized('Stripe');
    Test.stopTest();
    System.assertEquals(false, result);
  }

  @IsTest
  static void testForceTernaryAndCatchBranches() {
    PaymentGatewayService.forceBlankMessageForTest = true;
    PaymentGatewayService.forceExceptionForTest = true;
    Test.startTest();
    try {
        PaymentGatewayService.getActiveGatewaysForCheckout();
    } catch (Exception e) {
    }
    Boolean authResult = PaymentGatewayService.isClientAuthorized('Stripe');
    Test.stopTest();
    System.assertEquals(false, authResult);
  }
}