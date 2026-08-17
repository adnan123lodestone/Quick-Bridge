trigger CreditMemoLineTrigger on Credit_Memo_Line__c (after insert, after update, after delete) {
    Set<Id> parentCmIds = new Set<Id>();
    
    List<Credit_Memo_Line__c> lines = Trigger.isDelete ? Trigger.old : Trigger.new;
    for (Credit_Memo_Line__c line : lines) {
        sObject lineObj = (sObject)line;
        Id parentId = null;
        try { parentId = (Id)lineObj.get('Credit_Memo__c'); } catch(Exception e){}
        if(parentId == null) { try { parentId = (Id)lineObj.get('QuickBridgeTLG__Credit_Memo__c'); } catch(Exception e){} }
        if (parentId != null) {
            parentCmIds.add(parentId);
        }
    }
    
    if (!parentCmIds.isEmpty() && !System.isBatch()) {
        for (Id cmId : parentCmIds) {
            IntegrationWorkService.enqueueQuickBooksWork(
                'CreditMemoUpsert',
                'Credit_Memo__c',
                cmId,
                'CreditMemo:' + String.valueOf(cmId),
                false
            );
        }
    }
}