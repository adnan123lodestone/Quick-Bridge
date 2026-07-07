@IsTest
private class NetSuiteScheduledExecutionTest {
  @IsTest
  static void customerScheduleRunsThroughHeartbeatAndCreatesAccountContact() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    insertSchedule('NetSuite Customer Schedule', 'NetSuite', 'Customer');
    Test.setMock(HttpCalloutMock.class, new CustomerSuiteQLMock());

    Test.startTest();
    ScheduledIntegrationHeartbeat.dispatchDueSchedules();
    Test.stopTest();

    System.assertEquals(1, [SELECT COUNT() FROM Account WHERE External_Id__c = 'netsuite:1001']);
    System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE External_Id__c = 'netsuite:contact:1001']);
  }

  @IsTest
  static void itemScheduleRunsThroughHeartbeatAndCreatesProduct() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    insertSchedule('NetSuite Item Schedule', 'NetSuite', 'Item');
    Test.setMock(HttpCalloutMock.class, new ItemSuiteQLMock());

    Test.startTest();
    ScheduledIntegrationHeartbeat.dispatchDueSchedules();
    Test.stopTest();

    System.assertEquals(1, [SELECT COUNT() FROM Product2 WHERE External_Id__c = 'netsuite:2002']);
  }

  @IsTest
  static void unsupportedScheduledObjectMarksScheduleFailed() {
    insertSchedule('NetSuite Unsupported Schedule', 'NetSuite', 'Unsupported');

    Test.startTest();
    ScheduledIntegrationHeartbeat.dispatchDueSchedules();
    Test.stopTest();

    Scheduled_Integration_Job__c job = [
      SELECT Status__c, Last_Error__c
      FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c = 'NetSuite Unsupported Schedule'
      LIMIT 1
    ];
    System.assertEquals('Failed', job.Status__c);
    System.assert(job.Last_Error__c.contains('Unsupported NetSuite scheduled object'));
  }

  @IsTest
  static void salesOrderScheduleRunsThroughHeartbeat() {
    assertPhaseTwoScheduleRuns('NetSuite Sales Order Schedule', 'SalesOrder');
  }

  @IsTest
  static void invoiceScheduleRunsThroughHeartbeat() {
    assertPhaseTwoScheduleRuns('NetSuite Invoice Schedule', 'Invoice');
  }

  @IsTest
  static void paymentScheduleRunsThroughHeartbeat() {
    assertPhaseTwoScheduleRuns('NetSuite Payment Schedule', 'Payment');
  }

  @IsTest
  static void fulfillmentScheduleRunsThroughHeartbeat() {
    assertPhaseTwoScheduleRuns('NetSuite Fulfillment Schedule', 'Fulfillment');
  }

  private static void assertPhaseTwoScheduleRuns(String keyValue, String sourceObject) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.testConfigured();
    config.enableSalesOrderSync = true;
    config.enableInvoiceSync = true;
    config.enablePaymentSync = true;
    config.enableFulfillmentSync = true;
    NetSuiteConfigService.setTestConfig(config);
    insertSchedule(keyValue, 'NetSuite', sourceObject);
    Test.setMock(HttpCalloutMock.class, new EmptySuiteQLMock());

    Test.startTest();
    ScheduledIntegrationHeartbeat.dispatchDueSchedules();
    Test.stopTest();

    Scheduled_Integration_Job__c job = [
      SELECT Status__c, Last_Error__c
      FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c = :keyValue
      LIMIT 1
    ];
    System.assertNotEquals('Failed', job.Status__c, 'Phase 2 scheduled job should not fail.');
  }

  private static void insertSchedule(String keyValue, String integrationType, String sourceObject) {
    insert new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = keyValue,
      Scheduler_Name__c = keyValue,
      Integration_Type__c = integrationType,
      Source_Object__c = sourceObject,
      Direction__c = 'Inbound',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Ready',
      Next_Run_At__c = System.now().addMinutes(-1),
      Created_DateTime__c = System.now()
    );
  }

  private class CustomerSuiteQLMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"items":[{"id":"1001","entityid":"CUST-1001","companyname":"Acme Industrial","firstname":"Ava","lastname":"Buyer","email":"ava@example.com","phone":"555-0100","billcity":"Detroit","lastmodifieddate":"2026-06-30T12:00:00Z"}],"hasMore":false}');
      return response;
    }
  }

  private class ItemSuiteQLMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"items":[{"id":"2002","itemid":"BW-2002","displayname":"Blue Widget","salesdescription":"Widget from NetSuite","isinactive":"F","lastmodifieddate":"2026-06-30T12:00:00Z"}],"hasMore":false}');
      return response;
    }
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
