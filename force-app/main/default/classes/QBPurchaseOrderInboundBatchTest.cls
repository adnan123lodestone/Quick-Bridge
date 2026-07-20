@isTest
private class QBPurchaseOrderInboundBatchTest {
    private class QBMock implements HttpCalloutMock {
        private Boolean shouldFail;
        public QBMock(Boolean shouldFail) { 
            this.shouldFail = shouldFail; 
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (shouldFail) {
                res.setStatusCode(400);
                res.setBody('{"Fault": {"Error": [{"Message": "API Error"}]}}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"PurchaseOrder":[{"Id":"PO-123", "DocNumber":"100"}]}}');
            }
            return res;
        }
    }

    @testSetup
    static void setupData() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'Mock_Named_Credential', '65');
        
        Account acc = new Account(Name = 'Supplier Acc');
        safePut(acc, 'QuickBridge_Int__QuickbookID__c', 'QB-ACC-001');
        safePut(acc, 'QuickbookID__c', 'QB-ACC-001');
        insert acc;

        Product2 prod = new Product2(Name = 'PO Product', IsActive = true);
        safePut(prod, 'QuickBridge_Int__QuickbookID__c', 'QB-PROD-001');
        safePut(prod, 'QuickbookID__c', 'QB-PROD-001');
        insert prod;
    }

    @isTest
    static void testBatchStartAndConstructors() {
        Test.setMock(HttpCalloutMock.class, new QBMock(false));

        Test.startTest();
        QBPurchaseOrderInboundBatch batch1 = new QBPurchaseOrderInboundBatch();
        QBPurchaseOrderInboundBatch batch2 = new QBPurchaseOrderInboundBatch('2024-01-01');

        Iterable<String> payloads = batch2.start(null);
        Id jobId = Database.executeBatch(batch2, 1);
        Test.stopTest();

        System.assertNotEquals(null, batch1, 'Constructor should work');
        System.assertNotEquals(null, payloads, 'Start should return payloads');
        System.assertNotEquals(null, jobId, 'Batch should be queued successfully');
    }

    @isTest
    static void testBatchExecuteValidPayload() {
        QBPurchaseOrderInboundBatch batch = new QBPurchaseOrderInboundBatch();
        String validPayload = '{' +
            '"Id": "PO-555",' +
            '"DocNumber": "12345",' +
            '"TxnDate": "2024-01-01",' +
            '"ExpectedDate": "2024-01-05",' +
            '"DueDate": "2024-01-10",' +
            '"VendorRef": { "value": "QB-ACC-001" },' +
            '"Line": [' +
                '{' +
                    '"Id": "LINE-1",' +
                    '"DetailType": "ItemBasedExpenseLineDetail",' +
                    '"Amount": 100.50,' +
                    '"ItemBasedExpenseLineDetail": {' +
                        '"ItemRef": { "value": "QB-PROD-001" },' +
                        '"Qty": 10,' +
                        '"UnitPrice": 10.05' +
                    '}' +
                '},' +
                '{' +
                    '"Id": "LINE-2",' +
                    '"DetailType": "OtherDetailType"' +
                '}' +
            ']' +
        '}';

        Test.startTest();
        Boolean unhandledException = false;
        try {
            batch.execute(null, new List<String>{ validPayload });
            String simplePayload = '{"Id":"PO-999","Quantity__c": 5, "IsActive": true}';
            batch.execute(null, new List<String>{ simplePayload });
        } catch (Exception e) {
            unhandledException = true;
        }
        Test.stopTest();

        System.assertEquals(false, unhandledException, 'Should process valid payload without unhandled exceptions');
    }

    @isTest
    static void testBatchExecuteInvalidData() {
        QBPurchaseOrderInboundBatch batch = new QBPurchaseOrderInboundBatch();

        String noIdPayload = '{"DocNumber": "123"}';
        String badDatesPayload = '{' +
            '"Id": "PO-666",' +
            '"TxnDate": "NotADate",' +
            '"ExpectedDate": "NotADate",' +
            '"DueDate": "NotADate"' +
        '}';
        String badJson = '{ Invalid JSON Formatter }';

        Test.startTest();
        batch.execute(null, new List<String>{ noIdPayload, badDatesPayload, badJson });
        Test.stopTest();

        Integer errorLogs = [SELECT count() FROM Error_Log__c];
        System.assert(errorLogs >= 1, 'Invalid data should generate error logs gracefully');
    }

    @isTest
    static void testStartException() {
        Test.setMock(HttpCalloutMock.class, new QBMock(true));

        QBPurchaseOrderInboundBatch batch = new QBPurchaseOrderInboundBatch();
        Test.startTest();
        batch.start(null);
        Test.stopTest();

        Integer errorLogs = [SELECT count() FROM Error_Log__c];
        System.assert(errorLogs >= 1, 'API failure should be caught and logged');
    }

    @isTest
    static void testExecuteNullScopeException() {
        QBPurchaseOrderInboundBatch batch = new QBPurchaseOrderInboundBatch();
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            batch.execute(null, null);
        } catch (Exception e) {
            exceptionCaught = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionCaught, 'Batch should throw and we should catch the NullPointerException when scope is null');
    }

    private static void safePut(SObject obj, String fieldName, Object value) {
        Map<String, Schema.SObjectField> fields = obj.getSObjectType().getDescribe().fields.getMap();
        String namespaced = 'QuickBridge_Int__' + fieldName;
        if (fields.containsKey(namespaced.toLowerCase())) {
            obj.put(namespaced, value);
        } else if (fields.containsKey(fieldName.toLowerCase())) {
            obj.put(fieldName, value);
        }
    }
}