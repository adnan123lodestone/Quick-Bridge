public with sharing class NetSuiteApiClient {
  private static final Integer DEFAULT_LIMIT = 1000;
  private static final Integer MAX_PAGES = 50;

  private final NetSuiteConfigService.Config config;

  private NetSuiteApiClient(NetSuiteConfigService.Config config) {
    this.config = config;
  }

  public static NetSuiteApiClient configured() {
    return new NetSuiteApiClient(NetSuiteConfigService.requireConfigured());
  }

  public NetSuiteApiResponse get(String path, Map<String, String> queryParams) {
    return send('GET', appendQuery(path, queryParams), null);
  }

  public NetSuiteApiResponse post(String path, Object body) {
    return send('POST', path, body);
  }

  public NetSuiteApiResponse patch(String path, Object body) {
    return send('PATCH', path, body);
  }

  public NetSuiteApiResponse put(String path, Object body) {
    return send('PUT', path, body);
  }

  public NetSuiteApiResponse deleteRequest(String path) {
    return send('DELETE', path, null);
  }

  public NetSuiteApiResponse deletePath(String path) {
    return deleteRequest(path);
  }

  public List<Map<String, Object>> suiteql(String query, Map<String, Object> parameters) {
    if (String.isBlank(query)) {
      throw new NetSuiteApiClientException('SuiteQL query is required.');
    }
    List<Map<String, Object>> rows = new List<Map<String, Object>>();
    Integer offset = 0;
    Integer guard = 0;
    Boolean hasMore = true;
    while (hasMore) {
      guard++;
      if (guard > MAX_PAGES) {
        throw new NetSuiteApiClientException('NetSuite SuiteQL pagination exceeded the safety limit.');
      }
      Map<String, Object> payload = new Map<String, Object>{'q' => query};
      if (parameters != null && !parameters.isEmpty()) {
        payload.put('params', parameters);
      }
      String path = appendQuery(config.suiteqlUrl, new Map<String, String>{
        'limit' => String.valueOf(DEFAULT_LIMIT),
        'offset' => String.valueOf(offset)
      });
      NetSuiteApiResponse response = send('POST', path, payload);
      rows.addAll(response.items);
      hasMore = response.hasMore == true;
      Integer countValue = response.count == null ? response.items.size() : response.count;
      offset += countValue == null || countValue <= 0 ? DEFAULT_LIMIT : countValue;
    }
    return rows;
  }

  private NetSuiteApiResponse send(String method, String path, Object body) {
    HttpRequest request = new HttpRequest();
    request.setMethod(method);
    request.setEndpoint(toEndpoint(path));
    request.setTimeout(120000);
    request.setHeader('Accept', 'application/json');
    request.setHeader('Content-Type', 'application/json');
    if (path != null && path.contains('/suiteql')) {
      request.setHeader('Prefer', 'transient');
    }
    if (body != null) {
      request.setBody(JSON.serialize(body));
    }
    try {
      HttpResponse httpResponse = new Http().send(request);
      NetSuiteApiResponse response = NetSuiteApiResponse.fromHttpResponse(httpResponse);
      if (!response.isSuccess()) {
        String message = NetSuiteErrorMapper.userMessage(response.statusCode, response.errorMessage);
        NetSuiteErrorMapper.logCalloutFailure(
          'NetSuiteApiClient.send',
          message,
          response.statusCode,
          request.getEndpoint()
        );
        throw new NetSuiteApiClientException(message);
      }
      return response;
    } catch (NetSuiteApiClientException e) {
      throw e;
    } catch (Exception e) {
      NetSuiteErrorMapper.logException('NetSuiteApiClient.send', e);
      throw new NetSuiteApiClientException(NetSuiteErrorMapper.sanitize(e.getMessage()));
    }
  }

  private String toEndpoint(String pathOrUrl) {
    String safePath = String.isBlank(pathOrUrl) ? '' : pathOrUrl.trim();
    if (String.isBlank(safePath)) {
      throw new NetSuiteApiClientException('NetSuite API path is required.');
    }
    if (safePath.startsWith('callout:')) {
      return safePath;
    }
    if (safePath.toLowerCase().startsWith('http://') || safePath.toLowerCase().startsWith('https://')) {
      Integer schemeIndex = safePath.indexOf('://');
      Integer pathIndex = safePath.indexOf('/', schemeIndex + 3);
      safePath = pathIndex >= 0 ? safePath.substring(pathIndex) : '/';
    }
    if (!safePath.startsWith('/')) {
      safePath = '/' + safePath;
    }
    return 'callout:' + config.namedCredentialName + safePath;
  }

  private static String appendQuery(String path, Map<String, String> params) {
    if (params == null || params.isEmpty()) {
      return path;
    }
    List<String> pairs = new List<String>();
    for (String key : params.keySet()) {
      if (String.isBlank(key) || params.get(key) == null) {
        continue;
      }
      pairs.add(urlEncode(key) + '=' + urlEncode(params.get(key)));
    }
    if (pairs.isEmpty()) {
      return path;
    }
    String separator = path != null && path.contains('?') ? '&' : '?';
    return path + separator + String.join(pairs, '&');
  }

  private static String urlEncode(String value) {
    return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
  }

  public class NetSuiteApiClientException extends Exception {}
}
