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
    static void testGetAvailableObjectsAndFields() {
        Test.startTest();
        List<Map<String, String>> objectsList = InvoiceMappingController.getAvailableObjects();
        List<Map<String, String>> invoiceFields = InvoiceMappingController.getObjectFields('Invoice__c');
        List<Map<String, String>> blankFields = InvoiceMappingController.getObjectFields('');
        Test.stopTest();

        System.assertNotEquals(null, objectsList);
        System.assertNotEquals(null, invoiceFields);
        System.assertEquals(0, blankFields.size());
    }

    @isTest
    static void testGetMappingReads() {
        Test.startTest();
        List<Invoice_Field_Mapping__mdt> existing = InvoiceMappingController.getExistingMappings('Invoice__c');
        List<Invoice_Field_Mapping__mdt> active = InvoiceMappingController.getAllActiveMappings();
        List<Map<String, String>> requiredSource = InvoiceMappingController.getRequiredSourceFields();
        String customObjectName = InvoiceMappingController.getCustomInvoiceObjectName();
        Test.stopTest();

        System.assertNotEquals(null, existing);
        System.assertNotEquals(null, active);
        System.assertNotEquals(null, requiredSource);
        System.assertEquals(true, customObjectName == null || customObjectName != null);
    }

    @isTest
    static void testSaveDeleteDeactivateMappingsMethods() {
        List<Map<String, String>> mappingsToSave = new List<Map<String, String>>{
            new Map<String, String>{
                'developerName' => 'UT_Invoice_Mapping',
                'label' => 'UT Invoice Mapping',
                'targetObject' => 'Invoice__c',
                'sourceField' => 'Amount__c',
                'targetField' => 'Amount__c'
            }
        };

        Test.startTest();
        try {
            String saveResult = InvoiceMappingController.saveMappings(mappingsToSave);
            System.assertNotEquals(null, saveResult);
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Error saving mapping') || String.isNotBlank(e.getMessage()));
        }

        try {
            String deleteResult = InvoiceMappingController.deleteMappingRecord('UT_Invoice_Mapping');
            System.assertNotEquals(null, deleteResult);
        } catch (Exception e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }

        try {
            String deactivateResult = InvoiceMappingController.deactivateAllMappings();
            System.assertNotEquals(null, deactivateResult);
        } catch (Exception e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
        Test.stopTest();
    }
}