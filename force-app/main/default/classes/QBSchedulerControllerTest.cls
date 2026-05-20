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

  @isTest
  static void testScheduleJobMinutesAndDeleteSpecificJob() {
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    Test.startTest();
    String jobId = QBSchedulerController.scheduleJob(
      '15',
      'Minutes',
      'Account'
    );
    Test.stopTest();

    System.assertNotEquals(null, jobId);

    List<Map<String, Object>> jobs = QBSchedulerController.getScheduledJobs();
    System.assertNotEquals(null, jobs);
    System.assertEquals(
      1,
      jobs.size(),
      'New Ready schedules should be listed as active schedules.'
    );
    System.assertEquals('Ready', (String) jobs[0].get('status'));

    QBSchedulerController.deleteSpecificJob('QBO Sync - Account');
  }

  @isTest
  static void testScheduleJobHoursDaysWeeksMonths() {
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    Test.startTest();
    String hoursJob = QBSchedulerController.scheduleJob(
      '2',
      'Hours',
      'Contact'
    );
    String daysJob = QBSchedulerController.scheduleJob('3', 'Days', 'Product2');
    String weeksJob = QBSchedulerController.scheduleJob('1', 'Weeks', 'Order');
    String monthsJob = QBSchedulerController.scheduleJob(
      '1',
      'Months',
      'Invoice__c'
    );
    Test.stopTest();

    System.assertNotEquals(null, hoursJob);
    System.assertNotEquals(null, daysJob);
    System.assertNotEquals(null, weeksJob);
    System.assertNotEquals(null, monthsJob);
  }

  @isTest
  static void testScheduleJobInvalidInputThrowsHandledException() {
    Boolean didThrow = false;
    try {
      QBSchedulerController.scheduleJob('abc', 'Hours', 'Account');
    } catch (Exception e) {
      didThrow = true;
    }
    System.assert(didThrow);
  }

  @isTest
  static void testStopJobNoMatchNoticePath() {
    String result = QBSchedulerController.stopJob();
    System.assert(result != null);
  }

  @isTest
  static void testSummaryPauseAndRecentRunsBlankPath() {
    Map<String, String> summary = QBSchedulerController.getSyncSettingsSummary();
    System.assertEquals(
      'Salesforce to QuickBooks Online',
      summary.get('direction')
    );

    QBSchedulerController.togglePauseStatus(true);
    System.assertEquals(true, QBSchedulerController.getPauseStatus());

    QBSchedulerController.togglePauseStatus(false);
    System.assertEquals(false, QBSchedulerController.getPauseStatus());

    List<Map<String, Object>> runs = QBSchedulerController.getRecentRuns(null);
    System.assertEquals(0, runs.size());
  }

  @isTest
  static void testSchedulerNextRunCalculationPaths() {
    Datetime baseTime = Datetime.newInstance(2026, 5, 20, 12, 0, 0);

    System.assertEquals(
      baseTime.addMinutes(5),
      SchedulerEntitlementService.calculateNextRun(5, 'Minutes', baseTime)
    );
    System.assertEquals(
      baseTime.addHours(2),
      SchedulerEntitlementService.calculateNextRun(2, 'Hours', baseTime)
    );
    System.assertEquals(
      baseTime.addDays(3),
      SchedulerEntitlementService.calculateNextRun(3, 'Days', baseTime)
    );
    System.assertEquals(
      baseTime.addDays(14),
      SchedulerEntitlementService.calculateNextRun(2, 'Weeks', baseTime)
    );
    System.assertEquals(
      baseTime.addMonths(1),
      SchedulerEntitlementService.calculateNextRun(1, 'Months', baseTime)
    );
    System.assertEquals(
      baseTime.addHours(1),
      SchedulerEntitlementService.calculateNextRun(null, null, baseTime)
    );
  }

  @isTest
  static void testSchedulerEntitlementCreateCountAndDeletePaths() {
    Test.startTest();
    SchedulerEntitlementService.assertCanCreateSchedule();
    SchedulerEntitlementService.recordScheduleCreated(
      'QuickBooks',
      'Account',
      '30',
      'Minutes',
      'QBO Sync - Direct Service Account',
      new List<Id>()
    );
    SchedulerEntitlementService.recordScheduleCreated(
      null,
      null,
      null,
      null,
      null,
      null
    );
    SchedulerEntitlementService.UsageSummary activeSummary = SchedulerEntitlementService.getUsageSummary();
    SchedulerEntitlementService.markScheduleDeleted(
      'QBO Sync - Direct Service Account'
    );
    SchedulerEntitlementService.markScheduleDeleted(null);
    Test.stopTest();

    System.assert(
      activeSummary.activeCount >= 1,
      'Directly recorded Ready schedules should be counted as active.'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Scheduled_Integration_Job__c
        WHERE
          Logical_Job_Key__c = 'QBO Sync - Direct Service Account'
          AND Status__c IN ('Ready', 'Active', 'Claimed', 'Running')
      ]
    );
  }

  @isTest
  static void testEditSpecificJobAndDeleteJob() {
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    Test.startTest();
    String msg = QBSchedulerController.editSpecificJob(
      'QBO Sync - Account',
      '10',
      'Minutes'
    );
    Test.stopTest();

    System.assert(msg != null);
    QBSchedulerController.deleteSpecificJob('QBO Sync - Account');
  }

  @isTest
  static void testShopifyLogicalScheduleLifecycle() {
    Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
    Test.startTest();
    String jobId = QBSchedulerController.scheduleShopifyJob(
      '15',
      'Minutes',
      'Customers',
      false
    );
    String editMessage = QBSchedulerController.editShopifyJob(
      'Shopify Sync - Customers [In]',
      '1',
      'Hours'
    );
    Test.stopTest();

    System.assertNotEquals(null, jobId);
    System.assert(editMessage.contains('Success'));
    System.assertNotEquals(
      null,
      QBSchedulerController.getShopifyScheduledJobs()
    );
    QBSchedulerController.deleteShopifyJob('Shopify Sync - Customers [In]');
    System.assertNotEquals(null, QBSchedulerController.stopShopifyJob());
  }

  @isTest
  static void testShopifySummaryAndInvalidSchedulePaths() {
    Map<String, String> summary = QBSchedulerController.getShopifySyncSettingsSummary();
    System.assertEquals('Incremental Sync', summary.get('type'));

    Boolean didThrow = false;
    try {
      QBSchedulerController.scheduleShopifyJob(
        'abc',
        'Hours',
        'Customers',
        false
      );
    } catch (Exception e) {
      didThrow = true;
    }
    System.assertEquals(true, didThrow);

    List<Map<String, Object>> runs = QBSchedulerController.getRecentRuns(
      '08e000000000000AAA'
    );
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

    Scheduled_Integration_Job__c afterRun = [
      SELECT
        Last_Run_At__c,
        Last_Claimed_At__c,
        Last_Dispatched_At__c,
        Next_Run_At__c,
        Processor_Job_Id__c,
        Status__c,
        Lease_Token__c,
        Lease_Expires_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c = 'Noop Sync - Account'
      LIMIT 1
    ];
    System.assertNotEquals(null, afterRun.Last_Run_At__c);
    System.assertNotEquals(null, afterRun.Last_Claimed_At__c);
    System.assertNotEquals(null, afterRun.Last_Dispatched_At__c);
    System.assertNotEquals(null, afterRun.Next_Run_At__c);
    System.assertNotEquals(null, afterRun.Processor_Job_Id__c);
    System.assertEquals('Ready', afterRun.Status__c);
    System.assertEquals(null, afterRun.Lease_Token__c);
    System.assertEquals(null, afterRun.Lease_Expires_At__c);
  }

  @isTest
  static void testReadyClaimedAndRunningSchedulesAreVisibleAndCounted() {
    insert new List<Scheduled_Integration_Job__c>{
      new Scheduled_Integration_Job__c(
        Logical_Job_Key__c = 'QBO Sync - Ready Account',
        Scheduler_Name__c = 'QBO Sync - Ready Account',
        Integration_Type__c = 'QuickBooks',
        Source_Object__c = 'Account',
        Frequency_Value__c = 10,
        Frequency_Type__c = 'Minutes',
        Status__c = 'Ready',
        Created_DateTime__c = System.now()
      ),
      new Scheduled_Integration_Job__c(
        Logical_Job_Key__c = 'QBO Sync - Claimed Account',
        Scheduler_Name__c = 'QBO Sync - Claimed Account',
        Integration_Type__c = 'QuickBooks',
        Source_Object__c = 'Account',
        Frequency_Value__c = 10,
        Frequency_Type__c = 'Minutes',
        Status__c = 'Claimed',
        Lease_Token__c = 'test-token',
        Lease_Expires_At__c = System.now().addMinutes(5),
        Created_DateTime__c = System.now()
      ),
      new Scheduled_Integration_Job__c(
        Logical_Job_Key__c = 'QBO Sync - Running Account',
        Scheduler_Name__c = 'QBO Sync - Running Account',
        Integration_Type__c = 'QuickBooks',
        Source_Object__c = 'Account',
        Frequency_Value__c = 10,
        Frequency_Type__c = 'Minutes',
        Status__c = 'Running',
        Created_DateTime__c = System.now()
      )
    };

    Test.startTest();
    List<Map<String, Object>> jobs = QBSchedulerController.getScheduledJobs();
    SchedulerEntitlementService.UsageSummary usage = SchedulerEntitlementService.getUsageSummary();
    Test.stopTest();

    System.assertEquals(
      3,
      jobs.size(),
      'Live scheduler statuses should be visible in the scheduler UI.'
    );
    System.assertEquals(
      3,
      usage.activeCount,
      'Live scheduler statuses should count against active schedule limits.'
    );
  }

  @isTest
  static void testDispatcherClaimsDueScheduleBeforeWorkerRunsAndSkipsDuplicates() {
    insert new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = 'Noop Claim - Account',
      Scheduler_Name__c = 'Noop Claim - Account',
      Integration_Type__c = 'Noop',
      Source_Object__c = 'Account',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Ready',
      Next_Run_At__c = System.now().addMinutes(-1)
    );

    Test.startTest();
    GenericScheduleDispatcher.dispatchDue();
    Scheduled_Integration_Job__c claimed = [
      SELECT
        Status__c,
        Lease_Token__c,
        Lease_Expires_At__c,
        Last_Claimed_At__c,
        Processor_Job_Id__c
      FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c = 'Noop Claim - Account'
      LIMIT 1
    ];
    System.assertEquals('Claimed', claimed.Status__c);
    System.assertNotEquals(null, claimed.Lease_Token__c);
    System.assertNotEquals(null, claimed.Lease_Expires_At__c);
    System.assertNotEquals(null, claimed.Last_Claimed_At__c);
    String firstProcessorId = claimed.Processor_Job_Id__c;

    GenericScheduleDispatcher.dispatchDue();
    Scheduled_Integration_Job__c stillClaimed = [
      SELECT Status__c, Lease_Token__c, Processor_Job_Id__c
      FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c = 'Noop Claim - Account'
      LIMIT 1
    ];
    Test.stopTest();

    System.assertEquals(
      'Claimed',
      stillClaimed.Status__c,
      'A second dispatcher pass must not reclaim a fresh lease.'
    );
    System.assertEquals(claimed.Lease_Token__c, stillClaimed.Lease_Token__c);
    System.assertEquals(firstProcessorId, stillClaimed.Processor_Job_Id__c);
  }

  @isTest
  static void testDispatcherReclaimsStaleClaim() {
    insert new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = 'Noop Stale Claim - Account',
      Scheduler_Name__c = 'Noop Stale Claim - Account',
      Integration_Type__c = 'Noop',
      Source_Object__c = 'Account',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Claimed',
      Lease_Token__c = 'stale-token',
      Lease_Expires_At__c = System.now().addMinutes(-10),
      Next_Run_At__c = System.now().addMinutes(-20)
    );

    Test.startTest();
    GenericScheduleDispatcher.dispatchDue();
    Scheduled_Integration_Job__c reclaimed = [
      SELECT Status__c, Lease_Token__c, Lease_Expires_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c = 'Noop Stale Claim - Account'
      LIMIT 1
    ];
    Test.stopTest();

    System.assertEquals('Claimed', reclaimed.Status__c);
    System.assertNotEquals('stale-token', reclaimed.Lease_Token__c);
    System.assert(reclaimed.Lease_Expires_At__c > System.now());
  }

  @isTest
  static void testProcessorWithWrongLeaseTokenExitsSafely() {
    Scheduled_Integration_Job__c job = new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = 'Noop Wrong Token - Account',
      Scheduler_Name__c = 'Noop Wrong Token - Account',
      Integration_Type__c = 'Noop',
      Source_Object__c = 'Account',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Claimed',
      Lease_Token__c = 'correct-token',
      Lease_Expires_At__c = System.now().addMinutes(5),
      Next_Run_At__c = System.now().addMinutes(-1)
    );
    insert job;

    Test.startTest();
    System.enqueueJob(
      new ScheduledIntegrationJobProcessor(job.Id, 'wrong-token')
    );
    Test.stopTest();

    Scheduled_Integration_Job__c afterRun = [
      SELECT Status__c, Lease_Token__c, Last_Dispatched_At__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :job.Id
    ];
    System.assertEquals('Claimed', afterRun.Status__c);
    System.assertEquals('correct-token', afterRun.Lease_Token__c);
    System.assertEquals(null, afterRun.Last_Dispatched_At__c);
  }

  @isTest
  static void testScheduledProcessorCompatibilityBranches() {
    Scheduled_Integration_Job__c qbJob = new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = 'QBO Sync - Unknown',
      Scheduler_Name__c = 'QBO Sync - Unknown',
      Integration_Type__c = 'QuickBooks',
      Source_Object__c = 'Unknown',
      Frequency_Value__c = 1,
      Frequency_Type__c = 'Hours',
      Status__c = 'Active'
    );
    Scheduled_Integration_Job__c shopifyJob = new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = 'Shopify Sync - Unknown [Out]',
      Scheduler_Name__c = 'Shopify Sync - Unknown [Out]',
      Integration_Type__c = 'Shopify',
      Source_Object__c = 'Unknown',
      Direction__c = 'Out',
      Frequency_Value__c = 1,
      Frequency_Type__c = 'Hours',
      Status__c = 'Active'
    );
    insert new List<Scheduled_Integration_Job__c>{ qbJob, shopifyJob };

    Test.startTest();
    new ScheduledIntegrationHeartbeat().execute(null);
    System.enqueueJob(new ScheduledIntegrationJobProcessor(qbJob.Id));
    System.enqueueJob(new ScheduledIntegrationJobProcessor(shopifyJob.Id));
    Test.stopTest();

    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Scheduled_Integration_Job__c
        WHERE Integration_Type__c IN ('QuickBooks', 'Shopify')
      ]
    );
  }
}
