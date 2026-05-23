public with sharing class KlaviyoAuthService {
    public static final String NAMED_CREDENTIAL = 'Klaviyo_API';
    public static final String NAMED_CREDENTIAL_ENDPOINT = 'callout:' + NAMED_CREDENTIAL;
    public static final String API_REVISION = '2025-01-15';

    public class KlaviyoConfigurationException extends Exception {}

    public static HttpRequest buildGetRequest(String endpoint) {
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        prepareRequest(request, endpoint);
        return request;
    }

    public static void prepareRequest(HttpRequest request, String endpoint) {
        if (request == null) {
            throw new KlaviyoConfigurationException('Klaviyo request is missing.');
        }
        request.setEndpoint(toNamedCredentialEndpoint(endpoint));
        request.setHeader('Accept', 'application/json');
        request.setHeader('revision', API_REVISION);
    }

    @TestVisible
    static String toNamedCredentialEndpoint(String endpoint) {
        String safeEndpoint = String.isBlank(endpoint) ? null : endpoint.trim();
        if (String.isBlank(safeEndpoint)) {
            throw new KlaviyoConfigurationException('Klaviyo endpoint is missing.');
        }

        if (safeEndpoint.startsWith('callout:')) {
            return safeEndpoint;
        }

        if (safeEndpoint.startsWith('/')) {
            return NAMED_CREDENTIAL_ENDPOINT + safeEndpoint;
        }

        String lowerEndpoint = safeEndpoint.toLowerCase();
        if (lowerEndpoint.startsWith('http://') || lowerEndpoint.startsWith('https://')) {
            Integer apiIndex = lowerEndpoint.indexOf('/api/');
            if (apiIndex >= 0) {
                return NAMED_CREDENTIAL_ENDPOINT + safeEndpoint.substring(apiIndex);
            }

            Integer schemeIndex = lowerEndpoint.indexOf('://');
            Integer pathIndex = safeEndpoint.indexOf('/', schemeIndex + 3);
            if (pathIndex >= 0) {
                return NAMED_CREDENTIAL_ENDPOINT + safeEndpoint.substring(pathIndex);
            }

            throw new KlaviyoConfigurationException('Klaviyo endpoint path is missing.');
        }

        return NAMED_CREDENTIAL_ENDPOINT + '/' + safeEndpoint;
    }
}
