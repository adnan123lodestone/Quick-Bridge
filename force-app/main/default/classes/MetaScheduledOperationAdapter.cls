public with sharing class MetaScheduledOperationAdapter implements ScheduledOperationAdapter {
    public void execute(Scheduled_Integration_Job__c job) {
        String sourceObject = job == null || String.isBlank(job.Source_Object__c) ? 'CampaignSync' : job.Source_Object__c;
        String operation = sourceObject == 'Insights' || sourceObject == 'InsightsSync' ? 'InsightsSync' : 'CampaignSync';
        IntegrationWorkRequest request = new IntegrationWorkRequest();
        request.integration = 'Meta';
        request.operation = operation;
        request.sourceObject = sourceObject;
        request.sourceRecordId = MetaConfigService.CONNECTOR_KEY + ':' + operation;
        request.lockKey = 'Meta:' + operation;
        request.payloadJson = JSON.serialize(new Map<String, Object>{ 'scheduled' => true, 'operation' => operation });
        IntegrationWorkService.enqueue(request);
    }
}