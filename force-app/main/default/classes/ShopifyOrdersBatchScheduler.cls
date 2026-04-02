global class ShopifyOrdersBatchScheduler implements Schedulable {
    
    global void execute(SchedulableContext SC) {
        ShopifyOrdersBatch batch = new ShopifyOrdersBatch();
        Database.executeBatch(batch, 1);
    }
    
}