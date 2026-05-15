public class QuickBooksInvoiceHandler {

    public static Boolean isProcessing = false;
    private static Boolean isBatchContext = false;

    public static void handleInvoiceEvents(List<SObject> newInvoices, Map<Id, SObject> oldMap, Boolean isUpdate) {
        if (isBatchContext || isProcessing) return;

        isProcessing = true;
        Set<Id> invoiceIdsToProcess = new Set<Id>();

        try {
            if (isUpdate) {
                for (SObject inv : newInvoices) {
                    SObject oldInv = oldMap.get(inv.Id);

                    String newQbId = null;
                    String oldQbId = null;
                    try { newQbId = (String)inv.get('QuickBridgeTLG__External_Id__c'); } catch(Exception e){}
                    try { oldQbId = (String)oldInv.get('QuickBridgeTLG__External_Id__c'); } catch(Exception e){}

                    // if (newQbId != null || (newQbId != oldQbId)) {
                    //     invoiceIdsToProcess.add(inv.Id);
                    // }
                    invoiceIdsToProcess.add(inv.Id);
                }
            }

            if (!invoiceIdsToProcess.isEmpty()) {
                enqueueInvoiceWork(invoiceIdsToProcess, false);
            }
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QuickBooksInvoiceHandler.handleInvoiceEvents',
                e,
                'Invoice__c',
                newInvoices == null || newInvoices.isEmpty() ? null : newInvoices[0].Id
            );
        } finally {
            isProcessing = false;
        }
    }

    public static void handleInvoiceLineEvents(List<SObject> newItems, Map<Id, SObject> oldMap, Boolean isInsert, Boolean isUpdate) {
        if (isBatchContext) return;

        isProcessing = true;
        Set<Id> invoiceIdsForInitialSync = new Set<Id>();
        Set<Id> invoiceIdsForUpdate = new Set<Id>();
        List<SObject> itemsForUpdate = new List<SObject>();
        Set<Id> invoiceIds = new Set<Id>();

        try {
            for (SObject item : newItems) {
                Id parentId = (Id)item.get('QuickBridgeTLG__Invoice__c'); // Invoice lookup field on line item
                if(parentId != null) invoiceIds.add(parentId);
            }

            String query = 'SELECT Id, QuickBridgeTLG__External_Id__c FROM QuickBridgeTLG__Invoice__c WHERE Id IN :invoiceIds';
            Map<Id, SObject> invoicesWithDetails = new Map<Id, SObject>((List<SObject>)Database.query(query));

            if (isInsert) {
                for (SObject item : newItems) {
                    Id parentId = (Id)item.get('QuickBridgeTLG__Invoice__c');
                    if(parentId == null) continue;

                    SObject parentInv = invoicesWithDetails.get(parentId);
                    String qbId = (String)parentInv.get('QuickBridgeTLG__External_Id__c');

                    if (qbId == null) {
                        invoiceIdsForInitialSync.add(parentId);
                    } else {
                        invoiceIdsForUpdate.add(parentId);
                        itemsForUpdate.add(item);
                    }
                }
            }

            if (isUpdate) {
                for (SObject item : newItems) {
                    Id parentId = (Id)item.get('QuickBridgeTLG__Invoice__c');
                    if(parentId == null) continue;

                    SObject oldItem = oldMap.get(item.Id);
                    Decimal newQty = (Decimal)item.get('QuickBridgeTLG__Quantity__c');
                    Decimal oldQty = (Decimal)oldItem.get('QuickBridgeTLG__Quantity__c');
                    Decimal newRate = (Decimal)item.get('QuickBridgeTLG__Rate__c');
                    Decimal oldRate = (Decimal)oldItem.get('QuickBridgeTLG__Rate__c');

                    if (newQty != oldQty || newRate != oldRate) {
                        SObject parentInv = invoicesWithDetails.get(parentId);
                        String qbId = (String)parentInv.get('QuickBridgeTLG__External_Id__c');
                        if (qbId != null) {
                            invoiceIdsForUpdate.add(parentId);
                            itemsForUpdate.add(item);
                        }
                    }
                }
            }

            if (!invoiceIdsForInitialSync.isEmpty()) {
                enqueueInvoiceWork(invoiceIdsForInitialSync, true);
            }
            if (!invoiceIdsForUpdate.isEmpty()) {
                enqueueInvoiceWork(invoiceIdsForUpdate, false);
            }

        } catch (Exception e) {
            System.debug('Error in handleInvoiceLineEvents: ' + e.getMessage());
            ErrorLogUtility.logException(
                'QuickBooks',
                'QuickBooksInvoiceHandler.handleInvoiceLineEvents',
                e,
                'Invoice__c',
                invoiceIds.isEmpty() ? null : new List<Id>(invoiceIds)[0]
            );
        } finally {
            isProcessing = false;
        }
    }

    public static void handleOrderEvents(List<Order> newOrders, Map<Id, Order> oldMap, Boolean isUpdate) {
        if (isBatchContext || isProcessing || QBTriggerHandler.isOrderProcessing || QBInvoiceToOrderSyncBatch.isProcessing) {
            return;
        }

        isProcessing = true;
        Set<Id> orderIdsToProcess = new Set<Id>();

        try {
            if (isUpdate) {
                for (Order ord : newOrders) {
                    Order oldOrd = oldMap == null ? null : oldMap.get(ord.Id);
                    if (oldOrd == null) {
                        continue;
                    }
                    if (ord.EffectiveDate != oldOrd.EffectiveDate ||
                        ord.TotalAmount != oldOrd.TotalAmount ||
                        (ord.QuickbookID__c != null && ord.QuickbookID__c != oldOrd.QuickbookID__c)) {
                        orderIdsToProcess.add(ord.Id);
                    }
                }
            }

            if (!orderIdsToProcess.isEmpty()) {
                enqueueOrderInvoiceWork(orderIdsToProcess, false);
            }
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QuickBooksInvoiceHandler.handleOrderEvents',
                e,
                'Order',
                newOrders == null || newOrders.isEmpty() ? null : newOrders[0].Id
            );
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
        List<SObject> itemsForUpdate = new List<SObject>();
        Set<Id> orderIds = new Set<Id>();

        try {
            for (OrderItem item : newItems) {
                if (item.OrderId != null) {
                    orderIds.add(item.OrderId);
                }
            }

            Map<Id, Order> ordersWithDetails = new Map<Id, Order>([
                SELECT Id, QuickbookID__c
                FROM Order
                WHERE Id IN :orderIds
            ]);

            if (isInsert) {
                for (OrderItem item : newItems) {
                    Order parentOrder = ordersWithDetails.get(item.OrderId);
                    if (parentOrder == null) {
                        continue;
                    }
                    if (parentOrder.QuickbookID__c == null) {
                        orderIdsForInitialSync.add(item.OrderId);
                    } else {
                        orderIdsForUpdate.add(item.OrderId);
                        itemsForUpdate.add(item);
                    }
                }
            }

            if (isUpdate) {
                for (OrderItem item : newItems) {
                    OrderItem oldItem = oldMap == null ? null : oldMap.get(item.Id);
                    if (oldItem == null) {
                        continue;
                    }
                    if (item.Quantity != oldItem.Quantity ||
                        item.OrderId != oldItem.OrderId ||
                        item.UnitPrice != oldItem.UnitPrice ||
                        item.QB_LineItemID__c != oldItem.QB_LineItemID__c) {

                        Order parentOrder = ordersWithDetails.get(item.OrderId);
                        if (parentOrder != null && parentOrder.QuickbookID__c != null) {
                            orderIdsForUpdate.add(item.OrderId);
                            itemsForUpdate.add(item);
                        }
                    }
                }
            }

            if (!orderIdsForInitialSync.isEmpty()) {
                enqueueOrderInvoiceWork(orderIdsForInitialSync, true);
            }

            if (!orderIdsForUpdate.isEmpty()) {
                enqueueOrderInvoiceWork(orderIdsForUpdate, false);
            }
        } catch (Exception e) {
            System.debug('Error in handleOrderItemEvents: ' + e.getMessage());
            ErrorLogUtility.logException(
                'QuickBooks',
                'QuickBooksInvoiceHandler.handleOrderItemEvents',
                e,
                'Order',
                orderIds.isEmpty() ? null : new List<Id>(orderIds)[0]
            );
        } finally {
            isProcessing = false;
        }
    }

    public static void handleOrderItemDeletion(List<OrderItem> deletedItems) {
        if (isBatchContext || isProcessing || QBTriggerHandler.isOrderProcessing || QBInvoiceToOrderSyncBatch.isProcessing) {
            return;
        }

        isProcessing = true;
        Set<Id> orderIdsForUpdate = new Set<Id>();
        Set<Id> orderIds = new Set<Id>();

        try {
            for (OrderItem item : deletedItems) {
                if (item.OrderId != null) {
                    orderIds.add(item.OrderId);
                }
            }

            for (Order ord : [
                SELECT Id, QuickbookID__c
                FROM Order
                WHERE Id IN :orderIds
                AND QuickbookID__c != null
            ]) {
                orderIdsForUpdate.add(ord.Id);
            }

            if (!orderIdsForUpdate.isEmpty()) {
                enqueueOrderInvoiceWork(orderIdsForUpdate, false);
            }
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QuickBooksInvoiceHandler.handleOrderItemDeletion',
                e,
                'Order',
                orderIds.isEmpty() ? null : new List<Id>(orderIds)[0]
            );
        } finally {
            isProcessing = false;
        }
    }

    public static void setBatchContext(Boolean value) {
        isBatchContext = value;
    }

    private static void enqueueInvoiceWork(Set<Id> invoiceIds, Boolean isInitialSync) {
        for (Id invoiceId : invoiceIds) {
            IntegrationWorkService.enqueueQuickBooksWork(
                'InvoiceUpsert',
                'Invoice__c',
                invoiceId,
                'Invoice:' + String.valueOf(invoiceId),
                isInitialSync
            );
        }
    }

    private static void enqueueOrderInvoiceWork(Set<Id> orderIds, Boolean isInitialSync) {
        for (Id orderId : orderIds) {
            IntegrationWorkService.enqueueQuickBooksWork(
                'InvoiceUpsert',
                'Order',
                orderId,
                'Order:' + String.valueOf(orderId),
                isInitialSync
            );
        }
    }
}
// public class QuickBooksInvoiceHandler {

