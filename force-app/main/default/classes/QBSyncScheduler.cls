global class QBSyncScheduler implements Schedulable {

    private String targetObject;
    private String direction;

    global QBSyncScheduler(String targetObject) {
        this(targetObject, 'Out');
    }

    global QBSyncScheduler(String targetObject, String direction) {
        this.targetObject = targetObject;
        this.direction = String.isBlank(direction) ? 'Out' : direction;
    }

    global void execute(SchedulableContext sc) {
        try {
            System.debug('Running scheduler for Object: ' + targetObject);
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
                if (direction == 'In') {
                    QBInvoiceToOrderSyncBatch orderBatch = new QBInvoiceToOrderSyncBatch();
                    Database.executeBatch(orderBatch, 10);
                } else {
                    List<Order> unsyncedOrders = [SELECT Id FROM Order WHERE QuickbookID__c = null AND Status IN ('Draft', 'Activated')];
                    if (!unsyncedOrders.isEmpty()) {
                        Set<Id> orderIds = new Map<Id, Order>(unsyncedOrders).keySet();
                        Database.executeBatch(new QBSalesOrderSyncBatch(orderIds, true), 1);
                    }
                }
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
                String cmObjName = Schema.getGlobalDescribe().containsKey('QuickBridgeTLG__Credit_Memo__c') ? 'QuickBridgeTLG__Credit_Memo__c' : 'Credit_Memo__c';
                List<SObject> unsyncedMemos = Database.query('SELECT Id FROM ' + cmObjName + ' WHERE External_Id__c = null');
                if (!unsyncedMemos.isEmpty()) Database.executeBatch(new QuickBooksCreditMemoBatch(new Map<Id, SObject>(unsyncedMemos).keySet(), true), 10);
            }
            else if (targetObject == 'PurchaseOrders' || targetObject == 'Purchase Order') {
                String poObjName = Schema.getGlobalDescribe().containsKey('QuickBridgeTLG__Purchase_Order__c') ? 'QuickBridgeTLG__Purchase_Order__c' : 'Purchase_Order__c';
                List<SObject> unsyncedPOs = Database.query('SELECT Id FROM ' + poObjName + ' WHERE External_Id__c = null');
                if (!unsyncedPOs.isEmpty()) Database.executeBatch(new QuickBooksPurchaseOrderBatch(new Map<Id, SObject>(unsyncedPOs).keySet(), true), 10);
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