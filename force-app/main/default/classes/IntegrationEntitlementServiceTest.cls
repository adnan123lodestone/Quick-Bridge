@IsTest
private class IntegrationEntitlementServiceTest {
  private class EntitlementMock implements HttpCalloutMock {
    private Integer statusCode;
    private String body;

    EntitlementMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setHeader('Content-Type', 'application/json');
      response.setBody(body);
      return response;
    }
  }

  @IsTest
  static void loginRefreshUsesSuppliedCredentialsAndCachesGateways() {
    Test.setMock(
      HttpCalloutMock.class,
      new EntitlementMock(
        200,
        '{"status":"Success","message":"ok","activeGateways":["Shopify","Stripe"]}'
      )
    );

    Test.startTest();
    IntegrationEntitlementService.EntitlementResult result = IntegrationEntitlementService.refreshCheckoutEntitlementForLogin(
      'user@example.com',
      '1234'
    );
    Test.stopTest();

    System.assertEquals(true, result.active);
    System.assertEquals(2, result.activeGateways.size());
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Integration_Entitlement__c
        WHERE Cache_Key__c = 'checkout'
      ]
    );
  }

  @IsTest
  static void cacheHitAuthorizesGatewayWithoutCallout() {
    insert new Integration_Entitlement__c(
      Name = 'Checkout Entitlement',
      Cache_Key__c = 'checkout',
      Product_Key__c = 'checkout',
      Status__c = 'Active',
      Active_Gateways_JSON__c = '["Shopify"]',
      Raw_Response__c = '{"status":"Success","activeGateways":["Shopify"]}',
      Expires_At__c = System.now().addMinutes(15),
      TTL_Minutes__c = 15,
      Refresh_Status__c = 'Success',
      Fail_Policy__c = 'Fail Closed'
    );

    System.assertEquals(
      true,
      IntegrationEntitlementService.isGatewayAuthorized('Shopify')
    );
    System.assertEquals(
      false,
      IntegrationEntitlementService.isGatewayAuthorized('Stripe')
    );
  }

  @IsTest
  static void staleFailOpenCacheAllowsRuntimeWithoutCallout() {
    insert new Integration_Entitlement__c(
      Name = 'Checkout Entitlement',
      Cache_Key__c = 'checkout',
      Product_Key__c = 'checkout',
      Status__c = 'Active',
      Active_Gateways_JSON__c = '["Stripe"]',
      Raw_Response__c = '{"status":"Success","activeGateways":["Stripe"]}',
      Expires_At__c = System.now().addMinutes(-5),
      TTL_Minutes__c = 15,
      Refresh_Status__c = 'Success',
      Fail_Policy__c = 'Fail Open'
    );

    Test.startTest();
    IntegrationEntitlementService.EntitlementResult result = IntegrationEntitlementService.getCheckoutEntitlement();
    Boolean stripeAuthorized = IntegrationEntitlementService.isGatewayAuthorized(
      'Stripe'
    );
    Test.stopTest();

    System.assertEquals(true, result.active);
    System.assertEquals(true, result.cacheHit);
    System.assertEquals(true, stripeAuthorized);
  }

  @IsTest
  static void staleFailClosedCacheDeniesRuntimeWithoutCallout() {
    insert new Integration_Entitlement__c(
      Name = 'Checkout Entitlement',
      Cache_Key__c = 'checkout',
      Product_Key__c = 'checkout',
      Status__c = 'Active',
      Active_Gateways_JSON__c = '["Stripe"]',
      Raw_Response__c = '{"status":"Success","activeGateways":["Stripe"]}',
      Expires_At__c = System.now().addMinutes(-5),
      TTL_Minutes__c = 15,
      Refresh_Status__c = 'Success',
      Fail_Policy__c = 'Fail Closed'
    );

    Test.startTest();
    IntegrationEntitlementService.EntitlementResult result = IntegrationEntitlementService.getCheckoutEntitlement();
    Boolean stripeAuthorized = IntegrationEntitlementService.isGatewayAuthorized(
      'Stripe'
    );
    Test.stopTest();

    System.assertEquals(false, result.active);
    System.assertEquals(true, result.cacheHit);
    System.assertEquals(false, stripeAuthorized);
  }

  @IsTest
  static void refreshPreservesExistingFailPolicy() {
    insert new Integration_Entitlement__c(
      Name = 'Checkout Entitlement',
      Cache_Key__c = 'checkout',
      Product_Key__c = 'checkout',
      Status__c = 'Active',
      Raw_Response__c = '{"status":"Success","activeGateways":["Stripe"]}',
      Expires_At__c = System.now().addMinutes(-5),
      TTL_Minutes__c = 15,
      Refresh_Status__c = 'Success',
      Fail_Policy__c = 'Fail Open'
    );
    Test.setMock(
      HttpCalloutMock.class,
      new EntitlementMock(
        200,
        '{"status":"Success","message":"ok","activeGateways":["PayPal"]}'
      )
    );

    Test.startTest();
    IntegrationEntitlementService.requestCheckoutRefresh();
    Test.stopTest();

    Integration_Entitlement__c refreshed = [
      SELECT Fail_Policy__c, Refresh_Status__c, Active_Gateways_JSON__c
      FROM Integration_Entitlement__c
      WHERE Cache_Key__c = 'checkout'
      LIMIT 1
    ];
    System.assertEquals('Fail Open', refreshed.Fail_Policy__c);
    System.assertEquals('Success', refreshed.Refresh_Status__c);
    System.assert(refreshed.Active_Gateways_JSON__c.contains('PayPal'));
  }
}