@IsTest
private class RetryDispatcherTest {
    @IsTest
    static void handlerResolvesThroughConnectorCapabilityMetadata() {
        System.assert(
            RetryDispatcher.handlerFor('QuickBooks') instanceof QBORetryHandler,
            'QuickBooks retry should resolve through retry.handler metadata.'
        );
        System.assert(
            RetryDispatcher.handlerFor('Shopify') instanceof ShopifyRetryHandler,
            'Shopify retry should resolve through retry.handler metadata.'
        );
    }

    @IsTest
    static void handlerRejectsUnknownConnector() {
        System.assertEquals(null, RetryDispatcher.handlerFor('Unknown Gateway'));
    }
}
