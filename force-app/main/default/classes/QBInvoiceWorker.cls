public with sharing class QBInvoiceWorker {
    public static void process(Integration_Work_Item__c item) {
        Id invoiceId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);
        if (invoiceId == null) {
            throw new QBInvoiceWorkerException('Invoice work item has no Salesforce Id.');
        }
        QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>{ invoiceId }, isInitialSync(item));
        batch.execute(null, new List<SObject>{ new Invoice__c(Id = invoiceId) });
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

    public class QBInvoiceWorkerException extends Exception {}
}
