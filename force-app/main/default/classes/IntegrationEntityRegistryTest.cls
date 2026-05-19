@IsTest
private class IntegrationEntityRegistryTest {
    @IsTest
    static void resolvesFallbackEntitiesForCurrentProducts() {
        System.assertEquals('Customer', IntegrationEntityRegistry.resolveExternalEntity('qbonline', 'Account', null, 'Invoice'));
        System.assertEquals('Product', IntegrationEntityRegistry.resolveExternalEntity('shopify', 'Product2', null, 'Customer'));
        System.assertEquals('Invoice', IntegrationEntityRegistry.resolveExternalEntity('qbo', 'pkg__Invoice__c', null, 'Invoice'));
    }

    @IsTest
    static void resolvesConfiguredEntityDefinitionsBeforeFallback() {
        insert new Integration_Entity_Definition__c(
            Name = 'Klaviyo Contact',
            Integration_Key__c = 'klaviyo',
            Salesforce_Object__c = 'Contact',
            External_Entity__c = 'Profile',
            Active__c = true
        );
        IntegrationEntityRegistry.clearCache();

        System.assertEquals('Profile', IntegrationEntityRegistry.resolveExternalEntity('klaviyo', 'Contact', null, 'Default'));
        System.assertEquals('Default', IntegrationEntityRegistry.resolveExternalEntity('klaviyo', 'Account', null, 'Default'));
    }
}