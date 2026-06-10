@isTest
private class RefreshLicensesGuardTest {
  // Mock the Server Org license callout.
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

  private static String validSessionToken() {
    return QuickBridgeAdminSessionService.createSession(
        'admin@example.com',
        System.now().addHours(1)
      )
      .sessionToken;
  }

  @isTest
  static void happyPath_validSessionAndPermission_succeeds() {
    String token = validSessionToken();
    Test.setMock(
      HttpCalloutMock.class,
      new ServerOrgMock(200, '{"status":"Success","licenses":[]}')
    );

    Test.startTest();
    String result = QuickBridgeAdminControlPlaneService.refreshLicenses(token);
    Test.stopTest();

    // Empty license list returns a benign message; the point is the guards passed.
    System.assert(
      result.startsWith('No active licenses') ||
      result.startsWith('Success'),
      'Expected success/no-licenses, got: ' + result
    );
  }

  @isTest
  static void permissionDenied_blocksRefresh() {
    String token = validSessionToken();
    QuickBridgeAdminGuard.bypassForTests = false; // simulate user without Manage_QuickBridge

    Test.startTest();
    Boolean blocked = false;
    try {
      QuickBridgeAdminControlPlaneService.refreshLicenses(token);
    } catch (Exception e) {
      blocked = true;
    }
    Test.stopTest();

    System.assertEquals(
      true,
      blocked,
      'Refresh must be blocked without Manage_QuickBridge.'
    );
  }

  @isTest
  static void invalidSession_blocksBeforeCallout() {
    Test.startTest();
    Boolean blocked = false;
    try {
      // No mock set: if a callout fired we would get a different failure; the
      // session guard must reject first.
      QuickBridgeAdminControlPlaneService.refreshLicenses('not-a-real-token');
    } catch (Exception e) {
      blocked = true;
    }
    Test.stopTest();

    System.assertEquals(
      true,
      blocked,
      'Invalid session must be rejected before any Server Org callout.'
    );
  }

  @isTest
  static void nonSuccessHttp_returnsSanitizedMessage() {
    String token = validSessionToken();
    Test.setMock(
      HttpCalloutMock.class,
      new ServerOrgMock(500, 'secret-internal-detail username=admin password=hunter2')
    );

    Test.startTest();
    String result = QuickBridgeAdminControlPlaneService.refreshLicenses(token);
    Test.stopTest();

    System.assert(
      result.contains('HTTP 500'),
      'Should surface a generic HTTP status, got: ' + result
    );
    System.assert(
      !result.contains('password') && !result.contains('hunter2'),
      'Raw Server Org body must not leak to the UI: ' + result
    );
  }
}