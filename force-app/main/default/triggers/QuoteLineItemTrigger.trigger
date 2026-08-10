trigger QuoteLineItemTrigger on QuoteLineItem (after insert, after update) {
    if (QBTriggerHandler.isQuoteProcessing) return;

    Set<Id> quoteIds = new Set<Id>();
    for (QuoteLineItem qli : Trigger.new) {
        if (qli.QuoteId != null) {
            quoteIds.add(qli.QuoteId);
        }
    }

    if (!quoteIds.isEmpty()) {
        List<Quote> quotesToSync = [SELECT Id, Name FROM Quote WHERE Id IN :quoteIds];
        QBTriggerHandler.handleQuoteTrigger(quotesToSync, null, false, true);
    }
}