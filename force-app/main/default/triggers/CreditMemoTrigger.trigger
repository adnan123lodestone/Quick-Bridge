trigger CreditMemoTrigger on Credit_Memo__c (after insert, after update) {
    Set<Id> idsToProcess = new Set<Id>();
    
    if (Trigger.isAfter) {
        for (Credit_Memo__c cm : Trigger.new) {
            idsToProcess.add(cm.Id);
        }
        
        if (!idsToProcess.isEmpty() && !System.isBatch()) {
            for (Id recordId : idsToProcess) {
                IntegrationWorkService.enqueueQuickBooksWork(
                    'CreditMemoUpsert',
                    'Credit_Memo__c',
                    recordId,
                    'CreditMemo:' + String.valueOf(recordId),
                    Trigger.isInsert
                );
            }
        }
    }
}