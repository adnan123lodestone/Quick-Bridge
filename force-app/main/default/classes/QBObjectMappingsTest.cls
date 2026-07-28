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
        System.assertEquals('DisplayName', accountMap.get('Name'));

        Map<String, String> reverseMap = QBObjectMappings.getCustomerToAccountMapping();
        System.assert(!reverseMap.isEmpty());
        System.assertEquals('Name', reverseMap.get('DisplayName'));

        Map<String, String> vendorReverseMap = QBObjectMappings.getVendorToAccountMapping();
        System.assert(!vendorReverseMap.isEmpty());
        System.assertEquals('Name', vendorReverseMap.get('DisplayName'));

        Map<String, String> productMap = QBObjectMappings.getProductToItemMapping();
        System.assert(!productMap.isEmpty());
        System.assertEquals('Name', productMap.get('Name'));

        Map<String, String> itemReverseMap = QBObjectMappings.getItemToProductMapping();
        System.assert(!itemReverseMap.isEmpty());
        System.assert(itemReverseMap.containsKey('Name'));
        System.assert(itemReverseMap.containsKey('Sku'));

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
    static void testInvoiceSourceAndSmartMappingFallbacks() {
        String sourceObject = QBObjectMappings.getInvoiceSourceObject();
        System.assert(String.isNotBlank(sourceObject));

        Map<String, String> smartMap = QBObjectMappings.getSmartInvoiceMapping();
        if (smartMap.isEmpty()) {
            Map<String, String> orderMap = QBObjectMappings.getOrderToInvoiceMapping();
            System.assert(!orderMap.isEmpty());
            Map<String, String> invoiceMap = QBObjectMappings.getInvoiceMapping();
            System.assert(!invoiceMap.isEmpty());
        } else {
            if (sourceObject == 'Order') {
                System.assertEquals('TxnDate', smartMap.get('EffectiveDate'));
            }
        }
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
        System.assertEquals('DisplayName', vendorMap.get('Name'));
        System.assertEquals('AcctNum', vendorMap.get('AccountNumber'));
    }

    @isTest
    static void testTaxCodeMapping() {
        Map<String, String> taxCodeMap = QBObjectMappings.getTaxCodeMapping();
        System.assert(!taxCodeMap.isEmpty());
        System.assertEquals('TaxCode', taxCodeMap.get('Name'));
        System.assertEquals('RateValue', taxCodeMap.get('QuickBridgeTLG__Tax_Rate_Per__c'));
    }

    @isTest
    static void testTaxCodeInboundMapping() {
        Map<String, String> inboundMap = QBObjectMappings.getTaxCodeInboundMapping();
        System.assert(!inboundMap.isEmpty());
        System.assertEquals('Name', inboundMap.get('TaxCode'));
        System.assertEquals('QuickBridgeTLG__Tax_Rate_Per__c', inboundMap.get('RateValue'));
    }

    @isTest
    static void testOrderItemMapping() {
        Map<String, String> orderItemMap = QBObjectMappings.getOrderItemMapping();
        System.assert(!orderItemMap.isEmpty());
        System.assertEquals('Qty', orderItemMap.get('Quantity'));
        System.assertEquals('UnitPrice', orderItemMap.get('UnitPrice'));
        System.assertEquals('Description', orderItemMap.get('Description'));
    }

    @isTest
    static void testCreditMemoLineMapping() {
        Map<String, String> cmLineMap = QBObjectMappings.getCreditMemoLineMapping();
        System.assert(!cmLineMap.isEmpty());
        System.assertEquals('Line.SalesItemLineDetail.Qty', cmLineMap.get('Quantity__c'));
        System.assertEquals('Line.SalesItemLineDetail.UnitPrice', cmLineMap.get('Rate__c'));
        System.assertEquals('Line.Description', cmLineMap.get('Description__c'));
    }

    @isTest
    static void testPurchaseOrderLineMapping() {
        Map<String, String> poLineMap = QBObjectMappings.getPurchaseOrderLineMapping();
        System.assert(!poLineMap.isEmpty());
        System.assertEquals('Line.ItemBasedExpenseLineDetail.Qty', poLineMap.get('Quantity__c'));
        System.assertEquals('Line.ItemBasedExpenseLineDetail.UnitPrice', poLineMap.get('Cost_Price__c'));
        System.assertEquals('Line.Description', poLineMap.get('Product_Description__c'));
    }

    @isTest
    static void testQBOToPurchaseOrderLineMapping() {
        Map<String, String> inboundPoLineMap = QBObjectMappings.getQBOToPurchaseOrderLineMapping();
        System.assert(!inboundPoLineMap.isEmpty());
        System.assertEquals('Quantity__c', inboundPoLineMap.get('Line.ItemBasedExpenseLineDetail.Qty'));
        System.assertEquals('Cost_Price__c', inboundPoLineMap.get('Line.ItemBasedExpenseLineDetail.UnitPrice'));
        System.assertEquals('Product_Description__c', inboundPoLineMap.get('Line.Description'));
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