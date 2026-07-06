public class NetSuiteApiResponse {
  public Integer statusCode;
  public String rawBody;
  public Map<String, Object> body = new Map<String, Object>();
  public List<Map<String, Object>> items = new List<Map<String, Object>>();
  public Boolean hasMore;
  public Integer offset;
  public Integer count;
  public Integer totalResults;
  public String errorMessage;

  public static NetSuiteApiResponse fromHttpResponse(HttpResponse response) {
    NetSuiteApiResponse result = new NetSuiteApiResponse();
    result.statusCode = response == null ? 0 : response.getStatusCode();
    result.rawBody = response == null ? null : response.getBody();
    if (String.isBlank(result.rawBody)) {
      return result;
    }
    try {
      Object parsed = JSON.deserializeUntyped(result.rawBody);
      if (parsed instanceof Map<String, Object>) {
        result.body = (Map<String, Object>) parsed;
        result.hasMore = booleanValue(result.body.get('hasMore'));
        result.offset = integerValue(result.body.get('offset'));
        result.count = integerValue(result.body.get('count'));
        result.totalResults = integerValue(result.body.get('totalResults'));
        result.errorMessage = firstNonBlank(stringValue(result.body.get('title')), stringValue(result.body.get('detail')));
        if (result.body.containsKey('items') && result.body.get('items') instanceof List<Object>) {
          for (Object item : (List<Object>) result.body.get('items')) {
            if (item instanceof Map<String, Object>) {
              result.items.add((Map<String, Object>) item);
            }
          }
        }
      }
    } catch (Exception e) {
      result.errorMessage = 'Malformed NetSuite API response: ' + e.getMessage();
    }
    return result;
  }

  public Boolean isSuccess() {
    return statusCode >= 200 && statusCode < 300 && String.isBlank(errorMessage);
  }

  private static Boolean booleanValue(Object value) {
    if (value == null) {
      return false;
    }
    if (value instanceof Boolean) {
      return (Boolean) value;
    }
    return String.valueOf(value).equalsIgnoreCase('true');
  }

  private static Integer integerValue(Object value) {
    if (value == null) {
      return null;
    }
    try {
      return Integer.valueOf(String.valueOf(value));
    } catch (Exception ignored) {
      return null;
    }
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static String firstNonBlank(String firstValue, String secondValue) {
    return String.isBlank(firstValue) ? secondValue : firstValue;
  }
}
