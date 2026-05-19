@IsTest
private class QuickBridgeArchitectureRefactorTest {
    @IsTest
    static void registryResolvesFallbackConnectorsAndDynamicProduct() {
        ConnectorRegistryService.clearCache();
        System.assertNotEquals(null, ConnectorRegistryService.byKey('qbo'));
        System.assertEquals('quickbooks', ConnectorRegistryService.byKey('QuickBooks Online').productKey);
        System.assertEquals('StripePaymentAdapter', ConnectorRegistryService.adapterClassFor('stripe', 'payment.checkout'));
        System.assert(ConnectorRegistryService.externalObjectsFor('shopify').contains('Customer'));

        insert new Integration_Product__c(
            Name = 'Klaviyo',
            Product_Key__c = 'klaviyo',
            Connector_Key__c = 'klaviyo',
            Product_Label__c = 'Klaviyo',
            Aliases__c = 'klaviyo,email',
            Category__c = 'Marketing',
            Display_Order__c = 80,
            Enabled__c = true,
            Catalog_Active__c = true,
            Has_Config__c = true,
            Has_Reporting__c = true,
            Has_Mapping__c = true,
            Has_Scheduler__c = false,
            Has_Checkout__c = false,
            Has_Payment__c = false,
            Has_Carrier__c = false,
            Status__c = 'Available'
        );

        ConnectorRegistryService.clearCache();
        ConnectorRegistryService.ConnectorDescriptor klaviyo = ConnectorRegistryService.byKey('email');
        System.assertNotEquals(null, klaviyo);
        System.assertEquals('klaviyo', klaviyo.connectorKey);
        System.assert(klaviyo.capabilities.contains('config.admin'));
    }

    @IsTest
    static void configServicePrefersNormalizedConfigAndBlocksSecretValues() {
        ConnectorRegistryService.clearCache();
        insert new Integration_Product__c(
            Name = 'Config Test',
            Product_Key__c = 'configtest',
            Connector_Key__c = 'configtest',
            Product_Label__c = 'Config Test',
            Category__c = 'Test',
            Display_Order__c = 5,
            Enabled__c = true,
            Catalog_Active__c = true,
            Has_Config__c = true,
            Has_Reporting__c = true
        );
        Connector_Instance__c instanceRecord = new Connector_Instance__c(
            Name = 'Config Test',
            Connector_Key__c = 'configtest',
            Connector_Label__c = 'Config Test',
            Active__c = true,
            Environment__c = 'Sandbox',
            Entitlement_Status__c = 'Active',
            Expiry_Date__c = Date.today().addDays(10),
            Health_Status__c = 'Healthy',
            Named_Credential__c = 'Config_Test_NC'
        );
        insert instanceRecord;
        insert new Connector_Config_Value__c(
            Name = 'configtest:storeUrl',
            Connector_Instance__c = instanceRecord.Id,
            Connector_Key__c = 'configtest',
            Field_Key__c = 'storeUrl',
            Value__c = 'https://example.test'
        );

        ConnectorRegistryService.clearCache();
        ConnectorConfigService.ConnectorConfig config = ConnectorConfigService.getConfig('configtest');
        System.assertEquals(true, config.fromNormalizedConfig);
        System.assertEquals(true, config.active);
        System.assertEquals('https://example.test', ConnectorConfigService.getConfigValue('configtest', 'storeUrl'));

        try {
            ConnectorConfigService.upsertNonSecretValue('configtest', 'clientSecret', 'not-allowed');
            System.assert(false, 'Expected secret value rejection.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }
    }

    @IsTest
    static void adminGuardCanBlockAndAuditControlPlaneActions() {
        QuickBridgeAdminGuard.bypassForTests = false;
        try {
            QuickBridgeAdminGuard.requireManage();
            System.assert(false, 'Expected permission failure.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        } finally {
            QuickBridgeAdminGuard.bypassForTests = true;
        }

        QuickBridgeAdminGuard.audit('TEST_ACTION', 'stripe', 'Success', 'details', null);
        System.assertEquals(1, [SELECT COUNT() FROM QuickBridge_Admin_Audit__c WHERE Action__c = 'TEST_ACTION']);
    }

    @IsTest
    static void paymentRouterResolvesCurrentProviderAdapters() {
        ConnectorRegistryService.clearCache();
        System.assertNotEquals(null, PaymentProviderRouter.adapterFor('stripe'));
        System.assertNotEquals(null, PaymentProviderRouter.adapterFor('paypal'));
        System.assertNotEquals(null, PaymentProviderRouter.adapterFor('authorizenet'));

        Set<String> activeGateways = new Set<String>{ 'stripe', 'paypal', 'authorize.net' };
        System.assertNotEquals(null, new StripePaymentAdapter().describe(ConnectorRegistryService.byKey('stripe'), activeGateways));
        System.assertNotEquals(null, new PayPalPaymentAdapter().describe(ConnectorRegistryService.byKey('paypal'), activeGateways));
        System.assertNotEquals(null, new AuthorizeNetPaymentAdapter().describe(ConnectorRegistryService.byKey('authorizenet'), activeGateways));

        List<PaymentCheckoutController.ProviderDescriptor> providers = PaymentCheckoutController.getCheckoutProviders();
        System.assertNotEquals(null, providers);

        try {
            PaymentProviderRouter.route('not-a-provider');
            System.assert(false, 'Expected unsupported payment provider.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }
    }

    @IsTest
    static void genericSchedulerCreatesListsAndDeletesLogicalSchedules() {
        Test.startTest();
        String scheduleId = GenericSchedulerController.scheduleJob('qbo', '1', 'Hours', 'Account', null);
        Test.stopTest();

        System.assertNotEquals(null, scheduleId);
        List<Map<String, Object>> jobs = GenericSchedulerController.getScheduledJobs('qbo');
        System.assertEquals(1, jobs.size());
        System.assertEquals('Account', jobs[0].get('syncObject'));

        GenericSchedulerController.deleteJob((String)jobs[0].get('name'));
        System.assertEquals(0, GenericSchedulerController.getScheduledJobs('qbo').size());

        QuickBooksScheduledOperationAdapter.skipExecutionForTests = true;
        ShopifyScheduledOperationAdapter.skipExecutionForTests = true;
        Scheduled_Integration_Job__c qbJob = new Scheduled_Integration_Job__c(Integration_Type__c = 'QuickBooks', Source_Object__c = 'Account', Direction__c = null);
        new QuickBooksScheduledOperationAdapter().execute(qbJob);
        Scheduled_Integration_Job__c shopifyJob = new Scheduled_Integration_Job__c(Integration_Type__c = 'Shopify', Source_Object__c = 'Customers', Direction__c = 'In');
        new ShopifyScheduledOperationAdapter().execute(shopifyJob);
        System.assertNotEquals(null, ScheduledOperationRouter.adapterFor('QuickBooks', 'Account'));
        new GenericScheduleDispatcher().execute(null);
    }

    @IsTest
    static void entityRegistryReadsObjectMapMetadataFallback() {
        String qbEntity = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'Account', null, 'Invoice');
        String shopifyEntity = IntegrationEntityRegistry.resolveExternalEntity('shopify', 'OrderItem', null, 'Customer');
        System.assertEquals('Customer', qbEntity);
        System.assertEquals('LineItem', shopifyEntity);
    }
}
