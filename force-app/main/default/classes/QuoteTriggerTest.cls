@isTest
private class QuoteTriggerTest {

    @testSetup
    static void setupData() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');

        Account acc = new Account(Name = 'Trigger Quote Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Trigger Quote Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
    }

    @isTest
    static void testQuoteTriggerInsertAndUpdate() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');

        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Quote q = new Quote(
            Name = 'Realtime Trigger Quote',
            OpportunityId = opp.Id,
            ExpirationDate = Date.today().addDays(10)
        );
        insert q;

        q.Name = 'Updated Realtime Trigger Quote';
        update q;
        Test.stopTest();

        System.assertNotEquals(null, q.Id);
    }
}