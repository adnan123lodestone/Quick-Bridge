trigger PurchaseOrderTrigger on Purchase_Order__c (after insert, after update) {
    Set<Id> idsToProcess = new Set<Id>();
    
    if (Trigger.isAfter) {
        for (Purchase_Order__c po : Trigger.new) {
            idsToProcess.add(po.Id);
        }
        
        if (!idsToProcess.isEmpty() && !System.isBatch()) {
            for (Id recordId : idsToProcess) {
                IntegrationWorkService.enqueueQuickBooksWork(
                    'PurchaseOrderUpsert',
                    'Purchase_Order__c',
                    recordId,
                    'PurchaseOrder:' + String.valueOf(recordId),
                    Trigger.isInsert
                );
            }
        }
    }
}