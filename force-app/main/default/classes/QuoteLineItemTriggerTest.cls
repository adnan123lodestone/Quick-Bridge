@isTest
private class QuoteLineItemTriggerTest {
    @testSetup
    static void setupData() {
        QBTriggerHandler.isAccountProcessing = true;
        QBTriggerHandler.isProductProcessing = true;
        QBTriggerHandler.isQuoteProcessing = true;

        try {
            Account acc = new Account(Name = 'QLI Test Account');
            insert acc;

            Product2 prod = new Product2(Name = 'QLI Test Product', IsActive = true);
            insert prod;

            Id pricebookId = Test.getStandardPricebookId();
            PricebookEntry pbe = new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = prod.Id,
                UnitPrice = 50.0,
                IsActive = true
            );
            insert pbe;

            Opportunity opp = new Opportunity(
                Name = 'QLI Test Opp',
                AccountId = acc.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            );
            insert opp;

            Quote q = new Quote(
                Name = 'QLI Test Quote',
                OpportunityId = opp.Id,
                Pricebook2Id = pricebookId
            );
            insert q;
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
            QBTriggerHandler.isProductProcessing = false;
            QBTriggerHandler.isQuoteProcessing = false;
        }
    }

    @isTest
    static void testQuoteLineItemTriggers() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry LIMIT 1];

        Test.startTest();
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 2,
            UnitPrice = 50.0
        );
        insert qli;

        qli.Quantity = 5;
        update qli;

        delete qli;
        Test.stopTest();
    }
}