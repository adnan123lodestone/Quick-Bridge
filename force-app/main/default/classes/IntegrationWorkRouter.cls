public with sharing class IntegrationWorkRouter {
    public static void process(Integration_Work_Item__c item) {
        if (item == null) {
            throw new IntegrationWorkRouteException('Work item is required.');
        }
        String integration = normalize(item.Integration__c);
        String operation = normalize(item.Operation__c);

        if (integration == 'quickbooks') {
            processQuickBooks(operation, item);
            return;
        }
        if (integration == 'shopify') {
            ShopifyIntegrationWorker.process(item);
            return;
        }
        if (integration == 'carrier') {
            CarrierIntegrationWorker.process(item);
            return;
        }
        if (integration == 'payment') {
            PaymentIntegrationWorker.process(item);
            return;
        }
        if (integration == 'qr') {
            QRIntegrationWorker.process(item);
            return;
        }
        if (integration == 'usage') {
            UsageIntegrationWorker.process(item);
            return;
        }

        throw new IntegrationWorkRouteException('Unsupported integration: ' + item.Integration__c);
    }

    private static void processQuickBooks(String operation, Integration_Work_Item__c item) {
        if (operation == 'accountupsert') {
            QBAccountWorker.process(item);
            return;
        }
        if (operation == 'productupsert') {
            QBProductWorker.process(item);
            return;
        }
        if (operation == 'invoiceupsert') {
            QBInvoiceWorker.process(item);
            return;
        }
        if (operation == 'creditmemoupsert') {
            QBCreditMemoWorker.process(item);
            return;
        }
        if (operation == 'purchaseorderupsert') {
            QBPurchaseOrderWorker.process(item);
            return;
        }
        throw new IntegrationWorkRouteException('Unsupported QuickBooks operation: ' + item.Operation__c);
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    public class IntegrationWorkRouteException extends Exception {}
}