//     public static Boolean isProcessing = false;
//     private static Boolean isBatchContext = false;

//     public static void handleOrderEvents(List<Order> newOrders, Map<Id, Order> oldMap, Boolean isUpdate) {
//         // Skip processing if we're already in a batch context
//         if (isBatchContext || isProcessing || QBTriggerHandler.isOrderProcessing || QBInvoiceToOrderSyncBatch.isProcessing) {
//             return;
//         }

//         isProcessing = true;
//         Set<Id> orderIdsToProcess = new Set<Id>();

//         try {
//             if (isUpdate) {
//                 for (Order ord : newOrders) {
//                     Order oldOrd = oldMap.get(ord.Id);
//                     // Only process if there are meaningful changes
//                     if (ord.EffectiveDate != oldOrd.EffectiveDate ||
//                         ord.TotalAmount != oldOrd.TotalAmount ||
//                         (ord.QuickbookID__c != null && ord.QuickbookID__c != oldOrd.QuickbookID__c)) {
//                         orderIdsToProcess.add(ord.Id);
//                     }
//                 }
//             }

//             if (!orderIdsToProcess.isEmpty()) {
//                 // Start batch job for updates (these orders already have QB IDs)
//                 Database.executeBatch(new QuickBooksInvoiceBatch(orderIdsToProcess, false), 1);
//             }
//         } finally {
//             isProcessing = false;
//         }
//     }

