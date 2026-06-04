@IsTest
private class QuickBridgeArchitectureRefactorTest {
  @IsTest
  static void registryResolvesFallbackConnectorsAndDynamicProduct() {
    ConnectorRegistryService.clearCache();
    System.assertNotEquals(
      null,
      LegacyConnectorRegistryFallback.connectors(),
      'Legacy fallback should be centralized in its own compatibility service.'
    );
    System.assertNotEquals(null, ConnectorRegistryService.byKey('qbo'), 'QBO connector should be resolvable by key');
    System.assertEquals(
      'quickbooks',
      ConnectorRegistryService.byKey('QuickBooks Online').productKey,
      'QuickBooks Online should resolve to quickbooks productKey'
    );
    System.assertEquals(
      'StripePaymentAdapter',
      ConnectorRegistryService.adapterClassFor('stripe', 'payment.checkout'),
      'Stripe payment checkout adapter should be StripePaymentAdapter'
    );
    System.assertEquals(
      'FedExCarrierAdapter',
      ConnectorRegistryService.adapterClassFor('fedex', 'carrier.operation'),
      'FedEx carrier adapter should be FedExCarrierAdapter'
    );
    System.assertEquals(
      'UPSCarrierAdapter',
      ConnectorRegistryService.adapterClassFor('ups', 'carrier.operation'),
      'UPS carrier adapter should be UPSCarrierAdapter'
    );
    System.assertEquals(
      'DHLCarrierAdapter',
      ConnectorRegistryService.adapterClassFor('dhl', 'carrier.operation'),
      'DHL carrier adapter should be DHLCarrierAdapter'
    );
    System.assertEquals(
      'QBAccountWorker',
      ConnectorRegistryService.adapterClassFor(
        'quickbooks',
        'work.AccountUpsert'
      ),
      'QuickBooks AccountUpsert adapter should be QBAccountWorker'
    );
    System.assertEquals(
      'ShopifyIntegrationWorker',
      ConnectorRegistryService.adapterClassFor('shopify', 'work.CustomerUpsert'),
      'Shopify CustomerUpsert adapter should be ShopifyIntegrationWorker'
    );
    System.assert(
      ConnectorRegistryService.externalObjectsFor('shopify')
        .contains('Customer'),
      'Shopify external objects should include Customer'
    );

    insert new Integration_Product__c(
      Name = 'MailPulse',
      Product_Key__c = 'mailpulse',
      Connector_Key__c = 'mailpulse',
      Product_Label__c = 'MailPulse',
      Aliases__c = 'mailpulse,email',
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
    ConnectorRegistryService.ConnectorDescriptor mailPulse = ConnectorRegistryService.byKey(
      'email'
    );
    System.assertNotEquals(null, mailPulse, 'MailPulse dynamic product should be resolvable by email alias');
    System.assertEquals('mailpulse', mailPulse.connectorKey, 'MailPulse connectorKey should be mailpulse');
    System.assert(mailPulse.capabilities.contains('config.admin'), 'MailPulse should have config.admin capability');
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
      Active_Field__c = 'activeFlag',
      Expiry_Field__c = 'expiryOn',
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
    insert new Connector_Config_Value__c(
      Name = 'configtest:clientSecretRef',
      Connector_Instance__c = instanceRecord.Id,
      Connector_Key__c = 'configtest',
      Field_Key__c = 'clientSecret',
      Value__c = 'NamedCredential:Config_Test_NC',
      Is_Secret_Reference__c = true
    );

    ConnectorRegistryService.clearCache();
    ConnectorConfigService.ConnectorConfig config = ConnectorConfigService.getConfig(
      'configtest'
    );
    System.assertEquals(true, config.fromNormalizedConfig, 'Config should be resolved from normalized Connector_Instance__c');
    System.assertEquals(true, config.active, 'Config should report active=true');
    System.assertEquals(
      'https://example.test',
      ConnectorConfigService.getConfigValue('configtest', 'storeUrl'),
      'storeUrl config value should match the inserted record'
    );
    System.assertEquals(
      'NamedCredential:Config_Test_NC',
      config.values.get('clientSecret'),
      'Secret reference value should be preserved as-is'
    );
    System.assertEquals(true, ConnectorConfigService.isActive('configtest'), 'configtest connector should be active');

    ConnectorConfigService.upsertNonSecretValue(
      'configtest',
      'publicSetting',
      'visible'
    );
    ConnectorConfigService.upsertNonSecretValue(
      'configtest',
      'publicSetting',
      'updated'
    );
    System.assertEquals(
      'updated',
      [
        SELECT Value__c
        FROM Connector_Config_Value__c
        WHERE Connector_Key__c = 'configtest' AND Field_Key__c = 'publicSetting'
        LIMIT 1
      ]
      .Value__c
    );
    ConnectorConfigService.upsertNonSecretValue('configtest', 'activeFlag', 'no');
    System.assertEquals(false, ConnectorConfigService.isActive('configtest'), 'Setting activeFlag to no should deactivate the connector');
    ConnectorConfigService.upsertNonSecretValue('configtest', 'activeFlag', 'yes');
    ConnectorConfigService.upsertNonSecretValue(
      'configtest',
      'expiryOn',
      String.valueOf(Date.today().addDays(20))
    );
    System.assertEquals(true, ConnectorConfigService.isActive('configtest'), 'Setting activeFlag back to yes should reactivate the connector');
    try {
      ConnectorConfigService.upsertNonSecretValue('configtest', 'expiryOn', 'not-a-date');
      System.assert(false, 'Expected invalid date rejection.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Invalid date format should throw an AuraHandledException');
    }

    try {
      ConnectorConfigService.upsertNonSecretValue(
        'configtest',
        'clientSecret',
        'not-allowed'
      );
      System.assert(false, 'Expected secret value rejection.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Writing a secret config value should be rejected by the service');
    }

    insert new Integration_Product__c(
      Name = 'No Config',
      Product_Key__c = 'noconfig',
      Connector_Key__c = 'noconfig',
      Product_Label__c = 'No Config',
      Category__c = 'Test',
      Config_Record_Name__c = 'Missing_Record',
      Active_Field__c = 'Missing_Active__c',
      Expiry_Field__c = 'Missing_Expiry__c',
      Display_Order__c = 6,
      Enabled__c = true,
      Catalog_Active__c = true,
      Has_Config__c = true,
      Has_Reporting__c = true
    );
    ConnectorRegistryService.clearCache();
    ConnectorConfigService.ConnectorConfig missingConfig = ConnectorConfigService.getConfig(
      'noconfig'
    );
    System.assertEquals(false, missingConfig.fromNormalizedConfig, 'Config for missing record should not be from normalized config');
    System.assertEquals(false, missingConfig.active, 'Config for missing record should be inactive');
    System.assertEquals(false, ConnectorConfigService.isActive('noconfig'), 'Connector with missing config record should be inactive');

    insert new Integration_Product__c(
      Name = 'New Config',
      Product_Key__c = 'newconfig',
      Connector_Key__c = 'newconfig',
      Product_Label__c = 'New Config',
      Category__c = 'Test',
      Editable_Fields__c = 'Public_Field__c,Client_Secret__c',
      Display_Order__c = 7,
      Enabled__c = true,
      Catalog_Active__c = true,
      Has_Config__c = true,
      Has_Reporting__c = true
    );
    ConnectorRegistryService.clearCache();
    ConnectorConfigService.upsertNonSecretValue(
      'newconfig',
      'Public_Field__c',
      'created'
    );
    ConnectorConfigService.ConnectorConfig createdConfig = ConnectorConfigService.getConfig(
      'newconfig'
    );
    System.assertEquals(true, createdConfig.fromNormalizedConfig, 'Config created via upsertNonSecretValue should be normalized');
    System.assertEquals(
      'created',
      ConnectorConfigService.getConfigValue('newconfig', 'Public_Field__c'),
      'Public_Field__c value should match the upserted value'
    );
    try {
      ConnectorConfigService.upsertNonSecretValue(
        'newconfig',
        'Client_Secret__c',
        'not-allowed'
      );
      System.assert(false, 'Expected secret legacy field rejection.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Writing a legacy secret field should be rejected by the service');
    }

    try {
      ConnectorConfigService.getConfig('missing-connector');
      System.assert(false, 'Expected unsupported connector rejection.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Unsupported connector key should throw AuraHandledException from getConfig');
    }
  }

  @IsTest
  static void configServiceSkipsLegacyFallbackForRuntimeAccess() {
    ConnectorRegistryService.clearCache();
    ConnectorConfigService.ConnectorConfig stripeConfig = ConnectorConfigService.getConfig(
      'stripe'
    );
    System.assertNotEquals(null, stripeConfig, 'Stripe config should be resolvable');
    System.assertEquals(false, stripeConfig.fromNormalizedConfig, 'Legacy config should not be from normalized config');
    System.assertEquals(true, stripeConfig.values.isEmpty(), 'Legacy config should have empty values map');
    ConnectorConfigService.ConnectorConfig migrationStripeConfig = ConnectorConfigService.getConfigForMigration(
      'stripe'
    );
    System.assertNotEquals(null, migrationStripeConfig.values, 'Migration config values should not be null');
    try {
      ConnectorConfigService.getConfigForMigration('missing-connector');
      System.assert(false, 'Expected unsupported migration connector rejection.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Unsupported migration connector should throw AuraHandledException');
    }
    System.assertNotEquals(null, ConnectorConfigService.getConfig('paypal'), 'PayPal config should be resolvable');
    System.assertNotEquals(
      null,
      ConnectorConfigService.getConfig('authorizenet'),
      'AuthorizeNet config should be resolvable'
    );
    System.assertNotEquals(
      null,
      ConnectorConfigService.getConfig('quickbooks'),
      'QuickBooks config should be resolvable'
    );
    System.assertNotEquals(null, ConnectorConfigService.getConfig('shopify'), 'Shopify config should be resolvable');
    System.assertNotEquals(null, ConnectorConfigService.getConfig('fedex'), 'FedEx config should be resolvable');
    System.assertNotEquals(null, ConnectorConfigService.getConfig('ups'), 'UPS config should be resolvable');
    ConnectorConfigService.getConfigValue(
      'stripe',
      'Stripe_Publishable_Key__c'
    );
    ConnectorConfigService.isActive('stripe');
  }

  @IsTest
  static void configResolverAndMigrationMakeNormalizedConfigPrimary() {
    ConnectorRegistryService.clearCache();
    QuickbridgeConfigMigrationService.MigrationResult migration = QuickbridgeConfigMigrationService.migrateConnector(
      'stripe'
    );
    System.assertEquals('stripe', migration.connectorKey, 'Migration result connectorKey should be stripe');
    System.assertEquals(true, migration.success, migration.message);
    System.assertNotEquals(null, migration.connectorInstanceId, 'Migration should create a connector instance ID');

    ConnectorConfigService.ConnectorConfig migratedConfig = ConnectorConfigService.getConfig(
      'stripe'
    );
    System.assertEquals(true, migratedConfig.fromNormalizedConfig, 'Post-migration config should be from normalized config');
    System.assertEquals(
      migratedConfig.values.get('Stripe_Publishable_Key__c'),
      ConnectorConfigResolver.getValue('stripe', 'Stripe_Publishable_Key__c'),
      'ConfigResolver should return same value as ConnectorConfigService after migration'
    );

    ConnectorConfigService.upsertNonSecretValue(
      'stripe',
      'Stripe_Publishable_Key__c',
      'pk_normalized_test'
    );
    System.assertEquals(
      'pk_normalized_test',
      ConnectorConfigResolver.requireValue(
        'stripe',
        'Stripe_Publishable_Key__c'
      ),
      'ConfigResolver should reflect the upserted normalized key value'
    );

    try {
      ConnectorConfigResolver.requireValue('stripe', 'doesNotExist');
      System.assert(false, 'Missing config should throw a clear exception.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Missing config key should throw AuraHandledException from requireValue');
    }
  }

  @IsTest
  static void paymentMetadataAdminSaveWritesNormalizedConnectorConfig() {
    ConnectorRegistryService.clearCache();
    QuickBridgeAdminSessionService.SessionCreateResult sessionResult = QuickBridgeAdminSessionService.createSession(
      'admin@example.test',
      System.now().addHours(1)
    );

    PaymentMetadataService.MetadataUpdateResponse response = PaymentMetadataService.updatePaymentMetadata(
      'stripe',
      JSON.serialize(
        new Map<String, Object>{
          'Stripe_Publishable_Key__c' => 'pk_admin_normalized',
          'Stripe_Active__c' => true,
          'Stripe_End_Date__c' => String.valueOf(Date.today().addDays(30))
        }
      ),
      sessionResult.sessionToken
    );

    System.assertEquals(true, response.success, response.message);
    System.assertEquals(
      'pk_admin_normalized',
      ConnectorConfigResolver.requireValue(
        'stripe',
        'Stripe_Publishable_Key__c'
      ),
      'RequireValue should return the admin-saved publishable key'
    );
    System.assertEquals(
      true,
      ConnectorConfigResolver.getBoolean('stripe', 'Stripe_Active__c'),
      'Stripe should be active after admin save'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Connector_Config_Value__c
        WHERE
          Connector_Key__c = 'stripe'
          AND Field_Key__c = 'Stripe_Publishable_Key__c'
      ],
      'Exactly one Connector_Config_Value__c row should exist for Stripe publishable key'
    );
  }

