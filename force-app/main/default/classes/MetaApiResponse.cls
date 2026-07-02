public class MetaApiResponse {
    public Integer statusCode;
    public String rawBody;
    public List<Map<String, Object>> data = new List<Map<String, Object>>();
    public String nextUrl;
    public String errorMessage;

    public static MetaApiResponse fromHttpResponse(HttpResponse response) {
        MetaApiResponse result = new MetaApiResponse();
        result.statusCode = response == null ? 0 : response.getStatusCode();
        result.rawBody = response == null ? null : response.getBody();
        if (String.isBlank(result.rawBody)) {
            return result;
        }

        try {
            Object parsed = JSON.deserializeUntyped(result.rawBody);
            if (!(parsed instanceof Map<String, Object>)) {
                return result;
            }
            Map<String, Object> root = (Map<String, Object>) parsed;
            if (root.containsKey('data') && root.get('data') instanceof List<Object>) {
                for (Object item : (List<Object>) root.get('data')) {
                    if (item instanceof Map<String, Object>) {
                        result.data.add((Map<String, Object>) item);
                    }
                }
            }
            if (root.containsKey('paging') && root.get('paging') instanceof Map<String, Object>) {
                Map<String, Object> paging = (Map<String, Object>) root.get('paging');
                result.nextUrl = stringValue(paging.get('next'));
            }
            if (root.containsKey('error') && root.get('error') instanceof Map<String, Object>) {
                Map<String, Object> error = (Map<String, Object>) root.get('error');
                result.errorMessage = stringValue(error.get('message'));
            }
        } catch (Exception e) {
            result.errorMessage = 'Malformed Meta API response: ' + e.getMessage();
        }
        return result;
    }

    public Boolean isSuccess() {
        return statusCode >= 200 && statusCode < 300 && String.isBlank(errorMessage);
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}