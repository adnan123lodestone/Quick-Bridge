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
}