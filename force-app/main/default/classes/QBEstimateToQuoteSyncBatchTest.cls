@IsTest
private class QBEstimateToQuoteSyncBatchTest {

    private class QuickBooksMockResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            String jsonResponse = '{"QueryResponse":{"Estimate":[{"Id":"999","DocNumber":"EST-001","CustomerRef":{"value":"CUST123","name":"Test Customer"},"Line":[{"Id":"1","DetailType":"SalesItemLineDetail","Amount":150.0,"Description":"Test Line","SalesItemLineDetail":{"ItemRef":{"value":"PROD123","name":"Test Product"},"Qty":2,"UnitPrice":75.0}}]}]}}';
            res.setBody(jsonResponse);
            return res;
        }
    }

    @TestSetup
    static void setupData() {
        Id standardPbId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPbId, IsActive = true);
        
        Account acc = new Account(Name = 'Test Customer');
        setSObjectField(acc, 'QuickbookID__c', 'CUST123');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = standardPbId
        );
        insert opp;
        
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        setSObjectField(prod, 'QuickbookID__c', 'PROD123');
        insert prod;
        
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPbId,
            Product2Id = prod.Id,
            UnitPrice = 75.0,
            IsActive = true
        );
        insert pbe;
    }

    @IsTest
    static void testBatchExecuteDirectly() {
        String jsonStr = '{"Id":"999","DocNumber":"EST-001","CustomerRef":{"value":"CUST123","name":"Test Customer"},"Line":[{"Id":"1","DetailType":"SalesItemLineDetail","Amount":150.0,"Description":"Test Line","SalesItemLineDetail":{"ItemRef":{"value":"PROD123","name":"Test Product"},"Qty":2,"UnitPrice":75.0}}]}';
        List<String> scope = new List<String>{ jsonStr };
        
        Test.startTest();
        QBEstimateToQuoteSyncBatch batchJob = new QBEstimateToQuoteSyncBatch('2023-01-01');
        batchJob.execute(null, scope);
        Test.stopTest();
        
        List<Quote> quotes = [SELECT Id, Name FROM Quote];
        System.assertEquals(1, quotes.size(), 'Expected 1 Quote to be created by sync batch');
        
        List<QuoteLineItem> lineItems = [SELECT Id, Quantity, UnitPrice FROM QuoteLineItem];
        System.assertEquals(1, lineItems.size(), 'Expected 1 QuoteLineItem to be created by sync batch');
    }
    
    @IsTest
    static void testStartMethodCoverage() {
        Test.setMock(HttpCalloutMock.class, new QuickBooksMockResponse());
        
        Test.startTest();
        QBEstimateToQuoteSyncBatch batchJob = new QBEstimateToQuoteSyncBatch();
        Iterable<String> scope = batchJob.start(null);
        Test.stopTest();
        
        System.assertNotEquals(null, scope);
    }

    private static void setSObjectField(SObject obj, String fieldName, Object val) {
        if (obj == null || String.isBlank(fieldName)) return;
        Map<String, Schema.SObjectField> fields = obj.getSObjectType().getDescribe().fields.getMap();
        String key = fieldName.toLowerCase();
        if (fields.containsKey(key)) {
            obj.put(fields.get(key).getDescribe().getName(), val);
        }
        if (fields.containsKey('quickbridgetlg__' + key)) {
            obj.put(fields.get('quickbridgetlg__' + key).getDescribe().getName(), val);
        }
    }
}