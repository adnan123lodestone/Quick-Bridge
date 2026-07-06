@IsTest
private class NetSuiteApiClientTest {
  @IsTest
  static void suiteqlPostsThroughNamedCredentialWithPreferHeader() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());

    SuiteQLMock mock = new SuiteQLMock(200, '{"items":[{"id":"42","companyName":"Acme"}],"hasMore":false}');
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    List<Map<String, Object>> rows = NetSuiteApiClient.configured()
      .suiteql('SELECT id, companyName FROM customer', null);
    Test.stopTest();

    System.assertEquals(1, rows.size());
    System.assertEquals('42', String.valueOf(rows[0].get('id')));
    System.assertEquals('POST', mock.method);
    System.assert(mock.endpoint.startsWith('callout:NetSuite_TBA'));
    System.assert(mock.endpoint.contains('/services/rest/query/v1/suiteql'));
    System.assertEquals('transient', mock.preferHeader);
    System.assert(mock.body.contains('SELECT id, companyName FROM customer'));
  }

  @IsTest
  static void failedRequestRaisesSanitizedException() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());

    Test.setMock(HttpCalloutMock.class, new SuiteQLMock(401, '{"title":"Invalid login","detail":"token_secret=abc123"}'));

    try {
      NetSuiteApiClient.configured().suiteql('SELECT id FROM customer', null);
      System.assert(false, 'Expected failed SuiteQL request.');
    } catch (NetSuiteApiClient.NetSuiteApiClientException expected) {
      System.assert(!expected.getMessage().contains('abc123'), 'Secrets must be redacted.');
    }
  }

  @IsTest
  static void requestSignerBuildsDeterministicTbaHeader() {
    NetSuiteRequestSigner.SigningInput input = new NetSuiteRequestSigner.SigningInput();
    input.realm = '123456_SB1';
    input.consumerKey = 'consumerKey';
    input.consumerSecret = 'consumerSecret';
    input.tokenId = 'tokenId';
    input.tokenSecret = 'tokenSecret';
    input.httpMethod = 'POST';
    input.url = 'https://123456-sb1.suitetalk.api.netsuite.com/services/rest/query/v1/suiteql';
    input.nonce = 'nonce-1';
    input.timestamp = '1700000000';
    input.queryParams = new Map<String, String>{ 'limit' => '1000', 'offset' => '0' };

    String header = NetSuiteRequestSigner.authorizationHeader(input);

    System.assert(header.startsWith('OAuth realm="123456_SB1"'));
    System.assert(header.contains('oauth_signature_method="HMAC-SHA256"'));
    System.assert(header.contains('oauth_signature='));
    System.assert(!header.contains('consumerSecret'));
    System.assert(!header.contains('tokenSecret'));
  }

  @IsTest
  static void apiResponseAndErrorMapperClassifyFailures() {
    HttpResponse response = new HttpResponse();
    response.setStatusCode(429);
    response.setBody('{"title":"Governance limit","items":[{"id":"1"}],"hasMore":true,"count":1}');

    NetSuiteApiResponse parsed = NetSuiteApiResponse.fromHttpResponse(response);

    System.assertEquals(429, parsed.statusCode);
    System.assertEquals(true, parsed.hasMore);
    System.assertEquals(1, parsed.items.size());
    System.assertEquals(false, parsed.isSuccess());
    System.assert(
      NetSuiteErrorMapper.userMessage(429, parsed.errorMessage).contains('governance'),
      'Expected a governance-safe message.'
    );
    System.assert(NetSuiteErrorMapper.userMessage(403, 'denied').contains('permission'));
    System.assert(NetSuiteErrorMapper.userMessage(500, 'server').contains('temporarily unavailable'));
    System.assert(NetSuiteErrorMapper.userMessage(400, 'missing customer').contains('Customer'));
    System.assert(NetSuiteErrorMapper.userMessage(400, 'closed period').contains('closed'));
    System.assert(NetSuiteErrorMapper.userMessage(400, 'duplicate transaction').contains('duplicate'));
    NetSuiteErrorMapper.logCalloutFailure(
      'NetSuiteApiClientTest.apiResponseAndErrorMapperClassifyFailures',
      'token_secret=abc123',
      401,
      'callout:NetSuite_TBA/services/rest/query/v1/suiteql'
    );
    System.assertEquals(
      1,
      [SELECT count() FROM Error_Log__c WHERE Gateway_Name__c = 'NetSuite']
    );
  }

  @IsTest
  static void httpVerbsUseNamedCredentialEndpoint() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    VerbMock mock = new VerbMock();
    Test.setMock(HttpCalloutMock.class, mock);

    NetSuiteApiClient client = NetSuiteApiClient.configured();
    client.get('/services/rest/record/v1/customer/1', new Map<String, String>{ 'expandSubResources' => 'true' });
    client.post('/services/rest/record/v1/customer', new Map<String, Object>{ 'companyName' => 'Acme' });
    client.patch('/services/rest/record/v1/customer/1', new Map<String, Object>{ 'phone' => '555' });
    client.put('/services/rest/record/v1/customer/1', new Map<String, Object>{ 'phone' => '555' });
    client.deletePath('/services/rest/record/v1/customer/1');

    System.assertEquals(
      new List<String>{ 'GET', 'POST', 'PATCH', 'PUT', 'DELETE' },
      mock.methods
    );
    System.assert(mock.lastEndpoint.startsWith('callout:NetSuite_TBA'));
  }

  private class SuiteQLMock implements HttpCalloutMock {
    Integer statusCode;
    String responseBody;
    String method;
    String endpoint;
    String preferHeader;
    String body;

    SuiteQLMock(Integer statusCode, String responseBody) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest request) {
      method = request.getMethod();
      endpoint = request.getEndpoint();
      preferHeader = request.getHeader('Prefer');
      body = request.getBody();
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(responseBody);
      return response;
    }
  }

  private class VerbMock implements HttpCalloutMock {
    List<String> methods = new List<String>();
    String lastEndpoint;
    public HttpResponse respond(HttpRequest request) {
      methods.add(request.getMethod());
      lastEndpoint = request.getEndpoint();
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{}');
      return response;
    }
  }

}
