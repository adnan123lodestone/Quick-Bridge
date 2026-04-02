global class KlaviyoProfilesBatchScheduler implements Schedulable {
    
    global void execute(SchedulableContext SC) {
        KlaviyoProfilesBatch batch = new KlaviyoProfilesBatch();
        Database.executeBatch(batch, 1);
    }
    
}