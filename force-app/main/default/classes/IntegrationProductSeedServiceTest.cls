@IsTest
private class IntegrationProductSeedServiceTest {
    @IsTest
    static void seedsSevenDefaultProducts() {
        Test.startTest();
        IntegrationProductSeedService.seedDefaultProducts();
        Test.stopTest();

        System.assertEquals(7, [SELECT Count() FROM Integration_Product__c]);
        Integration_Product__c quickBooks = [
            SELECT Product_Key__c, Connector_Key__c, Product_Label__c, Has_Scheduler__c
            FROM Integration_Product__c
            WHERE Product_Key__c = 'quickbooks'
            LIMIT 1
        ];
        System.assertEquals('qbo', quickBooks.Connector_Key__c);
        System.assertEquals('QuickBooks', quickBooks.Product_Label__c);
        System.assertEquals(true, quickBooks.Has_Scheduler__c);
    }
}
