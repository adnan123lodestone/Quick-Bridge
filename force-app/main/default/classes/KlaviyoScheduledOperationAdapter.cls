public with sharing class KlaviyoScheduledOperationAdapter implements ScheduledOperationAdapter {
    @TestVisible private static Boolean skipExecutionForTests = false;

    public void execute(Scheduled_Integration_Job__c job) {
        if (Test.isRunningTest() && skipExecutionForTests == true) {
            return;
        }

        String sourceObject = job == null || String.isBlank(job.Source_Object__c)
            ? null
            : job.Source_Object__c.toLowerCase();
        if (String.isBlank(sourceObject) || sourceObject == 'profile' || sourceObject == 'profiles') {
            Database.executeBatch(new KlaviyoProfilesBatch(), 1);
        } else if (sourceObject == 'list' || sourceObject == 'lists') {
            Database.executeBatch(new KlaviyoListsBatch(), 1);
        } else if (sourceObject == 'event' || sourceObject == 'events') {
            Database.executeBatch(new KlaviyoEventsBatch(), 1);
        } else {
            System.debug(LoggingLevel.WARN, 'Unsupported Klaviyo scheduled source object: ' + sourceObject);
        }
    }
}