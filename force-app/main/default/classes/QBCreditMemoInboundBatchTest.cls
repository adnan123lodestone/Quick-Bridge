@isTest
private class QBCreditMemoInboundBatchTest {

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
                res.setBody('{"QueryResponse":{"CreditMemo":[{"Id":"CM-123", "DocNumber":"100", "Line":[{"Id":"L-1","DetailType":"SalesItemLineDetail","SalesItemLineDetail":{"Qty":1,"UnitPrice":100,"ItemRef":{"value":"QB-PROD-001"}}}]}]}}');
            }
            return res;
        }
    }

    @testSetup
    static void setupData() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'Mock_Named_Credential', '65');

        Account acc = new Account(Name = 'Test Customer Acc');
        safePut(acc, 'QuickBridge_Int__QuickbookID__c', 'QB-CUST-001');
        safePut(acc, 'QuickbookID__c', 'QB-CUST-001');
        insert acc;

        Product2 prod = new Product2(Name = 'Test Product');
        safePut(prod, 'QuickBridge_Int__QuickbookID__c', 'QB-PROD-001');
        safePut(prod, 'QuickbookID__c', 'QB-PROD-001');
        insert prod;
    }

    @isTest
    static void testBatchStartAndConstructors() {
        Test.setMock(HttpCalloutMock.class, new QBMock(false));

        Test.startTest();
        QBCreditMemoInboundBatch batch1 = new QBCreditMemoInboundBatch();
        QBCreditMemoInboundBatch batch2 = new QBCreditMemoInboundBatch('2024-01-01');
        
        Iterable<String> payloads = batch2.start(null);
        Id jobId = Database.executeBatch(batch2, 1);
        Test.stopTest();
        
        System.assertNotEquals(null, batch1);
        System.assertNotEquals(null, payloads);
        System.assertNotEquals(null, jobId);
    }

    @isTest
    static void testBatchExecuteValidPayload() {
        QBCreditMemoInboundBatch batch = new QBCreditMemoInboundBatch();
        String validPayload = '{"Id": "CM-555", "DocNumber": "12345", "TxnDate": "2024-01-01", "DueDate": "2024-01-10", "Balance": 100.50, "CustomerRef": { "value": "QB-CUST-001" }, "Line": [{"Id": "L-1", "DetailType": "SalesItemLineDetail", "SalesItemLineDetail": {"Qty": 5, "UnitPrice": 20.0, "ItemRef": {"value": "QB-PROD-001"}}}]}';

        Test.startTest();
        Boolean unhandledExceptionThrown = false;
        try {
            batch.execute(null, new List<String>{ validPayload });
        } catch (Exception e) {
            unhandledExceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(false, unhandledExceptionThrown);
    }

    @isTest
    static void testBatchExecuteInvalidData() {
        QBCreditMemoInboundBatch batch = new QBCreditMemoInboundBatch();
        String noIdPayload = '{"DocNumber": "123"}';
        String badTypesPayload = '{"Id": "CM-666", "TxnDate": "NotADate", "DueDate": "NotADate", "Balance": "NotADecimal", "Line": [{"Id": "L-2", "DetailType": "SalesItemLineDetail", "SalesItemLineDetail": {"Qty": "NotANumber", "ItemRef": {"value": "QB-PROD-001"}}}]}';
        String badJson = '{ Invalid JSON }';

        Test.startTest();
        batch.execute(null, new List<String>{ noIdPayload, badTypesPayload, badJson });
        Test.stopTest();
        
        SObjectType logType = Schema.getGlobalDescribe().get('Error_Log__c');
        if(logType == null) logType = Schema.getGlobalDescribe().get('QuickBridge_Int__Error_Log__c');
        if(logType != null) {
            Integer errorLogs = Database.countQuery('SELECT count() FROM ' + logType.getDescribe().getName());
            System.assert(errorLogs >= 1);
        }
    }

    @isTest
    static void testStartException() {
        Test.setMock(HttpCalloutMock.class, new QBMock(true));
        QBCreditMemoInboundBatch batch = new QBCreditMemoInboundBatch();
        
        Test.startTest();
        batch.start(null);
        Test.stopTest();
        
        SObjectType logType = Schema.getGlobalDescribe().get('Error_Log__c');
        if(logType == null) logType = Schema.getGlobalDescribe().get('QuickBridge_Int__Error_Log__c');
        if(logType != null) {
            Integer errorLogs = Database.countQuery('SELECT count() FROM ' + logType.getDescribe().getName());
            System.assert(errorLogs >= 1);
        }
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