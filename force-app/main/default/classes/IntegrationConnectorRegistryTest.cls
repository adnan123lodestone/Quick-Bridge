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

    @IsTest
    static void productRecordsBecomeCatalogSourceOfTruth() {
        insert new Integration_Product__c(
            Name = 'Klaviyo',
            Product_Key__c = 'klaviyo',
            Connector_Key__c = 'klaviyo',
            Product_Label__c = 'Klaviyo',
            Aliases__c = 'klaviyo,email',
            Category__c = 'Marketing',
            Display_Order__c = 80,
            Logo_URL__c = 'https://example.com/klaviyo.svg',
            Enabled__c = true,
            Catalog_Active__c = true,
            Status__c = 'Available',
            Has_Config__c = true,
            Has_Reporting__c = true,
            Has_Mapping__c = false,
            Has_Scheduler__c = false,
            Has_Checkout__c = false,
            Has_Payment__c = false,
            Has_Carrier__c = false
        );
        IntegrationConnectorRegistry.clearCache();

        List<IntegrationConnectorRegistry.ConnectorDescriptor> connectors = IntegrationConnectorRegistry.connectors();
        System.assertEquals(1, connectors.size(), 'Product records should be used when present.');
        System.assertEquals('klaviyo', IntegrationConnectorRegistry.normalizeProductKey('email'));
        System.assertEquals('https://example.com/klaviyo.svg', connectors[0].logoUrl);
        System.assertEquals(true, connectors[0].catalogActive);
    }
}
