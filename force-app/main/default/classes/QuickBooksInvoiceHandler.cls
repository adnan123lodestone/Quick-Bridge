public class QuickBooksInvoiceHandler {

    public static Boolean isProcessing = false;
    private static Boolean isBatchContext = false;
    
    public static void handleOrderEvents(List<Order> newOrders, Map<Id, Order> oldMap, Boolean isUpdate) {
        // Skip processing if we're already in a batch context
        if (isBatchContext || isProcessing || QBTriggerHandler.isOrderProcessing || QBInvoiceToOrderSyncBatch.isProcessing) {
            return;
        }
        
        isProcessing = true;
        Set<Id> orderIdsToProcess = new Set<Id>();
        
        try {
            if (isUpdate) {
                for (Order ord : newOrders) {
                    Order oldOrd = oldMap.get(ord.Id);
                    // Only process if there are meaningful changes
                    if (ord.EffectiveDate != oldOrd.EffectiveDate || 
                        ord.TotalAmount != oldOrd.TotalAmount ||
                        (ord.QuickbookID__c != null && ord.QuickbookID__c != oldOrd.QuickbookID__c)) {
                        orderIdsToProcess.add(ord.Id);
                    }
                }
            }
            
            if (!orderIdsToProcess.isEmpty()) {
                // Start batch job for updates (these orders already have QB IDs)
                Database.executeBatch(new QuickBooksInvoiceBatch(orderIdsToProcess, false), 1);
            }
        } finally {
            isProcessing = false;
        }
    }
    
    public static void handleOrderItemEvents(List<OrderItem> newItems, Map<Id, OrderItem> oldMap, Boolean isInsert, Boolean isUpdate) {
        if (isBatchContext) {
            System.debug('Skipping due to batch context');
            return;
        }
        
        isProcessing = true;
        Set<Id> orderIdsForInitialSync = new Set<Id>();
        Set<Id> orderIdsForUpdate = new Set<Id>();
        List<OrderItem> itemsForUpdate = new List<OrderItem>(); // Store items that need updates
        
        try {
            // Get all parent order IDs
            Set<Id> orderIds = new Set<Id>();
            for (OrderItem item : newItems) {
                orderIds.add(item.OrderId);
            }
            
            // Query orders with their QuickBooks IDs
            Map<Id, Order> ordersWithDetails = new Map<Id, Order>([
                SELECT Id, QuickbookID__c
                FROM Order 
                WHERE Id IN :orderIds
            ]);
            
            if (isInsert) {
                for (OrderItem item : newItems) {
                    Order parentOrder = ordersWithDetails.get(item.OrderId);
                    if (parentOrder.QuickbookID__c == null) {
                        orderIdsForInitialSync.add(item.OrderId);
                    } else {
                        orderIdsForUpdate.add(item.OrderId);
                        itemsForUpdate.add(item); // Add the new item
                    }
                }
            }
            
            if (isUpdate) {
                for (OrderItem item : newItems) {
                    OrderItem oldItem = oldMap.get(item.Id);
                    // Enhanced change detection
                    if (
                        item.Quantity != oldItem.Quantity ||
                        
                        item.OrderId != oldItem.OrderId ||
                        item.UnitPrice != oldItem.UnitPrice ||
                       
                        item.QB_LineItemID__c != oldItem.QB_LineItemID__c) {
                        
                        Order parentOrder = ordersWithDetails.get(item.OrderId);
                        if (parentOrder.QuickbookID__c != null) {
                            orderIdsForUpdate.add(item.OrderId);
                            itemsForUpdate.add(item); // Add the updated item
                        }
                    }
                }
            }
            
            // Start batch jobs
            if (!orderIdsForInitialSync.isEmpty()) {
                Database.executeBatch(new QuickBooksInvoiceBatch(orderIdsForInitialSync, true), 1);
            }
            
            if (!orderIdsForUpdate.isEmpty()) {
                // Pass the trigger items to the batch for accurate data
                Database.executeBatch(new QuickBooksInvoiceBatch(orderIdsForUpdate, false, itemsForUpdate), 1);
            }
            
        } catch (Exception e) {
            System.debug('Error in handleOrderItemEvents: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        } finally {
            isProcessing = false;
        }
    }

    // Method to handle OrderItem deletion
    public static void handleOrderItemDeletion(List<OrderItem> deletedItems) {
        if (isBatchContext || isProcessing || QBTriggerHandler.isOrderProcessing || QBInvoiceToOrderSyncBatch.isProcessing) {
            return;
        }
        
        isProcessing = true;
        Set<Id> orderIdsForUpdate = new Set<Id>();
        
        try {
            // Get parent order IDs for deleted items
            Set<Id> orderIds = new Set<Id>();
            for (OrderItem item : deletedItems) {
                orderIds.add(item.OrderId);
            }
            
            // Query orders to check if they have QB IDs
            for (Order ord : [SELECT Id, QuickbookID__c FROM Order WHERE Id IN :orderIds AND QuickbookID__c != null]) {
                orderIdsForUpdate.add(ord.Id);
            }
            
            if (!orderIdsForUpdate.isEmpty()) {
                Database.executeBatch(new QuickBooksInvoiceBatch(orderIdsForUpdate, false), 1);
            }
            
        } finally {
            isProcessing = false;
        }
    }
    
    public static void setBatchContext(Boolean value) {
        isBatchContext = value;
    }
}