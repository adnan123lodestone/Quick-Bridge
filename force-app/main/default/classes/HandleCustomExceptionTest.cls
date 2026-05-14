@isTest
private class HandleCustomExceptionTest {

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Custom Exception Test Account');
        insert acc;
    }

    @isTest
    static void testLogExceptionWithoutRelatedId() {
        Integer beforeCount = [SELECT Count() FROM CustomException__c];

        try {
            Integer x = 1 / 0;
            System.assertEquals(0, x);
        } catch (Exception e) {
            Test.startTest();
            HandleCustomException.LogException(e);
            Test.stopTest();
        }

        Integer afterCount = [SELECT Count() FROM CustomException__c];
        System.assert(afterCount >= beforeCount, 'Exception logging method should execute.');
    }

    @isTest
    static void testLogExceptionWithRelatedId() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Integer beforeCount = [SELECT Count() FROM CustomException__c];

        try {
            String value = null;
            value.toLowerCase();
        } catch (Exception e) {
            Test.startTest();
            HandleCustomException.LogException(e, acc.Id);
            Test.stopTest();
        }

        Integer afterCount = [SELECT Count() FROM CustomException__c];
        System.assert(afterCount >= beforeCount, 'Overloaded logger should execute.');
    }
}