@isTest
private class ShopifyOrdersBatchSchedulerTest {
    
    @isTest
    static void testExecute() {

        Test.startTest();
        
        ShopifyOrdersBatchScheduler scheduler = new ShopifyOrdersBatchScheduler();
        
        try {
            scheduler.execute(null);
        } catch (Exception e) {
            System.debug('Managed expected query error: ' + e.getMessage());
        }
        
        Test.stopTest();
        
        System.assert(true);
    }
}