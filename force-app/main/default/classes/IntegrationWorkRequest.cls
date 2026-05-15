public class IntegrationWorkRequest {
    @AuraEnabled public String integration { get; set; }
    @AuraEnabled public String operation { get; set; }
    @AuraEnabled public String sourceObject { get; set; }
    @AuraEnabled public String sourceRecordId { get; set; }
    @AuraEnabled public Id sourceSalesforceId { get; set; }
    @AuraEnabled public String sourceExternalId { get; set; }
    @AuraEnabled public String lockKey { get; set; }
    @AuraEnabled public List<String> additionalLockKeys { get; set; }
    @AuraEnabled public String payloadJson { get; set; }
    @AuraEnabled public Integer maxAttempts { get; set; }
    @AuraEnabled public Datetime nextAttemptAt { get; set; }

    public static IntegrationWorkRequest quickBooks(String operation, String sourceObject, Id sourceId, String lockKey, Map<String, Object> payload) {
        IntegrationWorkRequest request = new IntegrationWorkRequest();
        request.integration = 'QuickBooks';
        request.operation = operation;
        request.sourceObject = sourceObject;
        request.sourceRecordId = sourceId == null ? null : String.valueOf(sourceId);
        request.sourceSalesforceId = sourceId;
        request.lockKey = lockKey;
        request.payloadJson = payload == null ? null : JSON.serialize(payload);
        return request;
    }
}