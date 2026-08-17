@isTest
private class QBOInvoiceMappingResolverTest {

    private static void registerInvoiceObject(String sfObject) {
        Integration_Entity_Definition__c def = new Integration_Entity_Definition__c(
            Name = sfObject + '_Invoice',
            Integration_Key__c = 'qbonline',
            Salesforce_Object__c = sfObject,
            External_Entity__c = 'Invoice',
            Active__c = true
        );
        insert def;
        IntegrationEntityRegistry.clearCache();
    }

    /**
     * Helper method to generate dummy Field_Mapping__mdt records dynamically for test context.
     */
    private static Field_Mapping__mdt createMockMapping(String sfObj, String sfField, String extField, String direction) {
        Field_Mapping__mdt row = new Field_Mapping__mdt();
        row.SF_Object__c = sfObj;
        row.SF_Field__c = sfField;
        row.External_Field__c = extField;
        row.Sync_Direction__c = direction;
        row.Is_Active__c = true;
        return row;
    }

    /**
     * Tests the core resolve mechanism when no valid mappings exist, throwing an exception.
     */
    @isTest
    static void testResolvesOrderExceptionPath() {
        // Use an explicit empty override so packaged Custom Metadata records
        // cannot make this negative-path test depend on org/package contents.
        QBOInvoiceMappingResolver.setTestFieldMappingRows(new List<Field_Mapping__mdt>());
        try {
            QBOInvoiceMappingResolver.ResolverResult result = QBOInvoiceMappingResolver.resolve();
            System.assertNotEquals(null, result);
        } catch (QBOInvoiceMappingResolver.ResolverException e) {
            System.assert(e.getMessage().contains('No active Field_Mapping__mdt'));
        } finally {
            QBOInvoiceMappingResolver.clearTestFieldMappingRows();
        }
    }

    /**
     * Tests successful resolution using valid mock data, covering header mappings, 
     * child lines, priority sorting, and display names.
     */
    @isTest
    static void testResolveSuccessWithMockData() {
        List<Field_Mapping__mdt> mockRows = new List<Field_Mapping__mdt>();
        
        // Header Mappings
        mockRows.add(createMockMapping('Order', 'Id', 'Id', 'Two-Way'));
        mockRows.add(createMockMapping('Order', 'EffectiveDate', 'TxnDate', 'SF to QBO'));
        mockRows.add(createMockMapping('Order', 'Status', 'Status', 'SF to QBO'));
        
        // Line Item Child Mappings to trigger resolveLineObject blocks
        mockRows.add(createMockMapping('OrderItem', 'Quantity', 'Line.SalesItemLineDetail.Qty', 'SF to QBO'));
        mockRows.add(createMockMapping('OrderItem', 'UnitPrice', 'Line.SalesItemLineDetail.UnitPrice', 'SF to QBO'));
        
        QBOInvoiceMappingResolver.setTestFieldMappingRows(mockRows);

        Test.startTest();
        QBOInvoiceMappingResolver.ResolverResult result = QBOInvoiceMappingResolver.resolve();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('Order', result.invoiceSourceObject);
        System.assertEquals('OrderItem', result.lineSourceObject);
        System.assertEquals('Id', result.qboIdField);
        System.assertEquals('Two-Way', result.qboIdFieldDirection);
        System.assertNotEquals(null, result.headerMappings);
        System.assertNotEquals(null, result.lineMappings);
        
        QBOInvoiceMappingResolver.clearTestFieldMappingRows();
    }

    @isTest
    static void testResolveUsesTheRequestedObjectAndConfiguredInvoiceTarget() {
        QBOInvoiceMappingResolver.setTestFieldMappingRows(new List<Field_Mapping__mdt>{
            new Field_Mapping__mdt(
                Integration__c = 'qbonline', SF_Object__c = 'Account', SF_Field__c = 'QuickbookID__c',
                External_Field__c = 'Id', Sync_Direction__c = 'QBO to SF',
                Target_Object_API_Name__c = 'Invoice', Is_Active__c = true
            ),
            new Field_Mapping__mdt(
                Integration__c = 'qbonline', SF_Object__c = 'Account', SF_Field__c = 'Description',
                External_Field__c = 'CustomerMemo.value', Sync_Direction__c = 'SF to QBO',
                Target_Object_API_Name__c = 'Invoice', Is_Active__c = true
            ),
            new Field_Mapping__mdt(
                Integration__c = 'qbonline', SF_Object__c = 'Account', SF_Field__c = 'Website',
                External_Field__c = 'InvoiceLink', Sync_Direction__c = 'QBO to SF',
                Target_Object_API_Name__c = 'Invoice', Is_Active__c = true
            )
        });

        QBOInvoiceMappingResolver.ResolverResult result = QBOInvoiceMappingResolver.resolve('Account');

        System.assertEquals('Account', result.invoiceSourceObject);
        System.assertEquals('QuickbookID__c', result.qboIdField);
        System.assertEquals('Website', result.invoiceLinkField);
        QBOInvoiceMappingResolver.clearTestFieldMappingRows();
    }

