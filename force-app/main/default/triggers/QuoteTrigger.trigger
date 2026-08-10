trigger QuoteTrigger on Quote (after insert, after update) {
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        if (!QBTriggerHandler.isQuoteProcessing && !QBQuoteToEstimateSyncBatch.isProcessing && !QBEstimateToQuoteSyncBatch.isProcessing) {
            QBTriggerHandler.handleQuoteTrigger(Trigger.new, Trigger.oldMap, Trigger.isInsert, Trigger.isUpdate);
        }
    }
}