//     public static void handleOrderItemEvents(List<OrderItem> newItems, Map<Id, OrderItem> oldMap, Boolean isInsert, Boolean isUpdate) {
//         if (isBatchContext) {
//             System.debug('Skipping due to batch context');
//             return;
//         }

//         isProcessing = true;
//         Set<Id> orderIdsForInitialSync = new Set<Id>();
//         Set<Id> orderIdsForUpdate = new Set<Id>();
//         List<OrderItem> itemsForUpdate = new List<OrderItem>(); // Store items that need updates

//         try {
//             // Get all parent order IDs
//             Set<Id> orderIds = new Set<Id>();
//             for (OrderItem item : newItems) {
//                 orderIds.add(item.OrderId);
//             }

//             // Query orders with their QuickBooks IDs
//             Map<Id, Order> ordersWithDetails = new Map<Id, Order>([
//                 SELECT Id, QuickbookID__c
//                 FROM Order
//                 WHERE Id IN :orderIds
//             ]);

//             if (isInsert) {
//                 for (OrderItem item : newItems) {
//                     Order parentOrder = ordersWithDetails.get(item.OrderId);
//                     if (parentOrder.QuickbookID__c == null) {
//                         orderIdsForInitialSync.add(item.OrderId);
//                     } else {
//                         orderIdsForUpdate.add(item.OrderId);
//                         itemsForUpdate.add(item); // Add the new item
//                     }
//                 }
//             }

