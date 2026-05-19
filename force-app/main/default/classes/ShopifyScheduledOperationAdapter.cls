public with sharing class ShopifyScheduledOperationAdapter implements ScheduledOperationAdapter {
    @TestVisible private static Boolean skipExecutionForTests = false;

    public void execute(Scheduled_Integration_Job__c job) {
        if (Test.isRunningTest() && skipExecutionForTests == true) {
            return;
        }
        new ShopifySyncScheduler(job.Source_Object__c, job.Direction__c == 'Out').execute(null);
    }
}