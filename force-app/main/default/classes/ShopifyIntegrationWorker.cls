public with sharing class ShopifyIntegrationWorker implements IntegrationWorkHandler {
    public void handle(Integration_Work_Item__c item) {
        process(item);
    }

    public static void process(Integration_Work_Item__c item) {
        String operation = normalize(item.Operation__c);
        Id sourceId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);

        if (operation == 'customeroutbound' || operation == 'customerupsert') {
            if (sourceId == null) throw new ShopifyIntegrationWorkerException('Shopify customer work requires a Salesforce Id.');
            executeSingleOutbound(item, sourceId, 'Customer', 'Account');
            return;
        }
        if (operation == 'orderoutbound' || operation == 'orderupsert') {
            if (sourceId == null) throw new ShopifyIntegrationWorkerException('Shopify order work requires a Salesforce Id.');
            executeSingleOutbound(item, sourceId, 'Order', 'Order');
            return;
        }
        if (operation == 'productoutbound' || operation == 'productupsert') {
            if (sourceId == null) throw new ShopifyIntegrationWorkerException('Shopify product work requires a Salesforce Id.');
            executeSingleOutbound(item, sourceId, 'Product', 'Product2');
            return;
        }
        throw new ShopifyIntegrationWorkerException('Unsupported Shopify operation: ' + item.Operation__c);
    }

    private static void executeSingleOutbound(
        Integration_Work_Item__c item,
        Id sourceId,
        String entity,
        String salesforceObject
    ) {
        ConnectorExecutionRequest request = new ConnectorExecutionRequest();
        request.connectorKey = 'Shopify';
        request.operationKey = entity;
        request.direction = 'Outbound';
        request.salesforceObject = salesforceObject;
        request.externalEntity = entity;
        request.recordIds = new List<Id>{ sourceId };
        request.initialSync = isInitialSync(item);
        request.scopeSize = 1;
        request.correlationKey = item == null ? null : String.valueOf(item.Id);

        ConnectorExecutionResult result = ConnectorExecutionService.executeSingle(request);
        if (result == null || result.hasFailures()) {
            if (result != null && result.retryable == true) {
                throw IntegrationRetryPolicy.exceptionForStatus(
                    429,
                    String.isBlank(result.errorSummary)
                        ? 'Shopify synchronization returned HTTP 429.'
                        : result.errorSummary + ' HTTP 429.'
                );
            }
            throw new ShopifyIntegrationWorkerException(
                result == null || String.isBlank(result.errorSummary)
                    ? 'Shopify ' + entity.toLowerCase() + ' synchronization failed.'
                    : result.errorSummary
            );
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

    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    public class ShopifyIntegrationWorkerException extends Exception {}
}
