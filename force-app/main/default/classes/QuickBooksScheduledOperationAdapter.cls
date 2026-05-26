public with sharing class QuickBooksScheduledOperationAdapter implements ScheduledOperationAdapter {
    @TestVisible private static Boolean skipExecutionForTests = false;

    public void execute(Scheduled_Integration_Job__c job) {
        if (Test.isRunningTest() && skipExecutionForTests == true) {
            return;
        }
        run(job.Source_Object__c, job.Direction__c);
    }

    public static void run(String targetObject, String direction) {
        try {
            IntegrationUsageService.incrementTaskUsage('QuickBooks', 1);
            String safeDirection = String.isBlank(direction) ? 'Out' : direction;

            if (targetObject == 'Account' || targetObject == 'Accounts') {
                Database.executeBatch(new QBCustomerToAccountSyncBatch(), 50);
            } else if (targetObject == 'Vendor' || targetObject == 'Vendors') {
                Database.executeBatch(new QBVendorToAccountSyncBatch(), 50);
            } else if (targetObject == 'Product' || targetObject == 'Products') {
                Database.executeBatch(new QBItemToProductSyncBatch(), 50);
            } else if (targetObject == 'Order' || targetObject == 'Orders') {
                if (safeDirection == 'In') {
                    Database.executeBatch(new QBInvoiceToOrderSyncBatch(), 10);
                } else {
                    List<Order> unsyncedOrders = [
                        SELECT Id
                        FROM Order
                        WHERE QuickbookID__c = null AND Status IN ('Draft', 'Activated')
                    ];
                    if (!unsyncedOrders.isEmpty()) {
                        Database.executeBatch(
                            new QBSalesOrderSyncBatch(new Map<Id, Order>(unsyncedOrders).keySet(), true),
                            1
                        );
                    }
                }
            } else if (targetObject == 'Invoices' || targetObject == 'Invoice') {
                String mappedObj = QBObjectMappings.getInvoiceSourceObject();
                String query = 'SELECT Id FROM ' + mappedObj + ' WHERE External_Id__c = null';
                List<SObject> unsyncedRecords = Database.query(query);

                if (!unsyncedRecords.isEmpty()) {
                    Database.executeBatch(
                        new QuickBooksInvoiceBatch(new Map<Id, SObject>(unsyncedRecords).keySet(), true),
                        10
                    );
                }
            } else if (targetObject == 'CreditMemos' || targetObject == 'Credit Memo') {
                Map<Id, Credit_Memo__c> unsyncedMemos = new Map<Id, Credit_Memo__c>([
                    SELECT Id
                    FROM Credit_Memo__c
                    WHERE External_Id__c = null
                ]);
                if (!unsyncedMemos.isEmpty()) {
                    Database.executeBatch(new QuickBooksCreditMemoBatch(unsyncedMemos.keySet(), true), 10);
                }
            } else if (targetObject == 'PurchaseOrders' || targetObject == 'Purchase Order') {
                Map<Id, Purchase_Order__c> unsyncedPurchaseOrders = new Map<Id, Purchase_Order__c>([
                    SELECT Id
                    FROM Purchase_Order__c
                    WHERE External_Id__c = null
                ]);
                if (!unsyncedPurchaseOrders.isEmpty()) {
                    Database.executeBatch(new QuickBooksPurchaseOrderBatch(unsyncedPurchaseOrders.keySet(), true), 10);
                }
            } else if (targetObject == 'ItemSalesTax' || targetObject == 'Item Sales Tax') {
                Database.executeBatch(new QBOItemSalesTaxBatch(), 1);
            }
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QuickBooksScheduledOperationAdapter.run',
                e,
                null,
                null
            );
            throw e;
        }
    }
}