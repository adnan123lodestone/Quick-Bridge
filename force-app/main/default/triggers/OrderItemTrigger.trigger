trigger OrderItemTrigger on OrderItem (after insert, after update, after delete) {
    try {
        if (Trigger.isAfter) {
            if (Trigger.isInsert) {
                System.debug('OrderItem Insert Trigger executing');
                QuickBooksInvoiceHandler.handleOrderItemEvents(Trigger.new, null, true, false);
            } 
            else if (Trigger.isUpdate) {
                System.debug('OrderItem Update Trigger executing');
                QuickBooksInvoiceHandler.handleOrderItemEvents(Trigger.new, Trigger.oldMap, false, true);
            }
          
        }
    } catch(Exception e) {
        System.debug('Error in OrderItemTrigger: ' + e.getMessage());
        // Consider adding error logging here
    }
}