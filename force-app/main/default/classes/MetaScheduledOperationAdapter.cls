public with sharing class MetaScheduledOperationAdapter implements ScheduledOperationAdapter, DeferredScheduledOperationAdapter {
    public void execute(Scheduled_Integration_Job__c job) {
        IntegrationWorkService.enqueue(buildRequest(job, null));
    }

    public ConnectorScheduleDispatchResult dispatch(
        Scheduled_Integration_Job__c job,
        String leaseToken
    ) {
        return ConnectorWorkOrchestrationService.dispatchScheduled(
            job,
            leaseToken,
            buildRequest(job, leaseToken)
        );
    }

    @TestVisible
    private static IntegrationWorkRequest buildRequest(
        Scheduled_Integration_Job__c job,
        String leaseToken
    ) {
        String sourceObject = job == null || String.isBlank(job.Source_Object__c)
            ? 'CampaignSync'
            : job.Source_Object__c;
        String operation = sourceObject == 'Insights' || sourceObject == 'InsightsSync'
            ? 'InsightsSync'
            : 'CampaignSync';
        return ConnectorWorkOrchestrationService.scheduledRequest(
            job,
            leaseToken,
            'Meta',
            operation,
            sourceObject,
            MetaConfigService.CONNECTOR_KEY + ':' + operation,
            'Meta:' + operation,
            null
        );
    }
}