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
        String jobId = QBSchedulerController.scheduleJob('15', 'Minutes', 'Account');
        Test.stopTest();

        System.assertNotEquals(null, jobId);

        List<Map<String, Object>> jobs = QBSchedulerController.getScheduledJobs();
        System.assertNotEquals(null, jobs);

        QBSchedulerController.deleteSpecificJob('QBO Sync - Account');
    }

    @isTest
    static void testScheduleJobHoursDaysWeeksMonths() {
        Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
        Test.startTest();
        String hoursJob = QBSchedulerController.scheduleJob('2', 'Hours', 'Contact');
        String daysJob = QBSchedulerController.scheduleJob('3', 'Days', 'Product2');
        String weeksJob = QBSchedulerController.scheduleJob('1', 'Weeks', 'Order');
        String monthsJob = QBSchedulerController.scheduleJob('1', 'Months', 'Invoice__c');
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
        System.assertEquals('Salesforce to QuickBooks Online', summary.get('direction'));

        QBSchedulerController.togglePauseStatus(true);
        System.assertEquals(true, QBSchedulerController.getPauseStatus());

        QBSchedulerController.togglePauseStatus(false);
        System.assertEquals(false, QBSchedulerController.getPauseStatus());

        List<Map<String, Object>> runs = QBSchedulerController.getRecentRuns(null);
        System.assertEquals(0, runs.size());
    }

    @isTest
    static void testEditSpecificJobAndDeleteJob() {
        Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
        Test.startTest();
        String msg = QBSchedulerController.editSpecificJob('QBO Sync - Account', '10', 'Minutes');
        Test.stopTest();

        System.assert(msg != null);
        QBSchedulerController.deleteSpecificJob('QBO Sync - Account');
    }

    @isTest
    static void testShopifyLogicalScheduleLifecycle() {
        Test.setMock(HttpCalloutMock.class, new QBSchedulerMock());
        Test.startTest();
        String jobId = QBSchedulerController.scheduleShopifyJob('15', 'Minutes', 'Customers', false);
        String editMessage = QBSchedulerController.editShopifyJob('Shopify Sync - Customers [In]', '1', 'Hours');
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assert(editMessage.contains('Success'));
        System.assertNotEquals(null, QBSchedulerController.getShopifyScheduledJobs());
        QBSchedulerController.deleteShopifyJob('Shopify Sync - Customers [In]');
        System.assertNotEquals(null, QBSchedulerController.stopShopifyJob());
    }

    @isTest
    static void testShopifySummaryAndInvalidSchedulePaths() {
        Map<String, String> summary = QBSchedulerController.getShopifySyncSettingsSummary();
        System.assertEquals('Incremental Sync', summary.get('type'));

        Boolean didThrow = false;
        try {
            QBSchedulerController.scheduleShopifyJob('abc', 'Hours', 'Customers', false);
        } catch (Exception e) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow);

        List<Map<String, Object>> runs = QBSchedulerController.getRecentRuns('08e000000000000AAA');
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
            Status__c = 'Active',
            Next_Run_At__c = System.now().addMinutes(-1)
        );

        Test.startTest();
        ScheduledIntegrationHeartbeat.dispatchDueSchedules();
        Test.stopTest();

        Scheduled_Integration_Job__c afterRun = [
            SELECT Last_Run_At__c, Next_Run_At__c, Processor_Job_Id__c
            FROM Scheduled_Integration_Job__c
            WHERE Logical_Job_Key__c = 'Noop Sync - Account'
            LIMIT 1
        ];
        System.assertNotEquals(null, afterRun.Last_Run_At__c);
        System.assertNotEquals(null, afterRun.Next_Run_At__c);
        System.assertNotEquals(null, afterRun.Processor_Job_Id__c);
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

        System.assertEquals(2, [SELECT Count() FROM Scheduled_Integration_Job__c WHERE Integration_Type__c IN ('QuickBooks', 'Shopify')]);
    }
}