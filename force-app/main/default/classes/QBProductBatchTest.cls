@isTest
private class QBProductBatchTest {

    private class QBProductBatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            if (endpoint.contains('/item/')) {
                res.setBody('{"Item":{"Id":"ITM-200","SyncToken":"0"}}');
            } else {
                res.setBody('{"Item":{"Id":"ITM-200"}}');
            }
            return res;
        }
    }

    @testSetup
    static void setupData() {
        insert new Product2(Name = 'QB Product Batch', IsActive = true, Sale_Price__c = 22);
    }

    @isTest
    static void testBatchRuns() {
        Product2 productToSync = [SELECT Id, Name, QuickbookID__c, Sale_Price__c FROM Product2 WHERE Name = 'QB Product Batch' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new QBProductBatchMock());

        Test.startTest();
        Database.executeBatch(new QBProductBatch(new List<Product2>{ productToSync }, true), 1);
        Test.stopTest();

        System.assertNotEquals(null, productToSync.Id);
    }
}