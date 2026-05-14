trigger InvoiceTrigger on QuickBridgeTLG__Invoice__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        QuickBooksInvoiceHandler.handleInvoiceEvents(Trigger.new, Trigger.oldMap, true);
    }
}