  @IsTest
  static void adminGuardCanBlockAndAuditControlPlaneActions() {
    QuickBridgeAdminGuard.bypassForTests = false;
    if (QuickBridgeAdminGuard.hasManage()) {
      QuickBridgeAdminGuard.requireManage();
    } else {
      try {
        QuickBridgeAdminGuard.requireManage();
        System.assert(false, 'Expected permission failure.');
      } catch (AuraHandledException expected) {
        System.assertNotEquals(null, expected, 'requireManage should throw AuraHandledException when permission is not granted');
      }
    }
    QuickBridgeAdminGuard.bypassForTests = true;

    System.assertEquals(true, QuickBridgeAdminGuard.hasManage(), 'Admin guard hasManage should return true in test context');
    System.assertEquals(true, QuickBridgeAdminGuard.hasView(), 'Admin guard hasView should return true in test context');
    System.assertEquals(true, QuickBridgeAdminGuard.hasRunSync(), 'Admin guard hasRunSync should return true in test context');
    QuickBridgeAdminGuard.requireView();
    QuickBridgeAdminGuard.requireRunSync();
    QuickBridgeAdminGuard.audit(
      'TEST_ACTION',
      'stripe',
      'Success',
      'details',
      null
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM QuickBridge_Admin_Audit__c
        WHERE Action__c = 'TEST_ACTION'
      ],
      'Audit record should be created for TEST_ACTION'
    );
  }

  @IsTest
  static void paymentRouterResolvesCurrentProviderAdapters() {
    ConnectorRegistryService.clearCache();
    System.assertNotEquals(null, PaymentProviderRouter.adapterFor('stripe'), 'Stripe adapter should be resolvable');
    System.assertNotEquals(null, PaymentProviderRouter.adapterFor('paypal'), 'PayPal adapter should be resolvable');
    System.assertNotEquals(
      null,
      PaymentProviderRouter.adapterFor('authorizenet'),
      'AuthorizeNet adapter should be resolvable'
    );

    Set<String> activeGateways = new Set<String>{
      'stripe',
      'paypal',
      'authorize.net'
    };
    PaymentCheckoutController.ProviderDescriptor stripeDescriptor = new StripePaymentAdapter()
      .describe(ConnectorRegistryService.byKey('stripe'), activeGateways);
    PaymentCheckoutController.ProviderDescriptor paypalDescriptor = new PayPalPaymentAdapter()
      .describe(ConnectorRegistryService.byKey('paypal'), activeGateways);
    PaymentCheckoutController.ProviderDescriptor authNetDescriptor = new AuthorizeNetPaymentAdapter()
      .describe(ConnectorRegistryService.byKey('authorizenet'), activeGateways);
    System.assertEquals('stripe', stripeDescriptor.connectorKey, 'Stripe descriptor connectorKey should be stripe');
    System.assertEquals('stripeElements', stripeDescriptor.actionType, 'Stripe descriptor actionType should be stripeElements');
    System.assert(stripeDescriptor.requiredInputFields.contains('cardName'), 'Stripe descriptor should require cardName input');
    System.assert(stripeDescriptor.capabilities.contains('payment.checkout'), 'Stripe descriptor should have payment.checkout capability');
    System.assertEquals(30, stripeDescriptor.displayOrder, 'Stripe descriptor display order should be 30');
    System.assertEquals('paypalButtons', paypalDescriptor.actionType, 'PayPal descriptor actionType should be paypalButtons');
    System.assertEquals('acceptJs', authNetDescriptor.actionType, 'AuthorizeNet descriptor actionType should be acceptJs');

    List<PaymentCheckoutController.ProviderDescriptor> providers = PaymentCheckoutController.getCheckoutProviders();
    System.assertNotEquals(null, providers, 'getCheckoutProviders should return a non-null list');

    PaymentCheckoutController.PaymentRequest stripeRequest = new PaymentCheckoutController.PaymentRequest();
    stripeRequest.providerKey = 'stripe';
    PaymentCheckoutController.PaymentResponse stripeInit = PaymentCheckoutController.initializePayment(
      stripeRequest
    );
    System.assertEquals(true, stripeInit.success, 'Stripe payment init should succeed in test context');
    PaymentCheckoutController.PaymentResponse stripeExecute = PaymentCheckoutController.executePayment(
      stripeRequest
    );
    System.assertEquals(false, stripeExecute.success, 'Stripe payment execute should fail without credentials');

    PaymentCheckoutController.PaymentRequest authNetRequest = new PaymentCheckoutController.PaymentRequest();
    authNetRequest.providerKey = 'authorizenet';
    PaymentCheckoutController.PaymentResponse authNetInit = PaymentCheckoutController.initializePayment(
      authNetRequest
    );
    System.assertEquals(true, authNetInit.success, 'AuthorizeNet payment init should succeed in test context');
    PaymentCheckoutController.PaymentResponse authNetExecute = PaymentCheckoutController.executePayment(
      authNetRequest
    );
    System.assertEquals(false, authNetExecute.success, 'AuthorizeNet payment execute should fail without credentials');

    PaymentCheckoutController.PaymentRequest paypalRequest = new PaymentCheckoutController.PaymentRequest();
    paypalRequest.providerKey = 'paypal';
    PaymentCheckoutController.PaymentResponse paypalInit = PaymentCheckoutController.initializePayment(
      paypalRequest
    );
    System.assertEquals(false, paypalInit.success, 'PayPal payment init should fail without credentials');
    PaymentCheckoutController.PaymentResponse paypalExecute = PaymentCheckoutController.executePayment(
      paypalRequest
    );
    System.assertEquals(false, paypalExecute.success, 'PayPal payment execute should fail without credentials');

    try {
      PaymentProviderRouter.route('not-a-provider');
      System.assert(false, 'Expected unsupported payment provider.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Routing to unsupported payment provider should throw AuraHandledException');
    }
  }

  @IsTest
  static void genericSchedulerCreatesListsAndDeletesLogicalSchedules() {
    QuickBooksAuthHandler.configureConnectionForTest(
      '12345',
      'QuickBooks_Test_Named_Credential',
      '70'
    );

    Test.startTest();
    String scheduleId = GenericSchedulerController.scheduleJob(
      'qbo',
      '1',
      'Hours',
      'Account',
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, scheduleId);
    List<Map<String, Object>> jobs = GenericSchedulerController.getScheduledJobs(
      'qbo'
    );
    System.assertEquals(1, jobs.size());
    System.assertEquals('Account', jobs[0].get('syncObject'));

    GenericSchedulerController.deleteJob((String) jobs[0].get('name'));
    System.assertEquals(
      0,
      GenericSchedulerController.getScheduledJobs('qbo').size()
    );

    String shopifyScheduleId = GenericSchedulerController.scheduleJob(
      'shopify',
      '2',
      'Hours',
      'Customers',
      'In'
    );
    System.assertNotEquals(null, shopifyScheduleId);
    String editMessage = GenericSchedulerController.editJob(
      'shopify',
      'Shopify Sync - Customers [In]',
      '3',
      'Hours'
    );
    System.assert(editMessage.contains('Success'));
    System.assertNotEquals(
      null,
      GenericSchedulerController.stopConnectorSchedules('shopify')
    );
    System.assertEquals(
      'custom-connector',
      GenericSchedulerController.connectorKeyToIntegrationType(
        'custom-connector'
      )
    );

    System.assertEquals(
      'Incremental Sync',
      GenericSchedulerController.getSyncSettingsSummary('qbo').get('type')
    );
    System.assertEquals(
      'Incremental Sync',
      GenericSchedulerController.getSyncSettingsSummary('shopify').get('type')
    );
    System.assertEquals(0, GenericSchedulerController.getRecentRuns(null).size());
    try {
      GenericSchedulerController.scheduleJob('qbo', 'abc', 'Hours', 'Account', 'Out');
      System.assert(false, 'Expected invalid QuickBooks schedule value.');
    } catch (Exception expected) {
      System.assertNotEquals(null, expected, 'Invalid QuickBooks schedule direction should throw an exception');
    }
    try {
      GenericSchedulerController.scheduleJob(
        'shopify',
        'abc',
        'Hours',
        'Customers',
        'In'
      );
      System.assert(false, 'Expected invalid Shopify schedule value.');
    } catch (Exception expected) {
      System.assertNotEquals(null, expected, 'Invalid Shopify schedule value should throw an exception');
    }
    GenericSchedulerController.togglePauseStatus('qbo', true);
    System.assertEquals(true, GenericSchedulerController.getPauseStatus('qbo'));
    GenericSchedulerController.togglePauseStatus('qbo', false);
    System.assertEquals(false, GenericSchedulerController.getPauseStatus('qbo'));

    QuickBooksScheduledOperationAdapter.skipExecutionForTests = true;
    ShopifyScheduledOperationAdapter.skipExecutionForTests = true;
    Scheduled_Integration_Job__c qbJob = new Scheduled_Integration_Job__c(
      Integration_Type__c = 'QuickBooks',
      Source_Object__c = 'Account',
      Direction__c = null
    );
    new QuickBooksScheduledOperationAdapter().execute(qbJob);
    Scheduled_Integration_Job__c shopifyJob = new Scheduled_Integration_Job__c(
      Integration_Type__c = 'Shopify',
      Source_Object__c = 'Customers',
      Direction__c = 'In'
    );
    new ShopifyScheduledOperationAdapter().execute(shopifyJob);
    System.assertNotEquals(
      null,
      ScheduledOperationRouter.adapterFor('QuickBooks', 'Account')
    );
    ScheduledOperationRouter.execute(
      new Scheduled_Integration_Job__c(
        Integration_Type__c = 'Noop',
        Source_Object__c = 'Account'
      )
    );

    insert new List<Scheduled_Integration_Job__c>{
      new Scheduled_Integration_Job__c(
        Logical_Job_Key__c = 'QBO Sync - Account - Due',
        Scheduler_Name__c = 'QBO Sync - Account - Due',
        Integration_Type__c = 'QuickBooks',
        Source_Object__c = 'Account',
        Frequency_Value__c = 1,
        Frequency_Type__c = 'Hours',
        Status__c = 'Active',
        Next_Run_At__c = System.now().addMinutes(-5)
      ),
      new Scheduled_Integration_Job__c(
        Logical_Job_Key__c = 'Shopify Sync - Customers [In] - Due',
        Scheduler_Name__c = 'Shopify Sync - Customers [In] - Due',
        Integration_Type__c = 'Shopify',
        Source_Object__c = 'Customers',
        Direction__c = 'In',
        Frequency_Value__c = 1,
        Frequency_Type__c = 'Hours',
        Status__c = 'Active',
        Next_Run_At__c = System.now().addMinutes(-5)
      )
    };

    ScheduledIntegrationHeartbeat.skipSchedulingForTests = false;
    ScheduledIntegrationHeartbeat.ensureScheduled();
    new GenericScheduleDispatcher().execute(null);
    ScheduledIntegrationHeartbeat.dispatchDueSchedules();
    System.assertNotEquals(null, SchedulerEntitlementService.getUsageSummary());
    SchedulerEntitlementService.assertCanCreateSchedule();
    SchedulerEntitlementService.recordScheduleCreated(
      null,
      null,
      null,
      null,
      null,
      null
    );
    SchedulerEntitlementService.markScheduleDeleted(null);
    System.assertNotEquals(
      null,
      SchedulerEntitlementService.calculateNextRun(1, 'Minutes', System.now())
    );
    System.assertNotEquals(
      null,
      SchedulerEntitlementService.calculateNextRun(1, 'Days', System.now())
    );
    System.assertNotEquals(
      null,
      SchedulerEntitlementService.calculateNextRun(1, 'Weeks', System.now())
    );
    System.assertNotEquals(
      null,
      SchedulerEntitlementService.calculateNextRun(1, 'Months', System.now())
    );
    System.assertNotEquals(
      null,
      SchedulerEntitlementService.calculateNextRun(null, 'Other', null)
    );
  }

  @IsTest
  static void workAndCarrierRoutingResolveRegisteredAdapters() {
    ConnectorRegistryService.clearCache();
    System.assertEquals(
      'QBAccountWorker',
      IntegrationWorkRouter.handlerClassFor('QuickBooks', 'AccountUpsert')
    );
    System.assertEquals(
      'QBProductWorker',
      IntegrationWorkRouter.handlerClassFor('qbo', 'ProductUpsert')
    );
    System.assertEquals(
      'ShopifyIntegrationWorker',
      IntegrationWorkRouter.handlerClassFor('Shopify', 'OrderUpsert')
    );
    System.assertEquals(
      'CarrierIntegrationWorker',
      IntegrationWorkRouter.handlerClassFor('Carrier', 'TrackingSync')
    );
    System.assertEquals(
      'PaymentIntegrationWorker',
      IntegrationWorkRouter.handlerClassFor('Payment', 'Authorize')
    );
    System.assertEquals(
      'QRIntegrationWorker',
      IntegrationWorkRouter.handlerClassFor('QR', 'Generate')
    );
    System.assertEquals(
      'UsageIntegrationWorker',
      IntegrationWorkRouter.handlerClassFor('Usage', 'Record')
    );

    System.assertEquals(
      'fedex',
      CarrierAdapterFactory.normalizeCarrierKey('FedEx')
    );
    System.assertEquals(
      'ups',
      CarrierAdapterFactory.normalizeCarrierKey('UPS')
    );
    System.assertNotEquals(null, CarrierAdapterFactory.getAdapter('FedEx'));
    System.assertNotEquals(null, CarrierAdapterFactory.getAdapter('UPS'));
    System.assertNotEquals(null, CarrierAdapterFactory.getAdapter('DHL'));
    System.assert(
      CarrierAdapterFactory.supportedCarrierKeys().contains('fedex')
    );
    System.assert(
      CarrierAdapterFactory.supportedCarrierKeys().contains('dhl')
    );
    System.assert(
      CarrierAdapterFactory.supportedCarrierLabels().contains('FedEx')
    );
    System.assert(
      CarrierAdapterFactory.supportedCarrierLabels().contains('DHL')
    );

    try {
      CarrierAdapterFactory.getAdapter(null);
      System.assert(false, 'Expected blank carrier rejection.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Null carrier key should throw AuraHandledException from adapter factory');
    }

    try {
      CarrierAdapterFactory.getAdapter('not-a-carrier');
      System.assert(false, 'Expected unsupported carrier rejection.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected, 'Unsupported carrier key should throw AuraHandledException from adapter factory');
    }
  }

  @IsTest
  static void entityRegistryReadsObjectMapMetadataFallback() {
    String qbEntity = IntegrationEntityRegistry.resolveExternalEntity(
      'qbonline',
      'Account',
      null,
      'Invoice'
    );
    String shopifyEntity = IntegrationEntityRegistry.resolveExternalEntity(
      'shopify',
      'OrderItem',
      null,
      'Customer'
    );
    System.assertEquals('Customer', qbEntity);
    System.assertEquals('LineItem', shopifyEntity);
    System.assertEquals(
      'Order',
      IntegrationEntityRegistry.resolveExternalEntity(
        'shopify',
        'Order',
        'Order',
        'Customer'
      )
    );
    System.assertEquals(
      'Invoice',
      IntegrationEntityRegistry.resolveExternalEntity(
        'qbo',
        'Unknown__c',
        null,
        'Invoice'
      )
    );
    System.assertEquals(
      'Customer',
      IntegrationEntityRegistry.resolveExternalEntity(
        'quickbooks',
        'Contact',
        null,
        'Invoice'
      )
    );
  }
}