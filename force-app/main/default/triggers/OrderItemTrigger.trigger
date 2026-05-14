trigger OrderItemTrigger on OrderItem (after insert, after update) {
    // if (Trigger.isAfter && !QuickBooksInvoiceHandler.isProcessing 
    //     && !QBTriggerHandler.isOrderProcessing && !QBInvoiceToOrderSyncBatch.isProcessing) {
    //     if (Trigger.isInsert) {
    //         QuickBooksInvoiceHandler.handleOrderItemEvents(Trigger.new, null, true, false);
    //     } else if (Trigger.isUpdate) {
    //         QuickBooksInvoiceHandler.handleOrderItemEvents(Trigger.new, Trigger.oldMap, false, true);
    //     }
    // }
}