public with sharing class QBPurchaseOrderWorker {
    public static void process(Integration_Work_Item__c item) {
        Id purchaseOrderId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);
        if (purchaseOrderId == null) {
            throw new QBPurchaseOrderWorkerException('Purchase order work item has no Salesforce Id.');
        }
        QuickBooksPurchaseOrderBatch batch = new QuickBooksPurchaseOrderBatch(new Set<Id>{ purchaseOrderId }, isInitialSync(item));
        batch.execute(null, new List<SObject>{ new Purchase_Order__c(Id = purchaseOrderId) });
    }

    private static Boolean isInitialSync(Integration_Work_Item__c item) {
        Map<String, Object> payload = IntegrationWorkService.parsePayload(item);
        return payload.containsKey('isInitialSync') && payload.get('isInitialSync') == true;
    }

    private static Id parseId(String primaryValue, String fallbackValue) {
        try {
            return (Id) (String.isBlank(primaryValue) ? fallbackValue : primaryValue);
        } catch (Exception e) {
            return null;
        }
    }

    public class QBPurchaseOrderWorkerException extends Exception {}
}