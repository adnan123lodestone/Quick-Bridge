public with sharing class MetaApiClient {
    private final String namedCredential;
    private final String graphApiVersion;

    private MetaApiClient(String namedCredential, String graphApiVersion) {
        this.namedCredential = namedCredential;
        this.graphApiVersion = graphApiVersion;
    }

    public static MetaApiClient configured() {
        MetaConfigService.requireConfiguredForApiSync();
        return new MetaApiClient(MetaConfigService.namedCredential(), MetaConfigService.graphApiVersion());
    }

    public List<Map<String, Object>> getAll(String path, Map<String, String> params) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        String nextPath = appendQuery(path, params);
        Integer guard = 0;
        while (String.isNotBlank(nextPath)) {
            guard++;
            if (guard > 50) {
                throw new MetaApiClientException('Meta API pagination exceeded the safety limit.');
            }
            MetaApiResponse response = sendGet(nextPath);
            rows.addAll(response.data);
            nextPath = response.nextUrl;
        }
        return rows;
    }

    public Map<String, Object> getObject(String path, Map<String, String> params) {
        MetaApiResponse response = sendGet(appendQuery(path, params));
        if (!response.data.isEmpty()) {
            return response.data[0];
        }
        if (String.isBlank(response.rawBody)) {
            return new Map<String, Object>();
        }
        Object parsed = JSON.deserializeUntyped(response.rawBody);
        return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : new Map<String, Object>();
    }

    private MetaApiResponse sendGet(String pathOrUrl) {
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(toEndpoint(pathOrUrl));
        request.setHeader('Accept', 'application/json');
        request.setTimeout(120000);
        try {
            HttpResponse httpResponse = new Http().send(request);
            MetaApiResponse response = MetaApiResponse.fromHttpResponse(httpResponse);
            if (!response.isSuccess()) {
                String message = MetaErrorMapper.userMessage(response.statusCode, response.errorMessage);
                MetaErrorMapper.logCalloutFailure(
                    'MetaApiClient.sendGet',
                    message,
                    response.statusCode,
                    request.getEndpoint()
                );
                throw new MetaApiClientException(message);
            }
            return response;
        } catch (MetaApiClientException e) {
            throw e;
        } catch (Exception e) {
            MetaErrorMapper.logException('MetaApiClient.sendGet', e);
            throw new MetaApiClientException(MetaErrorMapper.sanitize(e.getMessage()));
        }
    }

    private String toEndpoint(String pathOrUrl) {
        String safePath = String.isBlank(pathOrUrl) ? '' : pathOrUrl.trim();
        if (String.isBlank(safePath)) {
            throw new MetaApiClientException('Meta API path is required.');
        }
        if (safePath.startsWith('callout:')) {
            return safePath;
        }
        if (safePath.toLowerCase().startsWith('http://') || safePath.toLowerCase().startsWith('https://')) {
            Integer schemeIndex = safePath.indexOf('://');
            Integer pathIndex = safePath.indexOf('/', schemeIndex + 3);
            safePath = pathIndex >= 0 ? safePath.substring(pathIndex) : '';
            if (safePath.startsWith('/' + graphApiVersion + '/')) {
                safePath = safePath.substring(graphApiVersion.length() + 1);
            }
        }
        if (!safePath.startsWith('/')) {
            safePath = '/' + safePath;
        }
        if (!safePath.startsWith('/' + graphApiVersion + '/')) {
            safePath = '/' + graphApiVersion + safePath;
        }
        return 'callout:' + namedCredential + safePath;
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

    public class MetaApiClientException extends Exception {}
}