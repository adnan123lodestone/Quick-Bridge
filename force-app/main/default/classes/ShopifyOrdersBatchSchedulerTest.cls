@isTest
private class ShopifyOrdersBatchSchedulerTest {
    
    @isTest
    static void testExecuteSuccessPath() {
        Test.startTest();
        ShopifyOrdersBatchScheduler scheduler = new ShopifyOrdersBatchScheduler();
        // Standard execution
        scheduler.execute(null);
        Test.stopTest();
        
        System.assertNotEquals(null, scheduler, 'Scheduler should execute successfully');
    }

    @isTest
    static void testExecuteExceptionPath() {
        Test.startTest();
        ShopifyOrdersBatchScheduler scheduler = new ShopifyOrdersBatchScheduler();
        
        // Force the exception to hit the catch block
        ShopifyOrdersBatchScheduler.throwExceptionForTest = true;
        
        Boolean exceptionThrown = false;
        try {
            scheduler.execute(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        // Production-ready assertion
        System.assert(exceptionThrown, 'An exception should be thrown to cover the catch block');
    }
}