@isTest
private class QBOInvoiceSyncQueueableTest {
    private class BulkInvoiceMock implements HttpCalloutMock {
        Integer queryCalls = 0;

        public HttpResponse respond(HttpRequest req) {
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            System.assert(!endpoint.contains('/invoice/inv-1'), 'Invoice sync must not hydrate INV-1 with a per-record GET.');
            System.assert(!endpoint.contains('/invoice/inv-2'), 'Invoice sync must not hydrate INV-2 with a per-record GET.');

            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            if (endpoint.contains('/query?query=')) {
                queryCalls++;
                response.setStatusCode(200);
                response.setBody(
                    '{"QueryResponse":{"Invoice":[' +
                    '{"Id":"INV-1","DocNumber":"1001","CustomerRef":{"value":"CUST-1","name":"Customer One"},"Line":[{"DetailType":"SalesItemLineDetail","SalesItemLineDetail":{"ItemRef":{"value":"ITEM-1","name":"Item One"},"Qty":1,"UnitPrice":10}}]},' +
                    '{"Id":"INV-2","DocNumber":"1002","CustomerRef":{"value":"CUST-2","name":"Customer Two"},"Line":[{"DetailType":"SalesItemLineDetail","SalesItemLineDetail":{"ItemRef":{"value":"ITEM-2","name":"Item Two"},"Qty":2,"UnitPrice":15}}]}' +
                    ']}}'
                );
                return response;
            }

            response.setStatusCode(200);
            response.setBody('{}');
            return response;
        }
    }

    @isTest
    static void executeSyncFetchesInvoicesWithOneBulkQuery() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new BulkInvoiceMock());

        Test.startTest();
        new QBOInvoiceSyncQueueable(new Set<String>{ 'INV-1', 'INV-2' }).executeSync();
        Test.stopTest();

        System.assertEquals(false, QBTriggerHandler.isAccountProcessing);
        System.assertEquals(false, QBTriggerHandler.isProductProcessing);
        System.assertEquals(2, [
            SELECT Count()
            FROM Account
            WHERE QuickBridgeTLG__QuickbookID__c IN ('CUST-1', 'CUST-2')
        ]);
    }
}
