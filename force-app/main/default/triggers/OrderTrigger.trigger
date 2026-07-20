trigger OrderTrigger on Order (after update) {
  if (Trigger.isAfter && Trigger.isUpdate && !QuickBooksInvoiceHandler.isProcessing && !QBInvoiceToOrderSyncBatch.isProcessing) {
    QuickBooksInvoiceHandler.handleOrderEvents(Trigger.new, Trigger.oldMap, true);
  }
}