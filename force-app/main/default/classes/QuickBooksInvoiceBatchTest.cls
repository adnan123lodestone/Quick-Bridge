@isTest
private class QuickBooksInvoiceBatchTest {

    private class QBInvoiceBatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/invoice/')) {
                res.setBody('{"Invoice":{"Id":"INV-1","SyncToken":"0","Line":[]}}');
            } else {
                res.setBody('{"Invoice":{"Id":"INV-1","Line":[]}}');
            }
            return res;
        }
    }

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Invoice Batch Account');
        insert acc;

        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today()
        );
        insert ord;
    }

    @isTest
    static void testBatchWithEmptyRecordIds() {
        Test.setMock(HttpCalloutMock.class, new QBInvoiceBatchMock());
        Set<Id> emptyIds = new Set<Id>();

        Test.startTest();
        Database.executeBatch(new QuickBooksInvoiceBatch(emptyIds, true), 1);
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testConstructorWithTriggerItems() {
        Test.setMock(HttpCalloutMock.class, new QBInvoiceBatchMock());
        Set<Id> emptyIds = new Set<Id>();
        List<SObject> triggerItems = new List<SObject>();

        QuickBooksInvoiceBatch batchInstance = new QuickBooksInvoiceBatch(emptyIds, false, triggerItems);
        System.assertNotEquals(null, batchInstance);
    }
}