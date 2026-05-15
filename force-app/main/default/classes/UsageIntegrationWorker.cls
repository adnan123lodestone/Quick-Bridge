public with sharing class UsageIntegrationWorker {
    public static void process(Integration_Work_Item__c item) {
        Map<String, Object> payload = IntegrationWorkService.parsePayload(item);
        String productKey = payload.containsKey('productKey') ? String.valueOf(payload.get('productKey')) : item.Source_Record_Id__c;
        if (String.isBlank(productKey)) {
            throw new UsageIntegrationWorkerException('Usage work requires productKey.');
        }
        IntegrationUsageService.recordSuccessfulPaymentTask(productKey);
    }

    public class UsageIntegrationWorkerException extends Exception {}
}
