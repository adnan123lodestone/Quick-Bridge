public with sharing class MetaConnectionValidator {
    public class ValidationResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String status { get; set; }
    }

    public static ValidationResult validateConnection() {
        ValidationResult result = new ValidationResult();
        try {
            MetaConfigService.requireConfiguredForApiSync();
            MetaApiClient client = MetaApiClient.configured();
            validateObject(client, MetaConfigService.adAccountId());
            validateObject(client, MetaConfigService.pageId());
            validateObject(client, MetaConfigService.instagramBusinessAccountId());
            updateHealth('Healthy');
            QuickBridgeAdminGuard.audit(
                'CONNECTION_VALIDATE',
                MetaConfigService.CONNECTOR_KEY,
                'Success',
                'Validated Meta ad account and configured Page/Instagram asset access.',
                null
            );
            result.success = true;
            result.status = 'Healthy';
            result.message = 'Meta connection validated successfully.';
        } catch (Exception e) {
            String message = MetaErrorMapper.sanitize(e.getMessage());
            updateHealth('Error');
            QuickBridgeAdminGuard.audit(
                'CONNECTION_VALIDATE',
                MetaConfigService.CONNECTOR_KEY,
                'Failure',
                message,
                null
            );
            result.success = false;
            result.status = 'Error';
            result.message = message;
        }
        return result;
    }

    private static void validateObject(MetaApiClient client, String metaId) {
        if (String.isBlank(metaId)) {
            return;
        }
        Map<String, Object> response = client.getObject('/' + metaId, new Map<String, String>{ 'fields' => 'id' });
        Object validatedId = response.get('id');
        if (validatedId == null || String.isBlank(String.valueOf(validatedId))) {
            throw new MetaConnectionValidatorException('Meta returned an invalid validation response.');
        }
    }

    private static void updateHealth(String healthStatus) {
        List<Connector_Instance__c> instances = [
            SELECT Id
            FROM Connector_Instance__c
            WHERE Connector_Key__c = :MetaConfigService.CONNECTOR_KEY
            LIMIT 1
        ];
        if (instances.isEmpty()) {
            return;
        }
        update new Connector_Instance__c(
            Id = instances[0].Id,
            Health_Status__c = healthStatus,
            Last_Health_Check_At__c = Datetime.now()
        );
    }

    public class MetaConnectionValidatorException extends Exception {}
}