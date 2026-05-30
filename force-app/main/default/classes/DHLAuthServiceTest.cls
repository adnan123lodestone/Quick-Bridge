@IsTest
private class DHLAuthServiceTest {
    @IsTest
    static void missingConfigIsRejected() {
        Boolean didThrow = false;
        try {
            DHLAuthService.getCredentialConfig();
        } catch (CalloutException e) {
            didThrow = true;
            System.assert(e.getMessage().contains('inactive'));
        }
        System.assertEquals(true, didThrow);
    }

    @IsTest
    static void inactiveConfigIsRejected() {
        Connector_Instance__c instanceRecord = createDhlInstance(false);
        insertValue(instanceRecord, 'DHL_Api_Key__c', 'api-key', false);
        insertValue(instanceRecord, 'apiSecretRef', 'api-secret', true);
        insertValue(instanceRecord, 'DHL_Account_Number__c', '123456789', false);

        Boolean didThrow = false;
        try {
            DHLAuthService.getCredentialConfig();
        } catch (CalloutException e) {
            didThrow = true;
            System.assert(e.getMessage().contains('inactive'));
        }
        System.assertEquals(true, didThrow);
    }

    @IsTest
    static void missingCredentialsAreRejected() {
        createDhlInstance(true);

        Boolean didThrow = false;
        try {
            DHLAuthService.getCredentialConfig();
        } catch (CalloutException e) {
            didThrow = true;
            System.assert(e.getMessage().contains('API key'));
        }
        System.assertEquals(true, didThrow);
    }

    @IsTest
    static void activeConfigBuildsBasicAuthAndUrls() {
        Connector_Instance__c instanceRecord = createDhlInstance(true);
        insertValue(instanceRecord, 'DHL_Api_Key__c', 'site-id', false);
        insertValue(instanceRecord, 'apiSecretRef', 'password', true);
        insertValue(instanceRecord, 'DHL_Account_Number__c', '123456789', false);
        insertValue(instanceRecord, 'DHL_Default_Product_Code__c', 'P', false);

        DHLAuthService.DHLCredentialConfig config = DHLAuthService.getCredentialConfig();

        System.assertEquals('site-id', config.apiKey);
        System.assertEquals('password', config.apiSecret);
        System.assertEquals('123456789', config.accountNumber);
        System.assertEquals('P', config.defaultProductCode);
        System.assertEquals('Sandbox', config.environment);
        System.assertEquals('https://express.api.dhl.com/mydhlapi/test', DHLAuthService.getBaseUrl('Sandbox'));
        System.assertEquals('https://express.api.dhl.com/mydhlapi', DHLAuthService.getBaseUrl('Production'));
        System.assertEquals(
            'Basic ' + EncodingUtil.base64Encode(Blob.valueOf('site-id:password')),
            DHLAuthService.getBasicAuthHeader(config)
        );
    }

    private static Connector_Instance__c createDhlInstance(Boolean active) {
        Connector_Instance__c instanceRecord = new Connector_Instance__c(
            Name = 'DHL',
            Connector_Key__c = 'dhl',
            Connector_Label__c = 'DHL',
            Active__c = active,
            Environment__c = 'Sandbox',
            Entitlement_Status__c = active ? 'Active' : 'Inactive',
            Expiry_Date__c = Date.today().addDays(30),
            Health_Status__c = 'Unknown'
        );
        insert instanceRecord;
        return instanceRecord;
    }

    private static void insertValue(Connector_Instance__c instanceRecord, String fieldKey, String value, Boolean isSecretReference) {
        insert new Connector_Config_Value__c(
            Name = 'dhl:' + fieldKey,
            Connector_Instance__c = instanceRecord.Id,
            Connector_Key__c = 'dhl',
            Field_Key__c = fieldKey,
            Value__c = value,
            Is_Secret_Reference__c = isSecretReference
        );
    }
}
