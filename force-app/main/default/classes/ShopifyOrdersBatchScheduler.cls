global class ShopifyOrdersBatchScheduler implements Schedulable {
    @TestVisible 
    private static Boolean throwExceptionForTest = false;
    
    global void execute(SchedulableContext SC) {
        try {
            if (throwExceptionForTest) {
                throw new System.AsyncException('Forced Exception for Test Coverage');
            }
            ShopifyOrdersBatch batch = new ShopifyOrdersBatch();
            Database.executeBatch(batch, 1);
        } catch (Exception e) {
            ErrorLogUtility.logException('Shopify', 'ShopifyOrdersBatchScheduler.execute', e, null, null);
            throw e;
        }
    }
    
}