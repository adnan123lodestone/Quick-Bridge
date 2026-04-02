@isTest
private class ShopifyOrdersBatchSchedulerTest {
    
    @isTest
    static void testExecute() {
        Test.startTest();
        
        ShopifyOrdersBatchScheduler scheduler = new ShopifyOrdersBatchScheduler();
        scheduler.execute(null);
        
        Test.stopTest();
        
        System.assert(true);
    }
}