@IsTest
private class MetaConnectionValidatorTest {
    @TestSetup
    static void setupData() {
        Connector_Instance__c instanceRecord = new Connector_Instance__c(
            Name = 'Meta',
            Connector_Key__c = 'meta',
            Connector_Label__c = 'Meta',
            Active__c = true,
            Entitlement_Status__c = 'Active',
            Health_Status__c = 'Unknown',
            Named_Credential__c = 'Meta_Graph_API'
        );
        insert instanceRecord;
        insert new List<Connector_Config_Value__c>{
            valueRecord(instanceRecord.Id, 'accessTokenRef', 'Meta_Access_Token_Reference', true),
            valueRecord(instanceRecord.Id, 'adAccountId', 'act_123', false),
            valueRecord(instanceRecord.Id, 'pageId', 'page-123', false),
            valueRecord(instanceRecord.Id, 'instagramBusinessAccountId', 'ig-123', false)
        };
    }

    @IsTest
    static void validationConfirmsConfiguredAssetsAndUpdatesHealth() {
        Test.setMock(HttpCalloutMock.class, new ValidationMock(200, '{"id":"validated"}'));

        Test.startTest();
        MetaConnectionValidator.ValidationResult result = MetaConnectionValidator.validateConnection();
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('Healthy', result.status);
        Connector_Instance__c refreshed = [
            SELECT Health_Status__c, Last_Health_Check_At__c
            FROM Connector_Instance__c
            WHERE Connector_Key__c = 'meta'
            LIMIT 1
        ];
        System.assertEquals('Healthy', refreshed.Health_Status__c);
        System.assertNotEquals(null, refreshed.Last_Health_Check_At__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM QuickBridge_Admin_Audit__c WHERE Connector_Key__c = 'meta' AND Action__c = 'CONNECTION_VALIDATE']
        );
    }

    @IsTest
    static void validationSanitizesPermissionFailuresAndUpdatesHealth() {
        Test.setMock(HttpCalloutMock.class, new ValidationMock(403, '{"error":{"message":"permission denied token=do-not-expose"}}'));

        Test.startTest();
        MetaConnectionValidator.ValidationResult result = MetaConnectionValidator.validateConnection();
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('Error', result.status);
        System.assert(result.message.contains('permission check failed'));
        System.assertEquals(false, result.message.contains('do-not-expose'));
        System.assertEquals(
            'Error',
            [SELECT Health_Status__c FROM Connector_Instance__c WHERE Connector_Key__c = 'meta' LIMIT 1].Health_Status__c
        );
    }

    private static Connector_Config_Value__c valueRecord(Id instanceId, String fieldKey, String value, Boolean secretReference) {
        return new Connector_Config_Value__c(
            Name = 'meta:' + fieldKey,
            Connector_Instance__c = instanceId,
            Connector_Key__c = 'meta',
            Field_Key__c = fieldKey,
            Value__c = value,
            Is_Secret_Reference__c = secretReference
        );
    }

    private class ValidationMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        ValidationMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(responseBody);
            return response;
        }
    }
}