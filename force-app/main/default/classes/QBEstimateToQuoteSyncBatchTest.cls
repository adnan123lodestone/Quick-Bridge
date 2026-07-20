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
        
        Account acc = new Account(
            Name = 'Test Customer',
            QuickbookID__c = 'CUST123'
        );
        insert acc;
        
        Product2 prod = new Product2(
            Name = 'Test Product',
            QuickbookID__c = 'PROD123',
            IsActive = true
        );
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
        
        List<Quote> quotes = [SELECT Id, Name, QuickbookID__c, Status FROM Quote WHERE QuickbookID__c = '999'];
        System.assertEquals(1, quotes.size());
        
        List<QuoteLineItem> lineItems = [SELECT Id, QB_LineItemID__c, Quantity, UnitPrice FROM QuoteLineItem WHERE QB_LineItemID__c = '999:1'];
        System.assertEquals(1, lineItems.size());
        System.assertEquals(2, lineItems[0].Quantity);
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
}