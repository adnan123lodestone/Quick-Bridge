@isTest
private class QBObjectMappingsTest {

    @testSetup
    static void setupData() {
        QBTriggerHandler.isAccountProcessing = true;
        try {
            Account acc = new Account(Name = 'QB Mapping Account');
            insert acc;
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
        }

        Sync_Settings__c settings = Sync_Settings__c.getOrgDefaults();
        if (settings == null) {
            settings = new Sync_Settings__c();
        }
        settings.Is_Paused__c = false;
        upsert settings;
    }

    @isTest
    static void testFallbackMappingsAreReturned() {
        Map<String, String> accountMap = QBObjectMappings.getAccountToCustomerMapping();
        System.assert(!accountMap.isEmpty());

        Map<String, String> reverseMap = QBObjectMappings.getCustomerToAccountMapping();
        System.assert(!reverseMap.isEmpty());

        Map<String, String> vendorReverseMap = QBObjectMappings.getVendorToAccountMapping();
        System.assert(!vendorReverseMap.isEmpty());

        Map<String, String> productMap = QBObjectMappings.getProductToItemMapping();
        System.assert(!productMap.isEmpty());

        Map<String, String> itemReverseMap = QBObjectMappings.getItemToProductMapping();
        System.assert(!itemReverseMap.isEmpty());

        Map<String, String> invoiceMap = QBObjectMappings.getInvoiceMapping();
        System.assert(!invoiceMap.isEmpty());

        Map<String, String> creditMemoMap = QBObjectMappings.getCreditMemoMapping();
        System.assert(!creditMemoMap.isEmpty());

        Map<String, String> purchaseOrderMap = QBObjectMappings.getPurchaseOrderMapping();
        System.assert(!purchaseOrderMap.isEmpty());

        Map<String, String> orderMap = QBObjectMappings.getOrderToInvoiceMapping();
        System.assert(!orderMap.isEmpty());

        Map<String, String> invoiceReverseMap = QBObjectMappings.getInvoiceToOrderMapping();
        System.assert(!invoiceReverseMap.isEmpty());
        System.assertEquals(orderMap.size(), invoiceReverseMap.size());
    }

    @isTest
    static void customerNotesMappingRespectsConfiguredDirection() {
        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>();
        System.assertEquals(
            false,
            QBObjectMappings.getAccountToCustomerMapping().containsKey('Description')
        );
        System.assertEquals(
            false,
            QBObjectMappings.getCustomerToAccountMapping().containsKey('Notes')
        );

        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('Description', 'Notes', 'QBO to SF')
        };

