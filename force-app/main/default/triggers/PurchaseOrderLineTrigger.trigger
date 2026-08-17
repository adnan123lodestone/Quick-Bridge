trigger PurchaseOrderLineTrigger on Purchase_Order_Line__c (after insert, after update, after delete) {
    Set<Id> parentPoIds = new Set<Id>();
    
    List<Purchase_Order_Line__c> lines = Trigger.isDelete ? Trigger.old : Trigger.new;
    for (Purchase_Order_Line__c line : lines) {
        sObject lineObj = (sObject)line;
        Id parentId = null;
        try { parentId = (Id)lineObj.get('Purchase_Order__c'); } catch(Exception e){}
        if(parentId == null) { try { parentId = (Id)lineObj.get('QuickBridgeTLG__Purchase_Order__c'); } catch(Exception e){} }
        if (parentId != null) {
            parentPoIds.add(parentId);
        }
    }
    
    if (!parentPoIds.isEmpty() && !System.isBatch()) {
        for (Id poId : parentPoIds) {
            IntegrationWorkService.enqueueQuickBooksWork(
                'PurchaseOrderUpsert',
                'Purchase_Order__c',
                poId,
                'PurchaseOrder:' + String.valueOf(poId),
                false
            );
        }
    }
}