global class ShopifyCustomersBatchScheduler implements Schedulable {
    @TestVisible 
    private static Boolean throwExceptionForTest = false;
    
    global void execute(SchedulableContext SC) {
        try {
            if (throwExceptionForTest) {
                throw new System.AsyncException('Forced Exception for Test Coverage');
            }
            ShopifyCustomersBatch batch = new ShopifyCustomersBatch();
            Database.executeBatch(batch, 1);
        } catch (Exception e) {
            ErrorLogUtility.logException('Shopify', 'ShopifyCustomersBatchScheduler.execute', e, null, null);
            throw e;
        }
    }
    
}