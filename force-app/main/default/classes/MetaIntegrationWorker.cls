public with sharing class MetaIntegrationWorker implements IntegrationWorkHandler {
    public void handle(Integration_Work_Item__c item) {
        if (item == null) {
            throw new MetaIntegrationWorkerException('Integration work item is required.');
        }
        String operation = item.Operation__c;
        if (operation == 'LeadAd' || operation == 'CommentAttribution' || operation == 'MessengerMessage') {
            if (!processEvent(MetaPayloadNormalizer.fromJson(item.Payload__c))) {
                logIgnoredEvent(operation, 1);
            }
        } else if (operation == 'WebhookEvent') {
            Integer ignoredCount = 0;
            for (MetaPayloadNormalizer.NormalizedEvent eventRecord : MetaPayloadNormalizer.fromWebhookPayload(item.Payload__c)) {
                if (!processEvent(eventRecord)) {
                    ignoredCount++;
                }
            }
            if (ignoredCount > 0) {
                logIgnoredEvent(operation, ignoredCount);
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

    private static Boolean processEvent(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        if (!MetaPayloadNormalizer.isProcessableEvent(eventRecord)) {
            return false;
        }
        if (eventRecord.interactionType == 'Meta Lead Ad') {
            MetaLeadAdsService.processLeadgenEvent(eventRecord);
            return true;
        }
        if (eventRecord.interactionType == 'Comment') {
            // Existing connector instances may not yet have this optional
            // setting. Preserve their historical default (enabled); only an
            // explicit false disables comment attribution.
            String commentAttributionSetting = MetaConfigService.getValue('commentAttributionEnabled');
            if (String.isNotBlank(commentAttributionSetting)
                && !MetaConfigService.isEnabled('commentAttributionEnabled')) {
                return true;
            }
            MetaCommentAttributionProcessor.process(eventRecord);
            return true;
        }
        if (eventRecord.interactionType == 'Messenger Message') {
            MetaMessengerMessageProcessor.process(eventRecord);
            return true;
        }
        return false;
    }

    private static void logIgnoredEvent(String operation, Integer ignoredCount) {
        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = 'Meta';
        context.classMethodName = 'MetaIntegrationWorker.handle';
        context.errorCategory = 'Ignored Webhook Event';
        context.errorMessage = 'Ignored ' + ignoredCount + ' malformed or unsupported Meta event(s) for operation ' + operation + '.';
        ErrorLogUtility.logError(context);
    }

    public class MetaIntegrationWorkerException extends Exception {}
}