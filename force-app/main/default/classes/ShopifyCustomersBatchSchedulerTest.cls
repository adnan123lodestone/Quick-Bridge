@isTest
private class ShopifyCustomersBatchSchedulerTest {
    
    @isTest
    static void testExecute() {
        Test.startTest();
        
        ShopifyCustomersBatchScheduler scheduler = new ShopifyCustomersBatchScheduler();
        scheduler.execute(null);
        
        Test.stopTest();
    }
}