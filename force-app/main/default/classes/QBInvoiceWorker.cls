public with sharing class QBInvoiceWorker implements IntegrationWorkHandler {
    public void handle(Integration_Work_Item__c item) {
        process(item);
    }

    public static void process(Integration_Work_Item__c item) {
        Id invoiceId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);
        if (invoiceId == null) {
            throw new QBInvoiceWorkerException('Invoice work item has no Salesforce Id.');
        }

        // Dynamically routing based on SObject type of the Source Salesforce Id
        if (invoiceId.getSObjectType() == Order.SObjectType) {
            // Reuse the batch selector so scheduled and single-record work hydrate
            // the exact same header, relationship, and line fields.
            List<Order> scope = QBSalesOrderSyncBatch.loadOrdersForSharedExecution(
                new Set<Id>{ invoiceId }
            );
            QBSalesOrderSyncBatch batch = new QBSalesOrderSyncBatch(new Set<Id>{ invoiceId }, isInitialSync(item));
            ConnectorExecutionResult result = batch.executeSharedScope(scope);
            if (result == null || result.hasFailures()) {
                throw new QBInvoiceWorkerException(
                    'Order invoice synchronization failed. ' +
                    ConnectorExecutionResult.sanitizeError(
                        result == null ? null : result.errorSummary
                    )
                );
            }
        } else {
            // Dynamic SObject construction to support any other mapped Invoice object (e.g. Invoice__c)
            SObject scopeRecord = invoiceId.getSObjectType().newSObject(invoiceId);
            QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>{ invoiceId }, isInitialSync(item));
            batch.execute(null, new List<SObject>{ scopeRecord });
        }
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