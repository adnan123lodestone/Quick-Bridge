public class QBProductBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {
    private List<Product2> productsToProcess;
    private Boolean isInsert;
    
    public QBProductBatch(List<Product2> products, Boolean isInsert) {
        this.productsToProcess = products;
        this.isInsert = isInsert;
    }
    
    public Iterable<sObject> start(Database.BatchableContext bc) {
        return productsToProcess;
    }
    
    public void execute(Database.BatchableContext bc, List<Product2> scope) {
        QBProductService.syncProductsToQuickBooks(scope, isInsert);
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('QBProductBatch completed');
    }
}