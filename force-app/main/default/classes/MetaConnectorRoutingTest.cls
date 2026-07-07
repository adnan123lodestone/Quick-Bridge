@IsTest
private class MetaConnectorRoutingTest {
  @IsTest
  static void metaAliasesResolveToSingleConnector() {
    ConnectorRegistryService.clearCache();

    ConnectorRegistryService.ConnectorDescriptor meta = ConnectorRegistryService.byKey('meta');
    ConnectorRegistryService.ConnectorDescriptor facebook = ConnectorRegistryService.byKey('facebook');
    ConnectorRegistryService.ConnectorDescriptor instagram = ConnectorRegistryService.byKey('instagram');
    ConnectorRegistryService.ConnectorDescriptor metaAds = ConnectorRegistryService.byKey('meta ads');

    System.assertEquals('meta', meta.connectorKey);
    System.assertEquals('meta', facebook.connectorKey);
    System.assertEquals('meta', instagram.connectorKey);
    System.assertEquals('meta', metaAds.connectorKey);
    System.assertEquals('Facebook / Instagram', meta.label);
  }

  @IsTest
  static void metaCapabilitiesResolveAllowlistedAdapters() {
    ConnectorRegistryService.clearCache();

    System.assert(
      ScheduledOperationRouter.adapterFor('meta', 'Campaign') instanceof MetaScheduledOperationAdapter
    );
    System.assertEquals('MetaIntegrationWorker', ConnectorRegistryService.adapterClassFor('meta', 'work.LeadAd'));
    System.assertEquals('MetaIntegrationWorker', ConnectorRegistryService.adapterClassFor('meta', 'work.CommentAttribution'));
    System.assertEquals('MetaIntegrationWorker', ConnectorRegistryService.adapterClassFor('meta', 'work.WebhookEvent'));
    System.assertEquals('MetaIntegrationWorker', ConnectorRegistryService.adapterClassFor('meta', 'work.CampaignSync'));
    System.assertEquals('MetaIntegrationWorker', ConnectorRegistryService.adapterClassFor('meta', 'work.InsightsSync'));
    System.assertEquals('MetaIntegrationWorker', ConnectorRegistryService.adapterClassFor('meta', 'work.Reconciliation'));
    ConnectorAdapterAllowlist.assertAllowed('MetaIntegrationWorker');
    ConnectorAdapterAllowlist.assertAllowed('MetaScheduledOperationAdapter');
  }

  @IsTest
  static void metaWorkRouterResolvesAllSupportedOperations() {
    System.assertEquals('MetaIntegrationWorker', IntegrationWorkRouter.handlerClassFor('instagram', 'LeadAd'));
    System.assertEquals('MetaIntegrationWorker', IntegrationWorkRouter.handlerClassFor('facebook', 'WebhookEvent'));
    System.assertEquals('MetaIntegrationWorker', IntegrationWorkRouter.handlerClassFor('meta', 'CommentAttribution'));
    System.assertEquals('MetaIntegrationWorker', IntegrationWorkRouter.handlerClassFor('meta ads', 'Reconciliation'));
  }
}