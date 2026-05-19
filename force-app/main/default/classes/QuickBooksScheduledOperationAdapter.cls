public with sharing class QuickBooksScheduledOperationAdapter implements ScheduledOperationAdapter {
    @TestVisible private static Boolean skipExecutionForTests = false;

    public void execute(Scheduled_Integration_Job__c job) {
        if (Test.isRunningTest() && skipExecutionForTests == true) {
            return;
        }
        new QBSyncScheduler(job.Source_Object__c).execute(null);
    }
}
