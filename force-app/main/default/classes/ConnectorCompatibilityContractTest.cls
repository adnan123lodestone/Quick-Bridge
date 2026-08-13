@IsTest
private class ConnectorCompatibilityContractTest {
  @IsTest
  static void everyConfiguredAdapterRemainsResolvableAndAllowlisted() {
    List<Integration_Connector_Capability__mdt> capabilities = [
      SELECT DeveloperName, Adapter_Class__c
      FROM Integration_Connector_Capability__mdt
      WHERE Adapter_Class__c != NULL
    ];
    System.assert(
      !capabilities.isEmpty(),
      'Connector capabilities are required.'
    );

    Set<String> resolvedClasses = new Set<String>();
    for (Integration_Connector_Capability__mdt capability : capabilities) {
      String className = capability.Adapter_Class__c;
      ConnectorAdapterAllowlist.assertAllowed(className);
      Type adapterType = Type.forName(className);
      if (adapterType == null) {
        adapterType = Type.forName('QuickBridgeTLG', className);
      }
      System.assertNotEquals(
        null,
        adapterType,
        'Configured adapter must remain available: ' + capability.DeveloperName
      );
      System.assertNotEquals(
        null,
        adapterType.newInstance(),
        'Configured adapter must retain a zero-argument constructor: ' +
        className
      );
      resolvedClasses.add(className);
    }

    System.assert(
      resolvedClasses.contains('QuickBooksScheduledOperationAdapter')
    );
    System.assert(resolvedClasses.contains('ShopifyScheduledOperationAdapter'));
    System.assert(resolvedClasses.contains('KlaviyoScheduledOperationAdapter'));
    System.assert(resolvedClasses.contains('MetaIntegrationWorker'));
    System.assert(resolvedClasses.contains('NetSuiteIntegrationWorker'));
    System.assert(resolvedClasses.contains('StripePaymentAdapter'));
    System.assert(resolvedClasses.contains('PayPalPaymentAdapter'));
    System.assert(resolvedClasses.contains('AuthorizeNetPaymentAdapter'));
    System.assert(resolvedClasses.contains('FedExCarrierAdapter'));
    System.assert(resolvedClasses.contains('UPSCarrierAdapter'));
    System.assert(resolvedClasses.contains('DHLCarrierAdapter'));
  }

  @IsTest
  static void touchedLegacyBatchConstructorsRemainAvailable() {
    Campaign campaign = new Campaign(
      Name = 'Klaviyo Constructor Compatibility',
      Profile_s_URL__c = 'https://example.invalid/api/lists/example'
    );
    insert campaign;
    Id campaignId = campaign.Id;

    System.assertNotEquals(null, new KlaviyoProfilesBatch());
    System.assertNotEquals(null, new KlaviyoProfilesBatch('/api/profiles'));
    System.assertNotEquals(null, new KlaviyoListsBatch());
    System.assertNotEquals(null, new KlaviyoListsBatch('/api/lists'));
    System.assertNotEquals(null, new KlaviyoEventsBatch());
    System.assertNotEquals(null, new KlaviyoEventsBatch('/api/events'));
    System.assertNotEquals(null, new KlaviyoCampaignMembersBatch(campaignId));
    System.assertNotEquals(
      null,
      new KlaviyoCampaignMembersBatch(campaignId, '/api/lists/example')
    );

    System.assertNotEquals(null, new ShopifyCustomersBatch());
    System.assertNotEquals(null, new ShopifyCustomersBatch('/customers.json'));
    System.assertNotEquals(null, new ShopifyProductsBatch());
    System.assertNotEquals(null, new ShopifyProductsBatch('/products.json'));
    System.assertNotEquals(null, new ShopifyOrdersBatch());
    System.assertNotEquals(null, new ShopifyOrdersBatch('/orders.json'));
    System.assertNotEquals(
      null,
      new ShopifyCustomersOutboundBatch(new Set<Id>(), false)
    );
    System.assertNotEquals(
      null,
      new ShopifyProductsOutboundBatch(new Set<Id>(), false)
    );
    System.assertNotEquals(
      null,
      new ShopifyOrdersOutboundBatch(new Set<Id>(), false)
    );

    System.assertNotEquals(null, new QBCustomerToAccountSyncBatch());
    System.assertNotEquals(
      null,
      new QBCustomerToAccountSyncBatch('2026-08-11')
    );
    System.assertNotEquals(null, new QBItemToProductSyncBatch());
    System.assertNotEquals(null, new QBItemToProductSyncBatch('2026-08-11'));
  }

  @IsTest
  static void sharedRuntimeEntryPointsRemainConstructible() {
    ConnectorExecutionRequest inboundRequest = new ConnectorExecutionRequest();
    ConnectorExecutionRequest outboundRequest = new ConnectorExecutionRequest();

    System.assertNotEquals(null, new ConnectorInboundBatch(inboundRequest));
    System.assertNotEquals(null, new ConnectorOutboundBatch(outboundRequest));
    System.assertNotEquals(null, new ConnectorInboundOperationExecutor());
    System.assertNotEquals(null, new ConnectorOutboundOperationExecutor());
    System.assertNotEquals(null, new IntegrationWorkProcessor(null, null));
  }
}