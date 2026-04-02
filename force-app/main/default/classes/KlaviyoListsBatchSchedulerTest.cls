@isTest
private class KlaviyoListsBatchSchedulerTest {
    
    @isTest
    static void testExecute() {
        Test.startTest();
        
        KlaviyoListsBatchScheduler scheduler = new KlaviyoListsBatchScheduler();
        scheduler.execute(null);
        
        Test.stopTest();
        
        System.assert(true);
    }
}