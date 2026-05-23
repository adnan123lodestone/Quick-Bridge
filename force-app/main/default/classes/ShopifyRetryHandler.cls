public with sharing class ShopifyRetryHandler implements RetryHandler {
    public String handle(Error_Log__c log) {
        return ShopifyErrorHandler.handle(log);
    }
}