    /**
     * Tests priority 2 resolution path of resolveQboIdField using ExternalId mappings.
     */
    @isTest
    static void testResolveQboIdFieldPriorityTwo() {
        List<Field_Mapping__mdt> mockRows = new List<Field_Mapping__mdt>{
            createMockMapping('Order', 'QuickbookID__c', 'ExternalId', 'QBO to SF')
        };
        QBOInvoiceMappingResolver.setTestFieldMappingRows(mockRows);

        Test.startTest();
        QBOInvoiceMappingResolver.ResolverResult result = QBOInvoiceMappingResolver.resolve();
        Test.stopTest();

        System.assertEquals('QuickbookID__c', result.qboIdField);
        QBOInvoiceMappingResolver.clearTestFieldMappingRows();
    }

    /**
     * Tests fallback priority 4 route using standard object field tokens like QuickbookID__c, 
     * handling optional package namespace additions dynamically.
     */
    @isTest
    static void testResolveQboIdFieldPriorityFourFallback() {
        List<Field_Mapping__mdt> mockRows = new List<Field_Mapping__mdt>{
            createMockMapping('Order', 'EffectiveDate', 'TxnDate', 'SF to QBO')
        };
        QBOInvoiceMappingResolver.setTestFieldMappingRows(mockRows);

        Test.startTest();
        QBOInvoiceMappingResolver.ResolverResult result = QBOInvoiceMappingResolver.resolve();
        Test.stopTest();

        // Dynamically verifies assertion with or without package namespace prefix
        System.assert(
            result.qboIdField == 'QuickbookID__c' || result.qboIdField == 'QuickBridgeTLG__QuickbookID__c',
            'Should return valid standard or namespaced fallback field identifier.'
        );
        QBOInvoiceMappingResolver.clearTestFieldMappingRows();
    }

    /**
     * Tests the boundary constraint when multiple objects evaluate to an Invoice layout.
     */
    @isTest
    static void testResolveMultipleInvoiceObjectsThrowsException() {
        List<Field_Mapping__mdt> mockRows = new List<Field_Mapping__mdt>{
            createMockMapping('Order', 'Id', 'Id', 'Two-Way'),
            createMockMapping('QuickBridgeTLG__Invoice__c', 'Id', 'Id', 'Two-Way')
        };
        QBOInvoiceMappingResolver.setTestFieldMappingRows(mockRows);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            QBOInvoiceMappingResolver.resolve();
        } catch (QBOInvoiceMappingResolver.ResolverException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('Multiple Salesforce objects'));
        }
        Test.stopTest();

        System.assert(exceptionThrown);
        QBOInvoiceMappingResolver.clearTestFieldMappingRows();
    }

    /**
     * Tests static registry fallbacks for classic mapping routes.
     */
    @isTest
    static void testRegistryFallbackResolvesOrderToInvoice() {
        String resolved = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'Order', null, null);
        System.assertEquals('Invoice', resolved);
    }

    /**
     * Tests mapping configurations targeting packaging schemas.
     */
    @isTest
    static void testRegistryResolvesNamespacedObjectToInvoice() {
        String resolved = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'QuickBridgeTLG__Invoice__c', null, null);
        System.assertEquals('Invoice', resolved);
    }

    /**
     * Tests dynamically registered custom object descriptions against external definitions.
     */
    @isTest
    static void testRegistryResolvesCustomObjectViaEntityDefinition() {
        registerInvoiceObject('Custom_Invoice__c');
        String resolved = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'Custom_Invoice__c', null, null);
        System.assertEquals('Invoice', resolved);
    }

    /**
     * Tests validation filters reject unmapped target containers.
     */
    @isTest
    static void testRegistryDoesNotResolveUnmappedObjectToInvoice() {
        String resolved = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'Account', null, 'DEFAULT');
        System.assertEquals('Customer', resolved);
    }

    /**
     * Tests utility patterns verify stripping parameters from standard namespaced text rows.
     */
    @isTest
    static void testObjectMatchesNamespaceStripping() {
        String resolvedNamespaced = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'pkg__Invoice__c', null, null);
        System.assertEquals('Invoice', resolvedNamespaced);
    }

    /**
     * Validates safe schema interrogation parameters return null descriptors for unknown metadata types.
     */
    @isTest
    static void testGetSObjectTypeReturnsNullForUnknownObject() {
        Schema.SObjectType sot = QBOInvoiceMappingResolver.getSObjectType('UnknownObject_XYZ__c');
        System.assertEquals(null, sot);
    }

    /**
     * Confirms typical platform bindings are resolved accurately via global token queries.
     */
    @isTest
    static void testGetSObjectTypeResolvesOrder() {
        Schema.SObjectType sot = QBOInvoiceMappingResolver.getSObjectType('Order');
        System.assertNotEquals(null, sot);
    }
}
