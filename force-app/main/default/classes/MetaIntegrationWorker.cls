public with sharing class MetaIntegrationWorker implements IntegrationWorkHandler {
    public void handle(Integration_Work_Item__c item) {
        if (item == null) {
            throw new MetaIntegrationWorkerException('Integration work item is required.');
        }
        String operation = item.Operation__c;
        if (operation == 'LeadAd') {
            MetaLeadAdsService.processLeadgenEvent(MetaPayloadNormalizer.fromJson(item.Payload__c));
        } else if (operation == 'CommentAttribution') {
            MetaCommentAttributionProcessor.process(MetaPayloadNormalizer.fromJson(item.Payload__c));
        } else if (operation == 'MessengerMessage') {
            MetaMessengerMessageProcessor.process(MetaPayloadNormalizer.fromJson(item.Payload__c));
        } else if (operation == 'WebhookEvent') {
            for (MetaPayloadNormalizer.NormalizedEvent eventRecord : MetaPayloadNormalizer.fromWebhookPayload(item.Payload__c)) {
                if (eventRecord.interactionType == 'Meta Lead Ad') {
                    MetaLeadAdsService.processLeadgenEvent(eventRecord);
                } else if (eventRecord.interactionType == 'Comment') {
                    MetaCommentAttributionProcessor.process(eventRecord);
                } else if (eventRecord.interactionType == 'Messenger Message') {
                    MetaMessengerMessageProcessor.process(eventRecord);
                }
            }
        } else if (operation == 'CampaignSync') {
            MetaCampaignSyncService.syncCampaignHierarchy();
        } else if (operation == 'InsightsSync') {
            MetaInsightsSyncService.syncInsights();
        } else if (operation == 'Reconciliation') {
            MetaReconciliationService.reconcile();
        } else {
            throw new MetaIntegrationWorkerException('Unsupported Meta operation: ' + operation);
        }
    }

    public class MetaIntegrationWorkerException extends Exception {}
}