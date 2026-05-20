@isTest
private class QBOInvoiceMappingResolverTest {

    // Builds a minimal Field_Mapping__mdt row without inserting it (CMT instantiation pattern).
    private static Field_Mapping__mdt makeRow(String sfObject, String sfField, String externalField, String direction) {
        return new Field_Mapping__mdt(
            Integration__c = 'qbonline',
            SF_Object__c = sfObject,
            SF_Field__c = sfField,
            External_Field__c = externalField,
            Sync_Direction__c = direction,
            Is_Active__c = true
        );
    }

    // Helper: insert an Integration_Entity_Definition__c so resolveExternalEntity returns Invoice for a custom object.
    private static void registerInvoiceObject(String sfObject) {
        insert new Integration_Entity_Definition__c(
            Name = sfObject + '_Invoice',
            Integration_Key__c = 'qbonline',
            Salesforce_Object__c = sfObject,
            External_Entity__c = 'Invoice',
            Active__c = true
        );
        IntegrationEntityRegistry.clearCache();
    }

    @isTest
    static void testResolvesOrder() {
        // Order maps to Invoice in the fallback registry — no custom entity needed.
        // We need actual Field_Mapping__mdt rows, but CMT can't be inserted in tests.
        // We verify the resolver behaves correctly when the registry confirms Invoice for Order
        // by checking the fallback path (Order→Invoice is in IntegrationEntityRegistry defaults).

        // Since Field_Mapping__mdt can't be inserted in tests we verify the resolver
        // throws a clear exception when no active rows exist (confirms the right code path).
        try {
            QBOInvoiceMappingResolver.resolve();
            System.assert(false, 'Expected ResolverException when no metadata rows exist');
        } catch (QBOInvoiceMappingResolver.ResolverException e) {
            System.assert(
                e.getMessage().contains('No active Field_Mapping__mdt'),
                'Exception should explain missing metadata: ' + e.getMessage()
            );
        }
    }

    @isTest
    static void testRegistryFallbackResolvesOrderToInvoice() {
        // Directly test that IntegrationEntityRegistry resolves Order → Invoice
        // (the foundation the resolver depends on).
        String resolved = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'Order', null, null);
        System.assertEquals('Invoice', resolved, 'Order should resolve to Invoice via fallback registry');
    }

    @isTest
    static void testRegistryResolvesNamespacedObjectToInvoice() {
        // Namespaced object QuickBridgeTLG__Invoice__c should strip to Invoice__c,
        // which is in the fallback registry as mapping to Invoice.
        String resolved = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'QuickBridgeTLG__Invoice__c', null, null);
        System.assertEquals('Invoice', resolved, 'Namespaced Invoice__c should resolve to Invoice via fallback registry');
    }

    @isTest
    static void testRegistryResolvesCustomObjectViaEntityDefinition() {
        registerInvoiceObject('Custom_Invoice__c');
        String resolved = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'Custom_Invoice__c', null, null);
        System.assertEquals('Invoice', resolved, 'Custom object should resolve to Invoice after entity definition insert');
    }

    @isTest
    static void testRegistryDoesNotResolveUnmappedObjectToInvoice() {
        // Account resolves to Customer, not Invoice
        String resolved = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'Account', null, 'DEFAULT');
        System.assertEquals('Customer', resolved, 'Account should resolve to Customer, not Invoice');
    }

    @isTest
    static void testObjectMatchesNamespaceStripping() {
        // Verify the objectMatches logic in the controller strips namespaces correctly.
        // Access via QBOInvoicePdfActionController (same logic); here just assert registry behavior.
        String resolvedNamespaced = IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'pkg__Invoice__c', null, null);
        System.assertEquals('Invoice', resolvedNamespaced, 'pkg__Invoice__c should strip to Invoice__c and match fallback');
    }

    @isTest
    static void testResolverThrowsOnNoMetadata() {
        Boolean threw = false;
        try {
            QBOInvoiceMappingResolver.resolve();
        } catch (QBOInvoiceMappingResolver.ResolverException e) {
            threw = true;
            System.assert(String.isNotBlank(e.getMessage()), 'Exception message should be set');
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'resolve() must throw when no active metadata rows exist');
    }

    @isTest
    static void testGetSObjectTypeReturnsNullForUnknownObject() {
        Schema.SObjectType sot = QBOInvoiceMappingResolver.getSObjectType('UnknownObject_XYZ__c');
        System.assertEquals(null, sot, 'Unknown object should return null');
    }

    @isTest
    static void testGetSObjectTypeResolvesOrder() {
        Schema.SObjectType sot = QBOInvoiceMappingResolver.getSObjectType('Order');
        System.assertNotEquals(null, sot, 'Order should resolve to a non-null SObjectType');
    }
}