public class QBOrderBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {
    private List<Order> ordersToProcess;
    private Boolean isInsert;
    
    public QBOrderBatch(List<Order> orders, Boolean isInsert) {
        this.ordersToProcess = orders;
        this.isInsert = isInsert;
    }
    
    public Iterable<sObject> start(Database.BatchableContext bc) {
        return ordersToProcess;
    }
    
    public void execute(Database.BatchableContext bc, List<Order> scope) {
       
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('QBOrderBatch completed');
    }
}