@IsTest
private class KlaviyoAuthServiceTest {
    @IsTest
    static void endpointsResolveThroughNamedCredential() {
        System.assertEquals(
            'callout:Klaviyo_API/api/profiles',
            KlaviyoAuthService.toNamedCredentialEndpoint('https://a.klaviyo.com/api/profiles')
        );
        System.assertEquals(
            'callout:Klaviyo_API/api/events?filter=x',
            KlaviyoAuthService.toNamedCredentialEndpoint('/api/events?filter=x')
        );
    }

    @IsTest
    static void buildRequestDoesNotSetPlaintextAuthorization() {
        HttpRequest request = KlaviyoAuthService.buildGetRequest('/api/lists');

        System.assertEquals('GET', request.getMethod());
        System.assertEquals('callout:Klaviyo_API/api/lists', request.getEndpoint());
        System.assertEquals(KlaviyoAuthService.API_REVISION, request.getHeader('revision'));
        System.assertEquals(null, request.getHeader('Authorization'));
    }
}