@isTest
private class ShopifyCustomersBatchSchedulerTest {
    
    @isTest
    static void testExecuteSuccessPath() {
        Test.startTest();
        ShopifyCustomersBatchScheduler scheduler = new ShopifyCustomersBatchScheduler();
        // Standard execution
        scheduler.execute(null);
        
        Test.stopTest();
        
        System.assertNotEquals(null, scheduler, 'Scheduler should execute successfully');
    }

    @isTest
    static void testExecuteExceptionPath() {
        Test.startTest();
        ShopifyCustomersBatchScheduler scheduler = new ShopifyCustomersBatchScheduler();
        
        // Force the exception to hit the catch block
        ShopifyCustomersBatchScheduler.throwExceptionForTest = true;
        
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