public with sharing class KlaviyoScheduledOperationAdapter
    implements ScheduledOperationAdapter, DeferredScheduledOperationAdapter {
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

    /**
     * Transfers terminal schedule ownership to ConnectorInboundBatch. The
     * original execute method remains the legacy compatibility entry point.
     */
    public ConnectorScheduleDispatchResult dispatch(
        Scheduled_Integration_Job__c job,
        String leaseToken
    ) {
        if (Test.isRunningTest() && skipExecutionForTests == true) {
            return ConnectorScheduleDispatchResult.synchronous();
        }
        try {
            ConnectorExecutionRequest request = buildSharedRequest(job, leaseToken);
            request = request.normalizedCopy();
            Id asyncJobId = Database.executeBatch(new ConnectorInboundBatch(request), 1);
            return ConnectorScheduleDispatchResult.deferred(asyncJobId);
        } catch (Exception exceptionValue) {
            return ConnectorScheduleDispatchResult.failed(
                ConnectorExecutionResult.sanitizeError(exceptionValue.getMessage())
            );
        }
    }

    @TestVisible
    private static ConnectorExecutionRequest buildSharedRequest(
        Scheduled_Integration_Job__c job,
        String leaseToken
    ) {
        if (job == null) {
            throw new KlaviyoScheduledOperationException(
                'A Klaviyo scheduled integration job is required.'
            );
        }
        if (
            String.isNotBlank(job.Direction__c) &&
            ConnectorOperationRegistry.normalizeDirection(job.Direction__c) !=
                ConnectorExecutionRequest.DIRECTION_INBOUND
        ) {
            throw new KlaviyoScheduledOperationException(
                'Klaviyo scheduled synchronization supports inbound direction only.'
            );
        }

        String sourceObject = String.isBlank(job.Source_Object__c)
            ? 'profiles'
            : job.Source_Object__c.toLowerCase();
        ConnectorExecutionRequest request = new ConnectorExecutionRequest();
        request.connectorKey = 'Klaviyo';
        request.direction = ConnectorExecutionRequest.DIRECTION_INBOUND;
        request.scheduleId = job.Id;
        request.leaseToken = leaseToken;
        request.correlationKey = job.Id == null ? null : String.valueOf(job.Id);
        request.scopeSize = 1;

        if (sourceObject == 'profile' || sourceObject == 'profiles') {
            request.operationKey = 'Profiles';
            request.salesforceObject = 'Account';
            request.externalEntity = 'Profile';
        } else if (sourceObject == 'list' || sourceObject == 'lists') {
            request.operationKey = 'Lists';
            request.salesforceObject = 'Campaign';
            request.externalEntity = 'List';
        } else if (sourceObject == 'event' || sourceObject == 'events') {
            request.operationKey = 'Events';
            request.salesforceObject = 'Event';
            request.externalEntity = 'Event';
        } else {
            throw new KlaviyoScheduledOperationException(
                'Unsupported Klaviyo scheduled source object: ' + sourceObject
            );
        }
        return request;
    }

    public class KlaviyoScheduledOperationException extends Exception {}
}
