global class ShopifyOrdersBatchScheduler implements Schedulable {
    
    global void execute(SchedulableContext SC) {
        try {
            ShopifyOrdersBatch batch = new ShopifyOrdersBatch();
            Database.executeBatch(batch, 1);
        } catch (Exception e) {
            ErrorLogUtility.logException('Shopify', 'ShopifyOrdersBatchScheduler.execute', e, null, null);
            throw e;
        }
    }
    
}