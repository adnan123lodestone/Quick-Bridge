public with sharing class ShopifyConfigService {
    public class ShopifyConfigException extends Exception {}

    public class Config {
        public String storeUrl;
        public String accessToken;
        public String apiKey;
        public String apiSecret;
        public Boolean isActive;
    }

    public static Config getConfig() {
        if (Test.isRunningTest()) {
            Config mockConfig = new Config();
            mockConfig.storeUrl = 'https://mock-shopify.com';
            mockConfig.accessToken = 'mock_token';
            mockConfig.apiKey = 'mock_api_key';
            mockConfig.apiSecret = 'mock_api_secret';
            mockConfig.isActive = true;
            return mockConfig;
        }

        Quickbridge_Config__mdt metadata = Quickbridge_Config__mdt.getInstance('Shopify');
        if (metadata == null) {
            ErrorLogUtility.logError(buildConfigLog('Shopify configuration metadata record is missing.'));
            throw new ShopifyConfigException('Shopify configuration metadata record is missing.');
        }

        Config config = new Config();
        config.storeUrl = normalizeStoreUrl(metadata.Shopify_Store_URL__c);
        config.accessToken = metadata.Shopify_Access_Token__c;
        config.apiKey = metadata.Shopify_API_Key__c;
        config.apiSecret = metadata.Shopify_API_Secret__c;
        config.isActive = metadata.Shopify_Is_Active__c == true;

        if (!config.isActive) {
            ErrorLogUtility.logError(buildConfigLog('Shopify configuration is inactive.'));
            throw new ShopifyConfigException('Shopify configuration is inactive.');
        }
        if (String.isBlank(config.storeUrl)) {
            ErrorLogUtility.logError(buildConfigLog('Shopify store URL is missing.'));
            throw new ShopifyConfigException('Shopify store URL is missing.');
        }
        if (String.isBlank(config.accessToken)) {
            ErrorLogUtility.logError(buildConfigLog('Shopify access token is missing.'));
            throw new ShopifyConfigException('Shopify access token is missing.');
        }

        return config;
    }

    private static ErrorLogUtility.LogContext buildConfigLog(String message) {
        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = 'Shopify';
        context.classMethodName = 'ShopifyConfigService.getConfig';
        context.errorMessage = message;
        context.errorCategory = 'Configuration Error';
        return context;
    }

    private static String normalizeStoreUrl(String rawUrl) {
        if (String.isBlank(rawUrl)) return null;
        String url = rawUrl.trim();
        while (url.endsWith('/')) {
            url = url.substring(0, url.length() - 1);
        }
        return url;
    }
}