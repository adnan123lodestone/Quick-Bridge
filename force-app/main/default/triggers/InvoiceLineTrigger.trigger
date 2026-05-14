trigger InvoiceLineTrigger on QuickBridgeTLG__Invoice_Line__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            QuickBooksInvoiceHandler.handleInvoiceLineEvents(Trigger.new, null, true, false);
        } 
        else if (Trigger.isUpdate) {
            QuickBooksInvoiceHandler.handleInvoiceLineEvents(Trigger.new, Trigger.oldMap, false, true);
        }
    }
}