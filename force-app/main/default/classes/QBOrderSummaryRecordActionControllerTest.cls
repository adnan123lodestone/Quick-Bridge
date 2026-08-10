@isTest
private class QBOrderSummaryRecordActionControllerTest {

    private class QBOrderSummaryMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String method = req.getMethod();

            if (method == 'GET' && endpoint.contains('/invoice/')) {
                res.setStatusCode(200);
                res.setBody('{"Invoice":{"Id":"999","SyncToken":"1","CustomerRef":{"value":"ACC-1"},"Line":[{"Id":"1","DetailType":"SalesItemLineDetail","Amount":10.00,"SalesItemLineDetail":{"Qty":1,"UnitPrice":10.00,"ItemRef":{"value":"PROD-1","name":"Widget"}}}]}}');
                return res;
            }
            if (method == 'POST' && endpoint.contains('/invoice')) {
                res.setStatusCode(200);
                res.setBody('{"Invoice":{"Id":"999","SyncToken":"1","Line":[{"Id":"1","DetailType":"SalesItemLineDetail"}]}}');
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    private class QBOrderSummaryErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('{"Fault":{"Error":[{"Message":"Internal Server Error","Detail":"Detailed failure"}]}}');
            return res;
        }
    }

    private static void configureQuickBooksConnection() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
    }

    @isTest
    static void testSyncToQuickBooks_NullId() {
        Boolean caught = false;
        try {
            QBOrderSummaryRecordActionController.syncToQuickBooks(null);
        } catch (AuraHandledException e) {
            caught = true;
        }
        System.assertEquals(true, caught, 'Should throw exception on null ID');
    }

    @isTest
    static void testSyncFromQuickBooks_NullId() {
        Boolean caught = false;
        try {
            QBOrderSummaryRecordActionController.syncFromQuickBooks(null);
        } catch (AuraHandledException e) {
            caught = true;
        }
        System.assertEquals(true, caught, 'Should throw exception on null ID');
    }

    @isTest
    static void testSyncToQuickBooks_NonExistingOrgSchemaOrRecord() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBOrderSummaryMock());

        Boolean caught = false;
        try {
            Id fakeId = Account.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
            QBOrderSummaryRecordActionController.syncToQuickBooks(fakeId);
        } catch (AuraHandledException e) {
            caught = true;
        }
        System.assertEquals(true, caught);
    }

    @isTest
    static void testSyncFromQuickBooks_NonExistingOrgSchemaOrRecord() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBOrderSummaryMock());

        Boolean caught = false;
        try {
            Id fakeId = Account.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
            QBOrderSummaryRecordActionController.syncFromQuickBooks(fakeId);
        } catch (AuraHandledException e) {
            caught = true;
        }
        System.assertEquals(true, caught);
    }

    @isTest
    static void testHelpersCoverage() {
        String summaryFields = QBOrderSummaryRecordActionController.buildOrderSummaryQueryFields();
        System.assertNotEquals(null, summaryFields);

        String itemFields = QBOrderSummaryRecordActionController.buildOrderItemSummaryQueryFields();
        System.assertNotEquals(null, itemFields);
    }
}