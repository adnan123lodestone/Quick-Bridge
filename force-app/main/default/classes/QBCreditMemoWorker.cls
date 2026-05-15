public with sharing class QBCreditMemoWorker {
    public static void process(Integration_Work_Item__c item) {
        Id creditMemoId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);
        if (creditMemoId == null) {
            throw new QBCreditMemoWorkerException('Credit memo work item has no Salesforce Id.');
        }
        QuickBooksCreditMemoBatch batch = new QuickBooksCreditMemoBatch(new Set<Id>{ creditMemoId }, isInitialSync(item));
        batch.execute(null, new List<SObject>{ new Credit_Memo__c(Id = creditMemoId) });
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

    public class QBCreditMemoWorkerException extends Exception {}
}
