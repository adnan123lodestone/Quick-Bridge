global class QBSyncScheduler implements Schedulable {

    private String targetObject;

    global QBSyncScheduler(String targetObject) {
        this.targetObject = targetObject;
    }

    global void execute(SchedulableContext sc) {
        try {
            System.debug('Running scheduler for Object: ' + targetObject);
            IntegrationUsageService.incrementTaskUsage('QuickBooks', 1);

            if (targetObject == 'Account' || targetObject == 'Accounts') {
                QBCustomerToAccountSyncBatch customerBatch = new QBCustomerToAccountSyncBatch();
                Database.executeBatch(customerBatch, 50);
            }
            else if (targetObject == 'Vendor' || targetObject == 'Vendors') {
                QBVendorToAccountSyncBatch vendorBatch = new QBVendorToAccountSyncBatch();
                Database.executeBatch(vendorBatch, 50);
            }
            else if (targetObject == 'Product' || targetObject == 'Products') {
                QBItemToProductSyncBatch productBatch = new QBItemToProductSyncBatch();
                Database.executeBatch(productBatch, 50);
            }
            else if (targetObject == 'Order' || targetObject == 'Orders') {
                QBInvoiceToOrderSyncBatch orderBatch = new QBInvoiceToOrderSyncBatch();
                Database.executeBatch(orderBatch, 10);
            }
            else if (targetObject == 'Invoices' || targetObject == 'Invoice') {
                String mappedObj = QBObjectMappings.getInvoiceSourceObject();
                String query = 'SELECT Id FROM ' + mappedObj + ' WHERE External_Id__c = null';
                List<SObject> unsyncedRecords = Database.query(query);

                if (!unsyncedRecords.isEmpty()) {
                    QuickBooksInvoiceBatch invoiceBatch = new QuickBooksInvoiceBatch(new Map<Id, SObject>(unsyncedRecords).keySet(), true);
                    Database.executeBatch(invoiceBatch, 10);
                }
            }
            else if (targetObject == 'CreditMemos' || targetObject == 'Credit Memo') {
                Map<Id, Credit_Memo__c> unsyncedMemos = new Map<Id, Credit_Memo__c>([SELECT Id FROM Credit_Memo__c WHERE External_Id__c = null]);
                if (!unsyncedMemos.isEmpty()) Database.executeBatch(new QuickBooksCreditMemoBatch(unsyncedMemos.keySet(), true), 10);
            }
            else if (targetObject == 'PurchaseOrders' || targetObject == 'Purchase Order') {
                Map<Id, Purchase_Order__c> unsyncedPOs = new Map<Id, Purchase_Order__c>([SELECT Id FROM Purchase_Order__c WHERE External_Id__c = null]);
                if (!unsyncedPOs.isEmpty()) Database.executeBatch(new QuickBooksPurchaseOrderBatch(unsyncedPOs.keySet(), true), 10);
            }
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBSyncScheduler.execute',
                e,
                null,
                null
            );
            throw e;
        }
    }
}