        Map<String, String> inboundOnly = QBObjectMappings.getCustomerToAccountMapping();
        Map<String, String> outboundWhileInboundOnly = QBObjectMappings.getAccountToCustomerMapping();
        System.assertEquals('Description', inboundOnly.get('Notes'));
        System.assertEquals(false, outboundWhileInboundOnly.containsKey('Description'));

        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('Description', 'Notes', 'SF to QBO')
        };
        Map<String, String> outboundOnly = QBObjectMappings.getAccountToCustomerMapping();
        Map<String, String> inboundWhileOutboundOnly = QBObjectMappings.getCustomerToAccountMapping();
        System.assertEquals('Notes', outboundOnly.get('Description'));
        System.assertEquals(false, inboundWhileOutboundOnly.containsKey('Notes'));

        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('Description', 'Notes', 'Two-Way')
        };
        System.assertEquals(
            'Notes',
            QBObjectMappings.getAccountToCustomerMapping().get('Description')
        );
        System.assertEquals(
            'Description',
            QBObjectMappings.getCustomerToAccountMapping().get('Notes')
        );
    }

    @isTest
    static void customerMappingPrefersCanonicalFieldWhenSalesforceFieldIsDuplicated() {
        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('Name', 'CompanyName', 'QBO to SF'),
            customerMapping('Name', 'DisplayName', 'QBO to SF'),
            customerMapping('Name', 'FullyQualifiedName', 'QBO to SF')
        };

        Map<String, String> inbound = QBObjectMappings.getCustomerToAccountMapping();
        System.assertEquals('Name', inbound.get('DisplayName'));
        System.assertEquals(false, inbound.containsKey('CompanyName'));
        System.assertEquals(false, inbound.containsKey('FullyQualifiedName'));
    }

    private static Field_Mapping__mdt customerMapping(
        String sfField,
        String externalField,
        String direction
    ) {
        return new Field_Mapping__mdt(
            Integration__c = 'qbonline',
            SF_Object__c = 'Account',
            SF_Field__c = sfField,
            External_Field__c = externalField,
            Sync_Direction__c = direction,
            Target_Object_API_Name__c = 'Customer',
            Is_Active__c = true
        );
    }

    @isTest
    static void testQuoteAndOrderSummaryMappings() {
        Map<String, String> quoteMap = QBObjectMappings.getQuoteMapping();
        System.assert(!quoteMap.isEmpty());

        Map<String, String> quoteLineMap = QBObjectMappings.getQuoteLineItemMapping();
        System.assert(!quoteLineMap.isEmpty());

        Map<String, String> orderSummaryMap = QBObjectMappings.getOrderSummaryToInvoiceMapping();
        System.assert(!orderSummaryMap.isEmpty());

        Map<String, String> orderItemSummaryMap = QBObjectMappings.getOrderItemSummaryMapping();
        System.assert(!orderItemSummaryMap.isEmpty());

        Map<String, String> invToOrderSummaryMap = QBObjectMappings.getInvoiceToOrderSummaryMapping();
        System.assert(!invToOrderSummaryMap.isEmpty());
    }

    @isTest
    static void testInvoiceSourceAndSmartMappingFallbacks() {
        String sourceObject = QBObjectMappings.getInvoiceSourceObject();
        System.assert(String.isNotBlank(sourceObject));

        Map<String, String> smartMap = QBObjectMappings.getSmartInvoiceMapping();
        System.assert(!smartMap.isEmpty());
    }

    @isTest
    static void testInvoiceLineItemObjectResolution() {
        String lineFromOrder = QBObjectMappings.getInvoiceLineItemObject('Order');
        String lineFromInvoice = QBObjectMappings.getInvoiceLineItemObject('Invoice__c');
        System.assert(String.isNotBlank(lineFromOrder));
        System.assert(String.isNotBlank(lineFromInvoice));
    }

    @isTest
    static void testAccountToVendorMapping() {
        Map<String, String> vendorMap = QBObjectMappings.getAccountToVendorMapping();
        System.assert(!vendorMap.isEmpty());
    }

    @isTest
    static void testTaxCodeMapping() {
        Map<String, String> taxCodeMap = QBObjectMappings.getTaxCodeMapping();
        System.assert(!taxCodeMap.isEmpty());
    }

    @isTest
    static void testTaxCodeInboundMapping() {
        Map<String, String> inboundMap = QBObjectMappings.getTaxCodeInboundMapping();
        System.assert(!inboundMap.isEmpty());
    }

    @isTest
    static void testOrderItemMapping() {
        Map<String, String> orderItemMap = QBObjectMappings.getOrderItemMapping();
        System.assert(!orderItemMap.isEmpty());
    }

    @isTest
    static void testCreditMemoLineMapping() {
        Map<String, String> cmLineMap = QBObjectMappings.getCreditMemoLineMapping();
        System.assert(!cmLineMap.isEmpty());
    }

    @isTest
    static void testPurchaseOrderLineMapping() {
        Map<String, String> poLineMap = QBObjectMappings.getPurchaseOrderLineMapping();
        System.assert(!poLineMap.isEmpty());
    }

    @isTest
    static void testQBOToPurchaseOrderLineMapping() {
        Map<String, String> inboundPoLineMap = QBObjectMappings.getQBOToPurchaseOrderLineMapping();
        System.assert(!inboundPoLineMap.isEmpty());
    }

    @isTest
    static void testReverseMappingUtility() {
        Map<String, String> original = new Map<String, String>{'A' => '1', 'B' => '2'};
        Map<String, String> reversed = QBObjectMappings.reverseMapping(original);
        System.assertEquals(2, reversed.size());
        System.assertEquals('A', reversed.get('1'));
        System.assertEquals('B', reversed.get('2'));
        
        Map<String, String> emptyReversed = QBObjectMappings.reverseMapping(null);
        System.assertEquals(0, emptyReversed.size());
    }
}