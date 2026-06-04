@IsTest
private class IntegrationConnectorRegistryTest {
    @IsTest
    static void resolvesCurrentConnectorAliasesAndCapabilities() {
        List<IntegrationConnectorRegistry.ConnectorDescriptor> connectors = IntegrationConnectorRegistry.connectors();
        System.assert(
            connectors.size() >= 9,
            'The compatibility registry should expose the current metadata connector catalog.'
        );

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
        System.assertEquals(true, IntegrationConnectorRegistry.productKeys().contains('dhl'));
        Integer carrierCount = 0;
        for (IntegrationConnectorRegistry.ConnectorDescriptor connector : connectors) {
            if (connector.hasCarrier == true) carrierCount++;
        }
        System.assertEquals(3, carrierCount);
        System.assertEquals('paypal', IntegrationConnectorRegistry.normalizeProductKey('Pay Pal'));
        System.assertEquals('', IntegrationConnectorRegistry.normalize(null));
        System.assertEquals(null, IntegrationConnectorRegistry.byKey('unknown-product'));
    }

    @IsTest
    static void productRecordsOverlayMetadataAndAddNetNew() {
        // Baseline: how many connectors come from metadata alone
        List<IntegrationConnectorRegistry.ConnectorDescriptor> baseline = IntegrationConnectorRegistry.connectors();
        Integer metadataCount = baseline.size();

        // Insert a net-new product not in Integration_Connector__mdt
        insert new Integration_Product__c(
            Name = 'Mailchimp',
            Product_Key__c = 'mailchimp',
            Connector_Key__c = 'mailchimp',
            Product_Label__c = 'Mailchimp',
            Aliases__c = 'mailchimp,email',
            Category__c = 'Marketing',
            Display_Order__c = 80,
            Logo_URL__c = 'https://example.com/mailchimp.svg',
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
        // Metadata connectors are always present; net-new product record is appended
        System.assertEquals(metadataCount + 1, connectors.size(), 'Net-new product record should be appended to metadata connectors.');

        // Overlay fields are applied to the net-new entry
        IntegrationConnectorRegistry.ConnectorDescriptor mailchimp = IntegrationConnectorRegistry.byKey('mailchimp');
        System.assertNotEquals(null, mailchimp, 'Net-new mailchimp connector should be resolvable by key.');
        System.assertEquals('mailchimp', IntegrationConnectorRegistry.normalizeProductKey('email'));
        System.assertEquals('https://example.com/mailchimp.svg', mailchimp.logoUrl);
        System.assertEquals(true, mailchimp.catalogActive);
    }
}