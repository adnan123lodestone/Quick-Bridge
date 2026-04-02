global class ShopifyCustomersBatchScheduler implements Schedulable {
    
    global void execute(SchedulableContext SC) {
        ShopifyCustomersBatch batch = new ShopifyCustomersBatch();
        Database.executeBatch(batch, 1);
    }
    
}