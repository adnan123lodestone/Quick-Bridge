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
        try {
            QBProductService.syncProductsToQuickBooks(scope, isInsert);
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBProductBatch.execute',
                e,
                'Product2',
                scope == null || scope.isEmpty() ? null : scope[0].Id
            );
            throw e;
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('QBProductBatch completed');
    }
}