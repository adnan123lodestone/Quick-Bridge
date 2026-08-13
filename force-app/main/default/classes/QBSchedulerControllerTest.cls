@isTest
private class QBSchedulerControllerTest {
  private class QBSchedulerMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setHeader('Content-Type', 'application/json');
      res.setBody('{"status":"success"}');
      return res;
    }
  }

  private static void configureQuickBooksAuth() {
    QuickBooksAuthHandler.configureConnectionForTest(
      '12345',
      'QuickBooks_Test_Named_Credential',
      '70'
    );
  }

  @testSetup
  static void setupData() {
    Account acc = new Account(Name = 'Scheduler Test Account');
    insert acc;

    Sync_Settings__c settings = Sync_Settings__c.getOrgDefaults();
    if (settings == null) {
      settings = new Sync_Settings__c();
    }
    settings.Is_Paused__c = false;
    upsert settings;
  }

  // =========================================================================
  // TESTS FOR QBSchedulerController (QuickBooks part)
  // =========================================================================

  @isTest
  static void testQbGetScheduledJobs() {
    configureQuickBooksAuth();
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    // Create a job so there is something to return
    String jobId = GenericSchedulerController.scheduleJob('qbo', '15', 'Minutes', 'Account', 'Out');
    Test.startTest();
    List<Map<String, Object>> jobs = QBSchedulerController.getScheduledJobs();
    Test.stopTest();
    System.assertNotEquals(null, jobs);
    System.assert(jobs.size() >= 1);
    GenericSchedulerController.deleteJob('QBO Sync - Account');
  }

  @isTest
  static void testQbScheduleJob() {
    configureQuickBooksAuth();
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    Test.startTest();
    String result = QBSchedulerController.scheduleJob('30', 'Minutes', 'Order', true); // true = Out
    Test.stopTest();
    System.assertNotEquals(null, result);
    // Clean up
    GenericSchedulerController.deleteJob('QBO Sync - Order');
  }

  @isTest
  static void testQbScheduleJobInvalid() {
    configureQuickBooksAuth();
    Boolean threw = false;
    try {
      QBSchedulerController.scheduleJob('abc', 'Minutes', 'Account', true);
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw);
  }

  @isTest
  static void testQbStopJob() {
    configureQuickBooksAuth();
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    // Create a job first
    String jobId = GenericSchedulerController.scheduleJob('qbo', '15', 'Minutes', 'Account', 'Out');
    Test.startTest();
    String result = QBSchedulerController.stopJob();
    Test.stopTest();
    System.assert(result.contains('Success') || result.contains('Notice'));
    GenericSchedulerController.deleteJob('QBO Sync - Account');
  }

  @isTest
  static void testQbGetSyncSettingsSummary() {
    Test.startTest();
    Map<String, String> summary = QBSchedulerController.getSyncSettingsSummary();
    Test.stopTest();
    System.assertNotEquals(null, summary);
    System.assertEquals('Salesforce ↔ QuickBooks Online', summary.get('direction'));
  }

  @isTest
  static void testQbGetRecentRuns() {
    // Create a dummy CronTrigger record? AsyncApexJob requires a real scheduled job.
    // We can pass a dummy jobId and expect empty list.
    Test.startTest();
    List<Map<String, Object>> runs = QBSchedulerController.getRecentRuns('08e000000000000AAA');
    Test.stopTest();
    System.assertEquals(0, runs.size());
  }

  @isTest
  static void testQbTogglePauseStatus() {
    Test.startTest();
    QBSchedulerController.togglePauseStatus(true);
    System.assertEquals(true, QBSchedulerController.getPauseStatus());
    QBSchedulerController.togglePauseStatus(false);
    System.assertEquals(false, QBSchedulerController.getPauseStatus());
    Test.stopTest();
  }

  @isTest
  static void testQbDeleteSpecificJob() {
    configureQuickBooksAuth();
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    // Create a job
    String jobId = GenericSchedulerController.scheduleJob('qbo', '15', 'Minutes', 'Account', 'Out');
    Test.startTest();
    QBSchedulerController.deleteSpecificJob('QBO Sync - Account');
    Test.stopTest();
    // Verify job is deleted
    List<Scheduled_Integration_Job__c> jobs = [
      SELECT Id FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c LIKE 'QBO Sync - Account%' AND Status__c != 'Deleted'
    ];
    System.assertEquals(0, jobs.size());
  }

  @isTest
  static void testQbEditSpecificJob() {
    configureQuickBooksAuth();
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    // Create a job
    String jobId = GenericSchedulerController.scheduleJob('qbo', '15', 'Minutes', 'Account', 'Out');
    Test.startTest();
    String result = QBSchedulerController.editSpecificJob('QBO Sync - Account', '10', 'Minutes');
    Test.stopTest();
    System.assert(result.contains('Success'));
    GenericSchedulerController.deleteJob('QBO Sync - Account');
  }

  // =========================================================================
  // TESTS FOR QBSchedulerController (Shopify part)
  // =========================================================================

  @isTest
  static void testShopifyGetScheduledJobs() {
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    String jobId = GenericSchedulerController.scheduleJob('shopify', '15', 'Minutes', 'Customers', 'In');
    Test.startTest();
    List<Map<String, Object>> jobs = QBSchedulerController.getShopifyScheduledJobs();
    Test.stopTest();
    System.assertNotEquals(null, jobs);
    GenericSchedulerController.deleteJob('Shopify Sync - Customers [In]');
  }

  @isTest
  static void testShopifyScheduleJob() {
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    Test.startTest();
    String result = QBSchedulerController.scheduleShopifyJob('30', 'Minutes', 'Customers', false); // false = In
    Test.stopTest();
    System.assertNotEquals(null, result);
    GenericSchedulerController.deleteJob('Shopify Sync - Customers [In]');
  }

  @isTest
  static void testShopifyStopJob() {
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    String jobId = GenericSchedulerController.scheduleJob('shopify', '15', 'Minutes', 'Customers', 'In');
    Test.startTest();
    String result = QBSchedulerController.stopShopifyJob();
    Test.stopTest();
    System.assert(result.contains('Success') || result.contains('Notice'));
    GenericSchedulerController.deleteJob('Shopify Sync - Customers [In]');
  }

  @isTest
  static void testShopifyDeleteJob() {
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    String jobId = GenericSchedulerController.scheduleJob('shopify', '15', 'Minutes', 'Customers', 'In');
    Test.startTest();
    QBSchedulerController.deleteShopifyJob('Shopify Sync - Customers [In]');
    Test.stopTest();
    List<Scheduled_Integration_Job__c> jobs = [
      SELECT Id FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c LIKE 'Shopify Sync - Customers [In]%' AND Status__c != 'Deleted'
    ];
    System.assertEquals(0, jobs.size());
  }

  @isTest
  static void testShopifyEditJob() {
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    String jobId = GenericSchedulerController.scheduleJob('shopify', '15', 'Minutes', 'Customers', 'In');
    Test.startTest();
    String result = QBSchedulerController.editShopifyJob('Shopify Sync - Customers [In]', '10', 'Minutes');
    Test.stopTest();
    System.assert(result.contains('Success'));
    GenericSchedulerController.deleteJob('Shopify Sync - Customers [In]');
  }

  @isTest
  static void testShopifyGetSyncSettingsSummary() {
    Test.startTest();
    Map<String, String> summary = QBSchedulerController.getShopifySyncSettingsSummary();
    Test.stopTest();
    System.assertNotEquals(null, summary);
    System.assertEquals('Salesforce ↔ Shopify', summary.get('direction'));
  }

  // =========================================================================
  // EXISTING TESTS FOR GENERIC SCHEDULER AND SUPPORTING CLASSES
  // (Keep all existing tests for GenericSchedulerController, etc. unchanged)
  // =========================================================================

  @isTest
  static void testScheduleJobMinutesAndDeleteSpecificJob_Generic() {
    configureQuickBooksAuth();
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    Test.startTest();
    String jobId = GenericSchedulerController.scheduleJob('qbo', '15', 'Minutes', 'Account', 'Out');
    Test.stopTest();
    System.assertNotEquals(null, jobId);
    List<Map<String, Object>> jobs = GenericSchedulerController.getScheduledJobs('qbo');
    System.assertEquals(1, jobs.size());
    System.assertEquals('Ready', (String) jobs[0].get('status'));
    GenericSchedulerController.deleteJob('QBO Sync - Account');
  }

  @isTest
  static void testScheduleJobHoursDaysWeeksMonths() {
    configureQuickBooksAuth();
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    Test.startTest();
    String hoursJob = GenericSchedulerController.scheduleJob('qbo', '2', 'Hours', 'Contact', 'Out');
    String daysJob = GenericSchedulerController.scheduleJob('qbo', '3', 'Days', 'Product2', 'Out');
    String weeksJob = GenericSchedulerController.scheduleJob('qbo', '1', 'Weeks', 'Order', 'In');
    String monthsJob = GenericSchedulerController.scheduleJob('qbo', '1', 'Months', 'Invoice__c', 'Out');
    Test.stopTest();
    System.assertNotEquals(null, hoursJob);
    System.assertNotEquals(null, daysJob);
    System.assertNotEquals(null, weeksJob);
    System.assertNotEquals(null, monthsJob);
  }

  @isTest
  static void testScheduleJobInvalidInputThrowsHandledException_Generic() {
    configureQuickBooksAuth();
    Boolean didThrow = false;
    try {
      GenericSchedulerController.scheduleJob('qbo', 'abc', 'Hours', 'Account', 'Out');
    } catch (Exception e) {
      didThrow = true;
    }
    System.assert(didThrow);
  }

  @isTest
  static void testStopJobNoMatchNoticePath_Generic() {
    String result = GenericSchedulerController.stopConnectorSchedules('qbo');
    System.assert(result != null);
  }

  @isTest
  static void testSummaryPauseAndRecentRunsBlankPath_Generic() {
    Map<String, String> summary = GenericSchedulerController.getSyncSettingsSummary('qbo');
    System.assertEquals('Salesforce <-> QuickBooks', summary.get('direction'));
    GenericSchedulerController.togglePauseStatus('qbo', true);
    System.assertEquals(true, GenericSchedulerController.getPauseStatus('qbo'));
    GenericSchedulerController.togglePauseStatus('qbo', false);
    System.assertEquals(false, GenericSchedulerController.getPauseStatus('qbo'));
    List<Map<String, Object>> runs = GenericSchedulerController.getRecentRuns(null);
    System.assertEquals(0, runs.size());
  }

  @isTest
  static void testSchedulerNextRunCalculationPaths() {
    Datetime baseTime = Datetime.newInstance(2026, 5, 20, 12, 0, 0);
    System.assertEquals(baseTime.addMinutes(5), SchedulerEntitlementService.calculateNextRun(5, 'Minutes', baseTime));
    System.assertEquals(baseTime.addHours(2), SchedulerEntitlementService.calculateNextRun(2, 'Hours', baseTime));
    System.assertEquals(baseTime.addDays(3), SchedulerEntitlementService.calculateNextRun(3, 'Days', baseTime));
    System.assertEquals(baseTime.addDays(14), SchedulerEntitlementService.calculateNextRun(2, 'Weeks', baseTime));
    System.assertEquals(baseTime.addMonths(1), SchedulerEntitlementService.calculateNextRun(1, 'Months', baseTime));
    System.assertEquals(baseTime.addHours(1), SchedulerEntitlementService.calculateNextRun(null, null, baseTime));
  }

  @isTest
  static void testSchedulerTrackingCreateAndDeletePaths() {
    Test.startTest();
    SchedulerEntitlementService.recordScheduleCreated('QuickBooks', 'Account', '30', 'Minutes', 'QBO Sync - Direct Service Account', new List<Id>());
    SchedulerEntitlementService.recordScheduleCreated(null, null, null, null, null, null);
    SchedulerEntitlementService.markScheduleDeleted('QBO Sync - Direct Service Account');
    SchedulerEntitlementService.markScheduleDeleted(null);
    Test.stopTest();
    System.assertEquals(0, [SELECT COUNT() FROM Scheduled_Integration_Job__c WHERE Logical_Job_Key__c = 'QBO Sync - Direct Service Account' AND Status__c IN ('Ready', 'Active', 'Claimed', 'Running')]);
  }

  @isTest
  static void scheduleCreationIsNotLimitedByExistingActiveSchedules() {
    configureQuickBooksAuth();
    List<Scheduled_Integration_Job__c> existingJobs = new List<Scheduled_Integration_Job__c>();
    for (Integer indexValue = 0; indexValue < 11; indexValue++) {
      existingJobs.add(new Scheduled_Integration_Job__c(
        Logical_Job_Key__c = 'Quota Regression ' + indexValue,
        Scheduler_Name__c = 'Quota Regression ' + indexValue,
        Integration_Type__c = 'QuickBooks',
        Source_Object__c = 'Account',
        Frequency_Value__c = 10,
        Frequency_Type__c = 'Minutes',
        Status__c = 'Ready',
        Created_DateTime__c = System.now()
      ));
    }
    insert existingJobs;

    Test.startTest();
    String scheduleId = GenericSchedulerController.scheduleJob(
      'qbo',
      '10',
      'Minutes',
      'Products',
      'In'
    );
    Test.stopTest();

    System.assertNotEquals(null, scheduleId);
    System.assertEquals(12, [SELECT COUNT() FROM Scheduled_Integration_Job__c WHERE Status__c = 'Ready']);
  }

  @isTest
  static void testEditSpecificJobAndDeleteJob_Generic() {
    configureQuickBooksAuth();
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    Test.startTest();
    String msg = GenericSchedulerController.editJob('qbo', 'QBO Sync - Account', '10', 'Minutes');
    Test.stopTest();
    System.assert(msg != null);
    GenericSchedulerController.deleteJob('QBO Sync - Account');
  }

  @isTest
  static void testShopifyLogicalScheduleLifecycle_Generic() {
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    Test.startTest();
    String jobId = GenericSchedulerController.scheduleJob('shopify', '15', 'Minutes', 'Customers', 'In');
    String editMessage = GenericSchedulerController.editJob('shopify', 'Shopify Sync - Customers [In]', '1', 'Hours');
    Test.stopTest();
    System.assertNotEquals(null, jobId);
    System.assert(editMessage.contains('Success'));
    System.assertNotEquals(null, GenericSchedulerController.getScheduledJobs('shopify'));
    GenericSchedulerController.deleteJob('Shopify Sync - Customers [In]');
    System.assertNotEquals(null, GenericSchedulerController.stopConnectorSchedules('shopify'));
  }

  @isTest
  static void testShopifySummaryAndInvalidSchedulePaths_Generic() {
    Map<String, String> summary = GenericSchedulerController.getSyncSettingsSummary('shopify');
    System.assertEquals('Incremental Sync', summary.get('type'));
    Boolean didThrow = false;
    try {
      GenericSchedulerController.scheduleJob('shopify', 'abc', 'Hours', 'Customers', 'In');
    } catch (Exception e) {
      didThrow = true;
    }
    System.assertEquals(true, didThrow);
    List<Map<String, Object>> runs = GenericSchedulerController.getRecentRuns('08e000000000000AAA');
    System.assertEquals(0, runs.size());
  }

  @isTest
  static void testHeartbeatDispatchesDueNoopSchedule() {
    insert new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = 'Noop Sync - Account',
      Scheduler_Name__c = 'Noop Sync - Account',
      Integration_Type__c = 'Noop',
      Source_Object__c = 'Account',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Ready',
      Next_Run_At__c = System.now().addMinutes(-1)
    );
    Test.startTest();
    ScheduledIntegrationHeartbeat.dispatchDueSchedules();
    Test.stopTest();
    Scheduled_Integration_Job__c afterRun = [SELECT Last_Run_At__c, Last_Claimed_At__c, Last_Dispatched_At__c, Next_Run_At__c, Processor_Job_Id__c, Status__c, Lease_Token__c, Lease_Expires_At__c, Last_Error__c FROM Scheduled_Integration_Job__c WHERE Logical_Job_Key__c = 'Noop Sync - Account' LIMIT 1];
    System.assertNotEquals(null, afterRun.Last_Run_At__c);
    System.assertNotEquals(null, afterRun.Last_Claimed_At__c);
    System.assertEquals(null, afterRun.Last_Dispatched_At__c);
    System.assertNotEquals(null, afterRun.Next_Run_At__c);
    System.assertNotEquals(null, afterRun.Processor_Job_Id__c);
    System.assertEquals('Failed', afterRun.Status__c);
    System.assert(afterRun.Last_Error__c.contains('No scheduled operation adapter'));
    System.assertEquals(null, afterRun.Lease_Token__c);
    System.assertEquals(null, afterRun.Lease_Expires_At__c);
  }

  @isTest
  static void testReadyClaimedAndRunningSchedulesAreVisible() {
    insert new List<Scheduled_Integration_Job__c>{
      new Scheduled_Integration_Job__c(Logical_Job_Key__c = 'QBO Sync - Ready Account', Scheduler_Name__c = 'QBO Sync - Ready Account', Integration_Type__c = 'QuickBooks', Source_Object__c = 'Account', Frequency_Value__c = 10, Frequency_Type__c = 'Minutes', Status__c = 'Ready', Created_DateTime__c = System.now()),
      new Scheduled_Integration_Job__c(Logical_Job_Key__c = 'QBO Sync - Claimed Account', Scheduler_Name__c = 'QBO Sync - Claimed Account', Integration_Type__c = 'QuickBooks', Source_Object__c = 'Account', Frequency_Value__c = 10, Frequency_Type__c = 'Minutes', Status__c = 'Claimed', Lease_Token__c = 'test-token', Lease_Expires_At__c = System.now().addMinutes(5), Created_DateTime__c = System.now()),
      new Scheduled_Integration_Job__c(Logical_Job_Key__c = 'QBO Sync - Running Account', Scheduler_Name__c = 'QBO Sync - Running Account', Integration_Type__c = 'QuickBooks', Source_Object__c = 'Account', Frequency_Value__c = 10, Frequency_Type__c = 'Minutes', Status__c = 'Running', Created_DateTime__c = System.now())
    };
    Test.startTest();
    List<Map<String, Object>> jobs = GenericSchedulerController.getScheduledJobs('qbo');
    Test.stopTest();
    System.assertEquals(3, jobs.size());
  }

  @isTest
  static void testDispatcherClaimsDueScheduleBeforeWorkerRunsAndSkipsDuplicates() {
    insert new Scheduled_Integration_Job__c(Logical_Job_Key__c = 'Noop Claim - Account', Scheduler_Name__c = 'Noop Claim - Account', Integration_Type__c = 'Noop', Source_Object__c = 'Account', Frequency_Value__c = 5, Frequency_Type__c = 'Minutes', Status__c = 'Ready', Next_Run_At__c = System.now().addMinutes(-1));
    Test.startTest();
    GenericScheduleDispatcher.dispatchDue();
    Scheduled_Integration_Job__c claimed = [SELECT Status__c, Lease_Token__c, Lease_Expires_At__c, Last_Claimed_At__c, Processor_Job_Id__c FROM Scheduled_Integration_Job__c WHERE Logical_Job_Key__c = 'Noop Claim - Account' LIMIT 1];
    System.assertEquals('Claimed', claimed.Status__c);
    System.assertNotEquals(null, claimed.Lease_Token__c);
    System.assertNotEquals(null, claimed.Lease_Expires_At__c);
    System.assertNotEquals(null, claimed.Last_Claimed_At__c);
    String firstProcessorId = claimed.Processor_Job_Id__c;
    GenericScheduleDispatcher.dispatchDue();
    Scheduled_Integration_Job__c stillClaimed = [SELECT Status__c, Lease_Token__c, Processor_Job_Id__c FROM Scheduled_Integration_Job__c WHERE Logical_Job_Key__c = 'Noop Claim - Account' LIMIT 1];
    Test.stopTest();
    System.assertEquals('Claimed', stillClaimed.Status__c);
    System.assertEquals(claimed.Lease_Token__c, stillClaimed.Lease_Token__c);
    System.assertEquals(firstProcessorId, stillClaimed.Processor_Job_Id__c);
  }

  @isTest
  static void testDispatcherReclaimsStaleClaim() {
    insert new Scheduled_Integration_Job__c(Logical_Job_Key__c = 'Noop Stale Claim - Account', Scheduler_Name__c = 'Noop Stale Claim - Account', Integration_Type__c = 'Noop', Source_Object__c = 'Account', Frequency_Value__c = 5, Frequency_Type__c = 'Minutes', Status__c = 'Claimed', Lease_Token__c = 'stale-token', Lease_Expires_At__c = System.now().addMinutes(-10), Next_Run_At__c = System.now().addMinutes(-20));
    Test.startTest();
    GenericScheduleDispatcher.dispatchDue();
    Scheduled_Integration_Job__c reclaimed = [SELECT Status__c, Lease_Token__c, Lease_Expires_At__c FROM Scheduled_Integration_Job__c WHERE Logical_Job_Key__c = 'Noop Stale Claim - Account' LIMIT 1];
    Test.stopTest();
    System.assertEquals('Claimed', reclaimed.Status__c);
    System.assertNotEquals('stale-token', reclaimed.Lease_Token__c);
    System.assert(reclaimed.Lease_Expires_At__c > System.now());
  }

  @isTest
  static void testProcessorWithWrongLeaseTokenExitsSafely() {
    Scheduled_Integration_Job__c job = new Scheduled_Integration_Job__c(Logical_Job_Key__c = 'Noop Wrong Token - Account', Scheduler_Name__c = 'Noop Wrong Token - Account', Integration_Type__c = 'Noop', Source_Object__c = 'Account', Frequency_Value__c = 5, Frequency_Type__c = 'Minutes', Status__c = 'Claimed', Lease_Token__c = 'correct-token', Lease_Expires_At__c = System.now().addMinutes(5), Next_Run_At__c = System.now().addMinutes(-1));
    insert job;
    Test.startTest();
    System.enqueueJob(new ScheduledIntegrationJobProcessor(job.Id, 'wrong-token'));
    Test.stopTest();
    Scheduled_Integration_Job__c afterRun = [SELECT Status__c, Lease_Token__c, Last_Dispatched_At__c FROM Scheduled_Integration_Job__c WHERE Id = :job.Id];
    System.assertEquals('Claimed', afterRun.Status__c);
    System.assertEquals('correct-token', afterRun.Lease_Token__c);
    System.assertEquals(null, afterRun.Last_Dispatched_At__c);
  }

  @isTest
  static void testScheduledProcessorCompatibilityBranches() {
    Scheduled_Integration_Job__c qbJob = new Scheduled_Integration_Job__c(Logical_Job_Key__c = 'QBO Sync - Unknown', Scheduler_Name__c = 'QBO Sync - Unknown', Integration_Type__c = 'QuickBooks', Source_Object__c = 'Unknown', Frequency_Value__c = 1, Frequency_Type__c = 'Hours', Status__c = 'Active');
    Scheduled_Integration_Job__c shopifyJob = new Scheduled_Integration_Job__c(Logical_Job_Key__c = 'Shopify Sync - Unknown [Out]', Scheduler_Name__c = 'Shopify Sync - Unknown [Out]', Integration_Type__c = 'Shopify', Source_Object__c = 'Unknown', Direction__c = 'Out', Frequency_Value__c = 1, Frequency_Type__c = 'Hours', Status__c = 'Active');
    insert new List<Scheduled_Integration_Job__c>{ qbJob, shopifyJob };
    Test.startTest();
    ScheduledIntegrationHeartbeat.dispatchDueSchedules();
    System.enqueueJob(new ScheduledIntegrationJobProcessor(qbJob.Id));
    System.enqueueJob(new ScheduledIntegrationJobProcessor(shopifyJob.Id));
    Test.stopTest();
    System.assertEquals(2, [SELECT COUNT() FROM Scheduled_Integration_Job__c WHERE Integration_Type__c IN ('QuickBooks', 'Shopify')]);
  }
}