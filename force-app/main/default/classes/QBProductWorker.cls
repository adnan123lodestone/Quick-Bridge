public with sharing class QBProductWorker {
    public static void process(Integration_Work_Item__c item) {
        Id productId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);
        if (productId == null) {
            throw new QBProductWorkerException('Product work item has no Salesforce Id.');
        }

        List<Product2> products = [
            SELECT Id, Name, ProductCode, IsActive, QuickbookID__c, Sale_Price__c
            FROM Product2
            WHERE Id = :productId
            LIMIT 1
        ];
        if (products.isEmpty()) {
            throw new QBProductWorkerException('Product not found: ' + productId);
        }

        QBProductService.syncProductsToQuickBooks(products, isInitialSync(item));
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

    public class QBProductWorkerException extends Exception {}
}