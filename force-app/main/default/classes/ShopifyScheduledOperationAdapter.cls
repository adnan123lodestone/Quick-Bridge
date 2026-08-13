public with sharing class ShopifyScheduledOperationAdapter implements ScheduledOperationAdapter, DeferredScheduledOperationAdapter {
    @TestVisible private static Boolean skipExecutionForTests = false;

    public void execute(Scheduled_Integration_Job__c job) {
        if (Test.isRunningTest() && skipExecutionForTests == true) {
            return;
        }
        run(job.Source_Object__c, job.Direction__c);
    }

    public ConnectorScheduleDispatchResult dispatch(
        Scheduled_Integration_Job__c job,
        String leaseToken
    ) {
        if (Test.isRunningTest() && skipExecutionForTests == true) {
            return ConnectorScheduleDispatchResult.synchronous();
        }
        if (job == null) {
            return ConnectorScheduleDispatchResult.failed(
                'A Shopify scheduled integration job is required.'
            );
        }

        String targetObject = job.Source_Object__c;
        if (
            targetObject != 'Customers' && targetObject != 'Customer' &&
            targetObject != 'Products' && targetObject != 'Product' &&
            targetObject != 'Orders' && targetObject != 'Order'
        ) {
            run(targetObject, job.Direction__c);
            return ConnectorScheduleDispatchResult.synchronous();
        }

        try {
            Boolean outbound = job.Direction__c == 'Out';
            Boolean customer = targetObject == 'Customers' || targetObject == 'Customer';
            Boolean product = targetObject == 'Products' || targetObject == 'Product';
            ConnectorExecutionRequest request = new ConnectorExecutionRequest();
            request.connectorKey = 'Shopify';
            request.operationKey = targetObject;
            request.direction = outbound ? 'Outbound' : 'Inbound';
            request.salesforceObject = customer ? 'Account' : (product ? 'Product2' : 'Order');
            request.externalEntity = customer ? 'Customer' : (product ? 'Product' : 'Order');
            request.initialSync = outbound;
            request.scopeSize = outbound ? 10 : 1;
            request.scheduleId = job.Id;
            request.leaseToken = leaseToken;
            request.correlationKey = 'Shopify:' + String.valueOf(job.Id);

            if (outbound) {
                if (customer) {
                    request.recordIds = new List<Id>(new Map<Id, Account>([
                        SELECT Id FROM Account WHERE Shopify_ID__c = null
                    ]).keySet());
                } else if (product) {
                    request.recordIds = new List<Id>(new Map<Id, Product2>([
                        SELECT Id FROM Product2 WHERE Shopify_ID__c = null
                    ]).keySet());
                } else {
                    request.recordIds = new List<Id>(new Map<Id, Order>([
                        SELECT Id FROM Order WHERE Shopify_ID__c = null
                    ]).keySet());
                }
                if (request.recordIds.isEmpty()) {
                    return ConnectorScheduleDispatchResult.synchronous();
                }
                return ConnectorScheduleDispatchResult.deferred(
                    Database.executeBatch(new ConnectorOutboundBatch(request), 10)
                );
            }

            return ConnectorScheduleDispatchResult.deferred(
                Database.executeBatch(new ConnectorInboundBatch(request), 1)
            );
        } catch (Exception exceptionValue) {
            ErrorLogUtility.logException(
                'Shopify',
                'ShopifyScheduledOperationAdapter.run',
                exceptionValue,
                null,
                null
            );
            return ConnectorScheduleDispatchResult.failed(exceptionValue.getMessage());
        }
    }

    public static void run(String targetObject, String direction) {
        try {
            Boolean isSfToShopify = direction == 'Out';

            if (targetObject == 'Customers' || targetObject == 'Customer') {
                if (isSfToShopify) {
                    Map<Id, Account> unsyncedAccounts = new Map<Id, Account>([
                        SELECT Id
                        FROM Account
                        WHERE Shopify_ID__c = null
                    ]);
                    if (!unsyncedAccounts.isEmpty()) {
                        Database.executeBatch(new ShopifyCustomersOutboundBatch(unsyncedAccounts.keySet(), true), 10);
                    }
                } else {
                    Database.executeBatch(new ShopifyCustomersBatch(), 1);
                }
            } else if (targetObject == 'Orders' || targetObject == 'Order') {
                if (isSfToShopify) {
                    Map<Id, Order> unsyncedOrders = new Map<Id, Order>([
                        SELECT Id
                        FROM Order
                        WHERE Shopify_ID__c = null
                    ]);
                    if (!unsyncedOrders.isEmpty()) {
                        Database.executeBatch(new ShopifyOrdersOutboundBatch(unsyncedOrders.keySet(), true), 10);
                    }
                } else {
                    Database.executeBatch(new ShopifyOrdersBatch(), 1);
                }
            } else if (targetObject == 'Products' || targetObject == 'Product') {
                if (isSfToShopify) {
                    Map<Id, Product2> unsyncedProducts = new Map<Id, Product2>([
                        SELECT Id
                        FROM Product2
                        WHERE Shopify_ID__c = null
                    ]);
                    if (!unsyncedProducts.isEmpty()) {
                        Database.executeBatch(new ShopifyProductsOutboundBatch(unsyncedProducts.keySet(), true), 10);
                    }
                } else {
                    Database.executeBatch(new ShopifyProductsBatch(), 1);
                }
            }
        } catch (Exception e) {
            ErrorLogUtility.logException('Shopify', 'ShopifyScheduledOperationAdapter.run', e, null, null);
            throw e;
        }
    }
}