@isTest
private class KlaviyoProfilesBatchSchedulerTest {
    
    @isTest
    static void testExecute() {
        Test.startTest();
        
        KlaviyoProfilesBatchScheduler scheduler = new KlaviyoProfilesBatchScheduler();
        scheduler.execute(null);
        
        Test.stopTest();
        
        System.assert(true);
    }
}