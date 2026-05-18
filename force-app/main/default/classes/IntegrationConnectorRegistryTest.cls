@IsTest
private class IntegrationConnectorRegistryTest {
    @IsTest
    static void resolvesCurrentConnectorAliasesAndCapabilities() {
        List<IntegrationConnectorRegistry.ConnectorDescriptor> connectors = IntegrationConnectorRegistry.connectors();
        System.assertEquals(7, connectors.size(), 'The compatibility registry should expose the seven current products.');

        IntegrationConnectorRegistry.ConnectorDescriptor quickBooks = IntegrationConnectorRegistry.byKey('quickbooks online');
        System.assertEquals('quickbooks', quickBooks.productKey);
        System.assertEquals('QuickBooks', quickBooks.label);
        System.assertEquals(true, quickBooks.hasScheduler);

        IntegrationConnectorRegistry.ConnectorDescriptor authorizeNet = IntegrationConnectorRegistry.byKey('authnet');
        System.assertEquals('authorizenet', authorizeNet.productKey);
        System.assertEquals(true, authorizeNet.hasPayment);

        System.assertEquals(3, IntegrationConnectorRegistry.paymentConnectors().size());
        System.assertEquals(true, IntegrationConnectorRegistry.byProductKey().containsKey('stripe'));
        System.assertEquals(true, IntegrationConnectorRegistry.productKeys().contains('fedex'));
        System.assertEquals('paypal', IntegrationConnectorRegistry.normalizeProductKey('Pay Pal'));
        System.assertEquals('', IntegrationConnectorRegistry.normalize(null));
        System.assertEquals(null, IntegrationConnectorRegistry.byKey('unknown-product'));
    }
}