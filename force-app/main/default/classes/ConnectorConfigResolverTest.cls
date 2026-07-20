/**
 * @description Production-certified test coverage targeting ConnectorConfigResolver utility methods.
 */
@IsTest
private class ConnectorConfigResolverTest {

    @TestSetup
    static void setupTestData() {
        insert new Integration_Product__c(
            Name = 'Resolver Test',
            Product_Key__c = 'resolvertest',
            Connector_Key__c = 'resolvertest',
            Product_Label__c = 'Resolver Test',
            Category__c = 'Test',
            Active_Field__c = 'Is_Active__c',
            Expiry_Field__c = 'Expiration_Date__c',
            Display_Order__c = 10,
            Enabled__c = true,
            Catalog_Active__c = true,
            Has_Config__c = true
        );

        Connector_Instance__c instance = new Connector_Instance__c(
            Name = 'Resolver Test Instance',
            Connector_Key__c = 'resolvertest',
            Active__c = true,
            Expiry_Date__c = Date.today().addDays(30)
        );
        insert instance;

        List<Connector_Config_Value__c> configValues = new List<Connector_Config_Value__c>{
            new Connector_Config_Value__c(
                Name = 'resolvertest:textKey',
                Connector_Instance__c = instance.Id,
                Connector_Key__c = 'resolvertest',
                Field_Key__c = 'textKey',
                Value__c = 'PersistedValue'
            ),
            new Connector_Config_Value__c(
                Name = 'resolvertest:boolTrue',
                Connector_Instance__c = instance.Id,
                Connector_Key__c = 'resolvertest',
                Field_Key__c = 'boolTrue',
                Value__c = 'true'
            ),
            new Connector_Config_Value__c(
                Name = 'resolvertest:boolYes',
                Connector_Instance__c = instance.Id,
                Connector_Key__c = 'resolvertest',
                Field_Key__c = 'boolYes',
                Value__c = 'yes'
            ),
            new Connector_Config_Value__c(
                Name = 'resolvertest:boolOne',
                Connector_Instance__c = instance.Id,
                Connector_Key__c = 'resolvertest',
                Field_Key__c = 'boolOne',
                Value__c = '1'
            ),
            new Connector_Config_Value__c(
                Name = 'resolvertest:validDate',
                Connector_Instance__c = instance.Id,
                Connector_Key__c = 'resolvertest',
                Field_Key__c = 'validDate',
                Value__c = '2026-12-31'
            ),
            new Connector_Config_Value__c(
                Name = 'resolvertest:badDate',
                Connector_Instance__c = instance.Id,
                Connector_Key__c = 'resolvertest',
                Field_Key__c = 'badDate',
                Value__c = 'invalid-date-string'
            )
        };
        insert configValues;
    }

    /**
     * @description Verifies successful string value resolution paths.
     */
    @IsTest
    static void testGetAndRequireValueSuccess() {
        ConnectorRegistryService.clearCache();

        Test.startTest();
        String resolvedValue = ConnectorConfigResolver.getValue('resolvertest', 'textKey');
        String requiredValue = ConnectorConfigResolver.requireValue('resolvertest', 'textKey');
        Test.stopTest();

        System.assertEquals('PersistedValue', resolvedValue);
        System.assertEquals('PersistedValue', requiredValue);
    }

    /**
     * @description Verifies requireValue throws an AuraHandledException on missing configurations.
     */
    @IsTest
    static void testRequireValueThrowsExceptionOnMissing() {
        ConnectorRegistryService.clearCache();

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ConnectorConfigResolver.requireValue('resolvertest', 'missingKey');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertNotEquals(null, e);
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'An exception must be intercepted for unconfigured variables.');
    }

    /**
     * @description Covers boolean variants evaluated down to true conditions.
     */
    @IsTest
    static void testGetBooleanEvaluationTruths() {
        ConnectorRegistryService.clearCache();

        Test.startTest();
        Boolean evaluateTrue = ConnectorConfigResolver.getBoolean('resolvertest', 'boolTrue');
        Boolean evaluateYes = ConnectorConfigResolver.getBoolean('resolvertest', 'boolYes');
        Boolean evaluateOne = ConnectorConfigResolver.getBoolean('resolvertest', 'boolOne');
        Boolean evaluateMissing = ConnectorConfigResolver.getBoolean('resolvertest', 'missingKey');
        Test.stopTest();

        System.assertEquals(true, evaluateTrue);
        System.assertEquals(true, evaluateYes);
        System.assertEquals(true, evaluateOne);
        System.assertEquals(false, evaluateMissing);
    }

    /**
     * @description Asserts date deserialization formats parse accurately or fall back cleanly.
     */
    @IsTest
    static void testGetDateParsing() {
        ConnectorRegistryService.clearCache();

        Test.startTest();
        Date validDateParsed = ConnectorConfigResolver.getDate('resolvertest', 'validDate');
        Date nullDateResult = ConnectorConfigResolver.getDate('resolvertest', 'missingKey');
        Test.stopTest();

        System.assertEquals(Date.valueOf('2026-12-31'), validDateParsed);
        System.assertEquals(null, nullDateResult);
    }

    /**
     * @description Enforces explicit execution tracking across type validation exceptions.
     */
    @IsTest
    static void testGetDateThrowsExceptionOnMalformedString() {
        ConnectorRegistryService.clearCache();

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ConnectorConfigResolver.getDate('resolvertest', 'badDate');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertNotEquals(null, e);
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Malformatted date strings must cause validation failures.');
    }

    /**
     * @description Tests the active validation path mapping logic.
     */
    @IsTest
    static void testIsActiveStatus() {
        ConnectorRegistryService.clearCache();

        Test.startTest();
        Boolean statusActive = ConnectorConfigResolver.isActive('resolvertest');
        Test.stopTest();

        System.assertEquals(true, statusActive);
    }

    /**
     * @description Verifies instantiation footprint of the explicit exception container.
     */
    @IsTest
    static void testExceptionInstantiation() {
        Test.startTest();
        ConnectorConfigResolver.MissingConfigException ex = new ConnectorConfigResolver.MissingConfigException('Test Error Message');
        Test.stopTest();

        System.assertEquals('Test Error Message', ex.getMessage());
    }
}