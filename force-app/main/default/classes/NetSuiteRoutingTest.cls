@IsTest
private class NetSuiteRoutingTest {
  @IsTest
  static void schedulerAndWorkRoutersResolveAllowlistedNetSuiteClasses() {
    ConnectorRegistryService.clearCache();

    System.assert(
      ScheduledOperationRouter.adapterFor('netsuite', 'Customer') instanceof NetSuiteScheduledOperationAdapter
    );
    System.assertEquals(
      'NetSuiteIntegrationWorker',
      IntegrationWorkRouter.handlerClassFor('netsuite', 'CustomerSync')
    );
    System.assertEquals(
      'NetSuiteIntegrationWorker',
      IntegrationWorkRouter.handlerClassFor('oracle_netsuite', 'ItemSync')
    );
    ConnectorAdapterAllowlist.assertAllowed('NetSuiteIntegrationWorker');
    ConnectorAdapterAllowlist.assertAllowed('NetSuiteScheduledOperationAdapter');
  }

  @IsTest
  static void workerDispatchesSupportedOperationAndRejectsUnknownOperation() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    Test.setMock(HttpCalloutMock.class, new EmptySuiteQLMock());

    Test.startTest();
    new NetSuiteIntegrationWorker().handle(
      new Integration_Work_Item__c(Operation__c = 'CustomerSync')
    );
    Test.stopTest();

    try {
      new NetSuiteIntegrationWorker().handle(
        new Integration_Work_Item__c(Operation__c = 'Unknown')
      );
      System.assert(false, 'Expected unsupported operation to fail.');
    } catch (NetSuiteIntegrationWorker.NetSuiteIntegrationWorkerException expected) {
      System.assert(expected.getMessage().contains('Unsupported NetSuite operation'));
    }
  }

  @IsTest
  static void scheduledAdapterCanBeSkippedInUnitTests() {
    NetSuiteScheduledOperationAdapter.skipExecutionForTests = true;

    Test.startTest();
    new NetSuiteScheduledOperationAdapter().execute(
      new Scheduled_Integration_Job__c(Source_Object__c = 'Customer', Direction__c = 'Inbound')
    );
    Test.stopTest();

    NetSuiteScheduledOperationAdapter.skipExecutionForTests = false;
  }

  @IsTest
  static void scheduledAdapterRunsCustomerSyncAndAuditsAfterCallout() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    Test.setMock(HttpCalloutMock.class, new EmptySuiteQLMock());

    Test.startTest();
    NetSuiteScheduledOperationAdapter.run('Customer', 'Inbound');
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT count() FROM QuickBridge_Admin_Audit__c WHERE Connector_Key__c = 'netsuite' AND Action__c = 'SCHEDULED_SYNC']
    );
  }

  @IsTest
  static void scheduledAdapterRunsItemSyncAndRejectsUnsupportedTargets() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    Test.setMock(HttpCalloutMock.class, new EmptySuiteQLMock());

    Test.startTest();
    NetSuiteScheduledOperationAdapter.run('Item', 'Inbound');
    Test.stopTest();

    Boolean threw = false;
    try {
      NetSuiteScheduledOperationAdapter.run('Unsupported', 'Inbound');
    } catch (NetSuiteScheduledOperationAdapter.NetSuiteScheduledOperationException expected) {
      threw = true;
      System.assert(expected.getMessage().contains('Unsupported NetSuite scheduled object'));
    }
    System.assertEquals(true, threw);
  }

  private class EmptySuiteQLMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"items":[],"hasMore":false}');
      return response;
    }
  }
}
