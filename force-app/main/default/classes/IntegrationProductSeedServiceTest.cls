@IsTest
private class IntegrationProductSeedServiceTest {
    @IsTest
    static void seedsDefaultProductsFromManagedDefinitions() {
        Test.startTest();
        IntegrationProductSeedService.seedDefaultProducts();
        Test.stopTest();

        System.assertEquals(8, [SELECT Count() FROM Integration_Product__c]);
        Integration_Product__c quickBooks = [
            SELECT Product_Key__c, Connector_Key__c, Product_Label__c, Has_Scheduler__c
            FROM Integration_Product__c
            WHERE Product_Key__c = 'quickbooks'
            LIMIT 1
        ];
        System.assertEquals('qbo', quickBooks.Connector_Key__c);
        System.assertEquals('QuickBooks', quickBooks.Product_Label__c);
        System.assertEquals(true, quickBooks.Has_Scheduler__c);

        Integration_Product__c ups = [
            SELECT Product_Key__c, Connector_Key__c, Logo_URL__c
            FROM Integration_Product__c
            WHERE Product_Key__c = 'ups'
            LIMIT 1
        ];
        System.assertEquals('ups', ups.Connector_Key__c);
        System.assertEquals(null, ups.Logo_URL__c);

        Integration_Product__c klaviyo = [
            SELECT Product_Key__c, Connector_Key__c, Product_Label__c, System_Managed__c
            FROM Integration_Product__c
            WHERE Product_Key__c = 'klaviyo'
            LIMIT 1
        ];
        System.assertEquals('klaviyo', klaviyo.Connector_Key__c);
        System.assertEquals('Klaviyo', klaviyo.Product_Label__c);
        System.assertEquals(true, klaviyo.System_Managed__c);
    }

    @IsTest
    static void repairsStaleUpsLogoOverride() {
        insert new Integration_Product__c(
            Name = 'UPS',
            Product_Key__c = 'ups',
            Connector_Key__c = 'ups',
            Product_Label__c = 'UPS',
            Enabled__c = true,
            Catalog_Active__c = true,
            Status__c = 'Available',
            Logo_URL__c = IntegrationProductSeedService.UPS_CDN_LOGO_URL
        );

        Test.startTest();
        IntegrationProductSeedService.repairKnownLogoOverrides();
        Test.stopTest();

        Integration_Product__c ups = [
            SELECT Logo_URL__c
            FROM Integration_Product__c
            WHERE Product_Key__c = 'ups'
            LIMIT 1
        ];
        System.assertEquals(null, ups.Logo_URL__c);
    }
}
