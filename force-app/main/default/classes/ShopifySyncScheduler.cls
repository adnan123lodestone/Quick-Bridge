global class ShopifySyncScheduler implements Schedulable {

    private String targetObject;
    private Boolean isSfToShopify;

    global ShopifySyncScheduler(String targetObject, Boolean isSfToShopify) {
        this.targetObject = targetObject;
        this.isSfToShopify = isSfToShopify == true;
    }

    global void execute(SchedulableContext sc) {
        try {
            IntegrationUsageService.incrementTaskUsage('Shopify', 1);
            System.debug('ShopifySyncScheduler running for: ' + targetObject + ' direction: ' + (isSfToShopify ? 'SF→Shopify' : 'Shopify→SF'));

            if (targetObject == 'Customers' || targetObject == 'Customer') {
                if (isSfToShopify) {
                    Map<Id, Account> unsyncedAccounts = new Map<Id, Account>([
                        SELECT Id FROM Account
                        WHERE RecordType.DeveloperName = 'PersonAccount'
                          AND Shopify_ID__c = null
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
                        SELECT Id FROM Order WHERE Shopify_ID__c = null
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
                        SELECT Id FROM Product2 WHERE Shopify_ID__c = null
                    ]);
                    if (!unsyncedProducts.isEmpty()) {
                        Database.executeBatch(new ShopifyProductsOutboundBatch(unsyncedProducts.keySet(), true), 10);
                    }
                } else {
                    Database.executeBatch(new ShopifyProductsBatch(), 1);
                }
            }
        } catch (Exception e) {
            ErrorLogUtility.logException('Shopify', 'ShopifySyncScheduler.execute', e, null, null);
            throw e;
        }
    }
}