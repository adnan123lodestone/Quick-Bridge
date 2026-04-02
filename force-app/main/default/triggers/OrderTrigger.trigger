trigger OrderTrigger on Order (after update) {
    System.debug('Order Trigger fired - Context: ' + Trigger.operationType + ', Records: ' + Trigger.new.size());
    System.debug('Trigger flags - isProcessing: ' + QuickBooksInvoiceHandler.isProcessing + 
                ', isOrderProcessing: ' + QBTriggerHandler.isOrderProcessing + 
                ', QBInvoiceToOrderSyncBatch.isProcessing: ' + QBInvoiceToOrderSyncBatch.isProcessing);
    
    if (Trigger.isAfter && Trigger.isUpdate && !QuickBooksInvoiceHandler.isProcessing 
        && !QBTriggerHandler.isOrderProcessing && !QBInvoiceToOrderSyncBatch.isProcessing) {
        
        System.debug('Calling handleOrderEvents for UPDATE');
        QuickBooksInvoiceHandler.handleOrderEvents(Trigger.new, Trigger.oldMap, true);
    } else {
        System.debug('Order Trigger skipped due to conditions');
    }
}