//             if (isUpdate) {
//                 for (OrderItem item : newItems) {
//                     OrderItem oldItem = oldMap.get(item.Id);
//                     // Enhanced change detection
//                     if (
//                         item.Quantity != oldItem.Quantity ||

//                         item.OrderId != oldItem.OrderId ||
//                         item.UnitPrice != oldItem.UnitPrice ||

//                         item.QB_LineItemID__c != oldItem.QB_LineItemID__c) {

//                         Order parentOrder = ordersWithDetails.get(item.OrderId);
//                         if (parentOrder.QuickbookID__c != null) {
//                             orderIdsForUpdate.add(item.OrderId);
//                             itemsForUpdate.add(item); // Add the updated item
//                         }
//                     }
//                 }
//             }

//             // Start batch jobs
//             if (!orderIdsForInitialSync.isEmpty()) {
//                 Database.executeBatch(new QuickBooksInvoiceBatch(orderIdsForInitialSync, true), 1);
//             }

//             if (!orderIdsForUpdate.isEmpty()) {
//                 // Pass the trigger items to the batch for accurate data
//                 Database.executeBatch(new QuickBooksInvoiceBatch(orderIdsForUpdate, false, itemsForUpdate), 1);
//             }

//         } catch (Exception e) {
//             System.debug('Error in handleOrderItemEvents: ' + e.getMessage());
//             System.debug('Stack trace: ' + e.getStackTraceString());
//         } finally {
//             isProcessing = false;
//         }
//     }

//     // Method to handle OrderItem deletion
//     public static void handleOrderItemDeletion(List<OrderItem> deletedItems) {
//         if (isBatchContext || isProcessing || QBTriggerHandler.isOrderProcessing || QBInvoiceToOrderSyncBatch.isProcessing) {
//             return;
//         }

//         isProcessing = true;
//         Set<Id> orderIdsForUpdate = new Set<Id>();

//         try {
//             // Get parent order IDs for deleted items
//             Set<Id> orderIds = new Set<Id>();
//             for (OrderItem item : deletedItems) {
//                 orderIds.add(item.OrderId);
//             }

//             // Query orders to check if they have QB IDs
//             for (Order ord : [SELECT Id, QuickbookID__c FROM Order WHERE Id IN :orderIds AND QuickbookID__c != null]) {
//                 orderIdsForUpdate.add(ord.Id);
//             }

//             if (!orderIdsForUpdate.isEmpty()) {
//                 Database.executeBatch(new QuickBooksInvoiceBatch(orderIdsForUpdate, false), 1);
//             }

//         } finally {
//             isProcessing = false;
//         }
//     }

//     public static void setBatchContext(Boolean value) {
//         isBatchContext = value;
//     }
// }
