@IsTest
public class IntegrationWorkTestFactory {
    public static IntegrationWorkRequest request(String integration, String operation, String sourceObject, String sourceRecordId, String lockKey) {
        IntegrationWorkRequest request = new IntegrationWorkRequest();
        request.integration = integration;
        request.operation = operation;
        request.sourceObject = sourceObject;
        request.sourceRecordId = sourceRecordId;
        request.lockKey = lockKey;
        request.payloadJson = JSON.serialize(new Map<String, Object>{ 'test' => true });
        return request;
    }

    public static Integration_Work_Item__c workItem(String statusValue, String lockKey) {
        IntegrationWorkRequest request = request('Test', 'Noop', 'Account', String.valueOf(Crypto.getRandomInteger()), lockKey);
        Id itemId = IntegrationWorkService.enqueue(request);
        Integration_Work_Item__c item = [
            SELECT Id, Status__c, Lock_Key__c, Unique_Key__c
            FROM Integration_Work_Item__c
            WHERE Id = :itemId
            LIMIT 1
        ];
        if (statusValue != null && statusValue != item.Status__c) {
            item.Status__c = statusValue;
            update item;
        }
        return item;
    }
}