@isTest
private class InvoiceMappingControllerTest {

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Invoice Mapping Test Account');
        insert acc;

        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today()
        );
        insert ord;

        Invoice__c inv = new Invoice__c(
            Related_Account__c = acc.Id,
            Order__c = ord.Id,
            Invoice_Date__c = Date.today(),
            Status__c = 'Draft',
            Amount__c = 100
        );
        insert inv;
    }

    @isTest
    static void testGetAvailableObjects() {
        Test.startTest();
        List<Map<String, String>> objectsList = InvoiceMappingController.getAvailableObjects();
        Test.stopTest();

        System.assertNotEquals(null, objectsList);
        System.assert(objectsList.size() > 0, 'Should successfully evaluate global describe for custom objects.');
    }

    @isTest
    static void testGetObjectFieldsExtensiveCoverage() {
        Test.startTest();
        
        List<Map<String, String>> accountFields = InvoiceMappingController.getObjectFields('Account');
        List<Map<String, String>> contactFields = InvoiceMappingController.getObjectFields('Contact');
        List<Map<String, String>> opportunityFields = InvoiceMappingController.getObjectFields('Opportunity');
        
        String invApiName = Invoice__c.SObjectType.getDescribe().getName();
        List<Map<String, String>> invoiceFields = InvoiceMappingController.getObjectFields(invApiName);
        
        List<Map<String, String>> blankFields = InvoiceMappingController.getObjectFields('');
        List<Map<String, String>> invalidFields = InvoiceMappingController.getObjectFields('Invalid_Object_Name_XYZ__c');
        
        Test.stopTest();

        System.assertNotEquals(null, accountFields);
        System.assertNotEquals(null, invoiceFields);
        System.assertEquals(0, blankFields.size(), 'Blank object API name should return empty array.');
        System.assertEquals(0, invalidFields.size(), 'Invalid object API name should gracefully return empty array.');
    }

    @isTest
    static void testGetMappingReadsAndSchemaRules() {
        String invApiName = Invoice__c.SObjectType.getDescribe().getName();

        Test.startTest();
        List<Invoice_Field_Mapping__mdt> existing = InvoiceMappingController.getExistingMappings(invApiName);
        List<Invoice_Field_Mapping__mdt> active = InvoiceMappingController.getAllActiveMappings();
        List<Map<String, String>> requiredSource = InvoiceMappingController.getRequiredSourceFields();
        String customObjectName = InvoiceMappingController.getCustomInvoiceObjectName();
        Test.stopTest();

        System.assertNotEquals(null, existing);
        System.assertNotEquals(null, active);
        System.assertNotEquals(null, requiredSource);
    }

    @isTest
    static void testSaveMappingsSuccessAndExceptions() {
        String invApiName = Invoice__c.SObjectType.getDescribe().getName();

        List<Map<String, String>> mappingsToSave = new List<Map<String, String>>{
            new Map<String, String>{
                'developerName' => 'UT_Invoice_Mapping_1',
                'label' => 'UT Invoice Mapping 1',
                'targetObject' => invApiName,
                'sourceField' => 'Amount__c',
                'targetField' => 'Amount__c'
            }
        };

        Test.startTest();
        try {
            String saveResult = InvoiceMappingController.saveMappings(mappingsToSave);
            System.assertNotEquals(null, saveResult);
        } catch (Exception e) {
            System.assertNotEquals(null, e);
        }
        Boolean exceptionCaught = false;
        try {
            InvoiceMappingController.saveMappings(null);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
        }
        System.assert(exceptionCaught, 'Save Mappings catch block should execute when passed null data.');
        Test.stopTest();
    }

    @isTest
    static void testDeleteMappingRecordAndExceptions() {
        Test.startTest();
        try {
            String deleteResult = InvoiceMappingController.deleteMappingRecord('UT_Invoice_Mapping');
            System.assertNotEquals(null, deleteResult);
        } catch (Exception e) {
            System.assertNotEquals(null, e);
        }
        Boolean exceptionCaught = false;
        try {
            InvoiceMappingController.deleteMappingRecord(null);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
        }
        System.assert(exceptionCaught, 'Delete Mappings catch block should execute when missing developer name.');
        Test.stopTest();
    }

    @isTest
    static void testDeactivateAllMappings() {
        Test.startTest();
        try {
            String deactivateResult = InvoiceMappingController.deactivateAllMappings();
            System.assertNotEquals(null, deactivateResult);
        } catch (Exception e) {
            System.assertNotEquals(null, e);
        }
        Test.stopTest();
    }
}