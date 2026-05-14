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
        System.assert(!accountMap.isEmpty(), 'Account mapping fallback should not be empty.');
        System.assertEquals('DisplayName', accountMap.get('Name'));

        Map<String, String> reverseMap = QBObjectMappings.getCustomerToAccountMapping();
        System.assert(!reverseMap.isEmpty(), 'Reverse mapping fallback should not be empty.');
        System.assertEquals('Name', reverseMap.get('DisplayName'));

        Map<String, String> vendorReverseMap = QBObjectMappings.getVendorToAccountMapping();
        System.assert(!vendorReverseMap.isEmpty(), 'Vendor reverse mapping should reuse account inbound mapping.');
        System.assertEquals('Name', vendorReverseMap.get('DisplayName'));

        Map<String, String> productMap = QBObjectMappings.getProductToItemMapping();
        System.assert(!productMap.isEmpty(), 'Product mapping fallback should not be empty.');
        System.assertEquals('Name', productMap.get('Name'));

        Map<String, String> itemReverseMap = QBObjectMappings.getItemToProductMapping();
        System.assert(!itemReverseMap.isEmpty(), 'Item reverse mapping should not be empty.');
        System.assert(itemReverseMap.containsKey('Name'));
        System.assert(itemReverseMap.containsKey('Sku'));

        Map<String, String> invoiceMap = QBObjectMappings.getInvoiceMapping();
        System.assert(!invoiceMap.isEmpty(), 'Invoice mapping fallback should not be empty.');

        Map<String, String> creditMemoMap = QBObjectMappings.getCreditMemoMapping();
        System.assert(!creditMemoMap.isEmpty(), 'Credit memo mapping fallback should not be empty.');

        Map<String, String> purchaseOrderMap = QBObjectMappings.getPurchaseOrderMapping();
        System.assert(!purchaseOrderMap.isEmpty(), 'PO mapping fallback should not be empty.');

        Map<String, String> orderMap = QBObjectMappings.getOrderToInvoiceMapping();
        System.assert(!orderMap.isEmpty(), 'Order mapping fallback should not be empty.');

        Map<String, String> invoiceReverseMap = QBObjectMappings.getInvoiceToOrderMapping();
        System.assert(!invoiceReverseMap.isEmpty(), 'Invoice reverse mapping should not be empty.');
        System.assertEquals(orderMap.size(), invoiceReverseMap.size());
    }

    @isTest
    static void testInvoiceSourceAndSmartMappingFallbacks() {
        String sourceObject = QBObjectMappings.getInvoiceSourceObject();
        System.assertEquals('Order', sourceObject, 'Default source object should be Order in tests.');

        Map<String, String> smartMap = QBObjectMappings.getSmartInvoiceMapping();
        System.assert(!smartMap.isEmpty(), 'Smart invoice mapping should resolve to a non-empty fallback mapping.');
        System.assertEquals('TxnDate', smartMap.get('EffectiveDate'));
    }

    @isTest
    static void testInvoiceLineItemObjectResolution() {
        System.assertEquals('OrderItem', QBObjectMappings.getInvoiceLineItemObject('Order'));
        System.assertEquals('Invoice_Line__c', QBObjectMappings.getInvoiceLineItemObject('Invoice__c'));
    }
}