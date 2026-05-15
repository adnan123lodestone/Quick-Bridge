public with sharing class QRIntegrationWorker {
    public static void process(Integration_Work_Item__c item) {
        Id invoiceId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);
        if (invoiceId == null) {
            throw new QRIntegrationWorkerException('QR work requires an invoice id.');
        }
        InvoiceQRService.generateAndSaveQRCode(invoiceId);
    }

    private static Id parseId(String primaryValue, String fallbackValue) {
        try {
            return (Id) (String.isBlank(primaryValue) ? fallbackValue : primaryValue);
        } catch (Exception e) {
            return null;
        }
    }

    public class QRIntegrationWorkerException extends Exception {}
}