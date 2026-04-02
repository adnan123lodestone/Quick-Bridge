global class KlaviyoListsBatchScheduler implements Schedulable {
    
    global void execute(SchedulableContext SC) {
        KlaviyoListsBatch batch = new KlaviyoListsBatch();
        Database.executeBatch(batch, 1);
    }
    
}