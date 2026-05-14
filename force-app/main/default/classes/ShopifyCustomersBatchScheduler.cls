global class ShopifyCustomersBatchScheduler implements Schedulable {
    
    global void execute(SchedulableContext SC) {
        try {
            ShopifyCustomersBatch batch = new ShopifyCustomersBatch();
            Database.executeBatch(batch, 1);
        } catch (Exception e) {
            ErrorLogUtility.logException('Shopify', 'ShopifyCustomersBatchScheduler.execute', e, null, null);
            throw e;
        }
    }
    
}