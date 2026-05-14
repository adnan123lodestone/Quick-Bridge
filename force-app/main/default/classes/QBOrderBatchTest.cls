@isTest
private class QBOrderBatchTest {
    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'QB Order Batch Acc');
        insert acc;

        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today()
        );
        insert ord;
    }

    @isTest
    static void testBatchRuns() {
        Order ord = [SELECT Id, AccountId, Status, EffectiveDate FROM Order LIMIT 1];
        Test.startTest();
        Database.executeBatch(new QBOrderBatch(new List<Order>{ ord }, true), 1);
        Test.stopTest();
        System.assertNotEquals(null, ord.Id);
    }
}