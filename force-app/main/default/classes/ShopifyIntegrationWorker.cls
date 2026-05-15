public with sharing class ShopifyIntegrationWorker {
    public static void process(Integration_Work_Item__c item) {
        String operation = normalize(item.Operation__c);
        Id sourceId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);

        if (operation == 'customeroutbound' || operation == 'customerupsert') {
            if (sourceId == null) throw new ShopifyIntegrationWorkerException('Shopify customer work requires a Salesforce Id.');
            Database.executeBatch(new ShopifyCustomersOutboundBatch(new Set<Id>{ sourceId }, isInitialSync(item)), 10);
            return;
        }
        if (operation == 'orderoutbound' || operation == 'orderupsert') {
            if (sourceId == null) throw new ShopifyIntegrationWorkerException('Shopify order work requires a Salesforce Id.');
            Database.executeBatch(new ShopifyOrdersOutboundBatch(new Set<Id>{ sourceId }, isInitialSync(item)), 10);
            return;
        }
        if (operation == 'productoutbound' || operation == 'productupsert') {
            if (sourceId == null) throw new ShopifyIntegrationWorkerException('Shopify product work requires a Salesforce Id.');
            Database.executeBatch(new ShopifyProductsOutboundBatch(new Set<Id>{ sourceId }, isInitialSync(item)), 10);
            return;
        }
        throw new ShopifyIntegrationWorkerException('Unsupported Shopify operation: ' + item.Operation__c);
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

    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    public class ShopifyIntegrationWorkerException extends Exception {}
}
