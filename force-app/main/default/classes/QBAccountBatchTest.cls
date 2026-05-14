@isTest
private class QBAccountBatchTest {

    private class QBAccountBatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"Customer":{"Id":"555"}}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        insert new Account(Name = 'QB Batch Account');
    }

    @isTest
    static void testBatchExecutesStartExecuteFinish() {
        Account acc = [SELECT Id, Name, QuickbookID__c FROM Account WHERE Name = 'QB Batch Account' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new QBAccountBatchMock());

        Test.startTest();
        Database.executeBatch(new QBAccountBatch(new List<Account>{ acc }, true), 1);
        Test.stopTest();

        System.assertNotEquals(null, acc.Id);
    }
}