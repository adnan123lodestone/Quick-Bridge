System.debug('QB_SMOKE_CONNECTORS=' + ConnectorRegistryService.connectors().size());
System.debug('QB_SMOKE_PAYMENT_PROVIDERS=' + PaymentCheckoutController.getCheckoutProviders().size());
System.debug('QB_SMOKE_HAS_MANAGE=' + QuickBridgeAdminGuard.hasManage());
System.debug('QB_SMOKE_HAS_VIEW=' + QuickBridgeAdminGuard.hasView());
System.debug('QB_SMOKE_HAS_RUN_SYNC=' + QuickBridgeAdminGuard.hasRunSync());
System.debug('QB_SMOKE_QBO_ENTITY=' + IntegrationEntityRegistry.resolveExternalEntity('qbo', 'Account', null, 'Invoice'));
System.debug('QB_SMOKE_SHOPIFY_ENTITY=' + IntegrationEntityRegistry.resolveExternalEntity('shopify', 'OrderItem', null, 'Customer'));
ScheduledIntegrationHeartbeat.ensureScheduled();
System.debug('QB_SMOKE_HEARTBEAT_CHECKED=true');
