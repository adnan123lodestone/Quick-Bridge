@isTest
private class QBQuoteToEstimateSyncBatchTest {

    private static String lastRequestBody;

    private class SingleQuoteMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public SingleQuoteMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest req) {
            lastRequestBody = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }

    @testSetup
    static void setupData() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');

        QBTriggerHandler.isAccountProcessing = true;
        QBTriggerHandler.isProductProcessing = true;
        QBTriggerHandler.isQuoteProcessing = true;

        try {
            Account acc = new Account(Name = 'Test Quote Account');
            setSObjectField(acc, 'QuickbookID__c', 'QB_ACC_123');
            insert acc;

            Product2 prod = new Product2(Name = 'Test Quote Product', IsActive = true);
            setSObjectField(prod, 'QuickbookID__c', 'QB_PROD_456');
            insert prod;

            Id pricebookId = Test.getStandardPricebookId();
            PricebookEntry pbe = new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = prod.Id,
                UnitPrice = 100.0,
                IsActive = true
            );
            insert pbe;

            Opportunity opp = new Opportunity(
                Name = 'Test Quote Opp',
                AccountId = acc.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            );
            insert opp;

            Quote q = new Quote(
                Name = 'Test Outbound Quote',
                OpportunityId = opp.Id,
                Pricebook2Id = pricebookId,
                ExpirationDate = Date.today().addDays(15),
                Description = 'Test Quote Description'
            );
            insert q;

            QuoteLineItem qli = new QuoteLineItem(
                QuoteId = q.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 2,
                UnitPrice = 100.0,
                Description = 'Line item description'
            );
            insert qli;
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
            QBTriggerHandler.isProductProcessing = false;
            QBTriggerHandler.isQuoteProcessing = false;
        }
    }

    @isTest
    static void testBatchExecutionSuccess() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');
        String successJson = '{"Estimate":{"Id":"QBO_EST_789","SyncToken":"1"}}';
        Test.setMock(HttpCalloutMock.class, new SingleQuoteMock(200, successJson));

        Quote q = [SELECT Id, Opportunity.AccountId FROM Quote LIMIT 1];
        Set<Id> ids = new Set<Id>{ q.Id };

        Test.startTest();
        QBQuoteToEstimateSyncBatch batch = new QBQuoteToEstimateSyncBatch(ids, true);
        Database.executeBatch(batch, 1);
        Test.stopTest();

        String fields = QBQuoteToEstimateSyncBatch.buildQuoteQueryFields();
        Quote updatedQuote = (Quote) Database.query('SELECT ' + fields + ' FROM Quote WHERE Id = \'' + q.Id + '\'');
        String qbId = (String) getSObjectField(updatedQuote, 'QuickbookID__c');
        System.assertEquals('QBO_EST_789', qbId);
    }

    @isTest
    static void testBatchExecutionDefaultConstructor() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');
        String successJson = '{"Estimate":{"Id":"QBO_EST_999","SyncToken":"0"}}';
        Test.setMock(HttpCalloutMock.class, new SingleQuoteMock(200, successJson));

        Test.startTest();
        QBQuoteToEstimateSyncBatch batch = new QBQuoteToEstimateSyncBatch();
        Database.executeBatch(batch, 1);
        Test.stopTest();

        String fields = QBQuoteToEstimateSyncBatch.buildQuoteQueryFields();
        Quote updatedQuote = (Quote) Database.query('SELECT ' + fields + ' FROM Quote LIMIT 1');
        String qbId = (String) getSObjectField(updatedQuote, 'QuickbookID__c');
        System.assertEquals('QBO_EST_999', qbId);
    }

    @isTest
    static void testBatchExecutionHttpError() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');
        String errorJson = '{"Fault":{"Error":[{"Message":"Customer missing"}]}}';
        Test.setMock(HttpCalloutMock.class, new SingleQuoteMock(400, errorJson));

        Quote q = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        QBQuoteToEstimateSyncBatch batch = new QBQuoteToEstimateSyncBatch(new Set<Id>{ q.Id }, false);
        Database.executeBatch(batch, 1);
        Test.stopTest();

        String fields = QBQuoteToEstimateSyncBatch.buildQuoteQueryFields();
        Quote updatedQuote = (Quote) Database.query('SELECT ' + fields + ' FROM Quote WHERE Id = \'' + q.Id + '\'');
        String qbId = (String) getSObjectField(updatedQuote, 'QuickbookID__c');
        System.assertEquals(null, qbId);
    }

    @isTest
    static void testBatchExecutionUnsyncedAccountAndProduct() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');
        String successJson = '{"Estimate":{"Id":"QBO_EST_888","SyncToken":"2"}}';
        Test.setMock(HttpCalloutMock.class, new SingleQuoteMock(200, successJson));

        QBTriggerHandler.isAccountProcessing = true;
        QBTriggerHandler.isProductProcessing = true;
        QBTriggerHandler.isQuoteProcessing = true;

        Account acc2 = new Account(Name = 'Unsynced Account');
        insert acc2;

        Product2 prod2 = new Product2(Name = 'Unsynced Product', IsActive = true);
        insert prod2;

        Id pricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe2 = new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = prod2.Id, UnitPrice = 50.0, IsActive = true);
        insert pbe2;

        Opportunity opp2 = new Opportunity(Name = 'Unsynced Opp', AccountId = acc2.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp2;

        Quote q2 = new Quote(Name = 'Unsynced Parent Quote', OpportunityId = opp2.Id, Pricebook2Id = pricebookId);
        insert q2;

        QuoteLineItem qli2 = new QuoteLineItem(QuoteId = q2.Id, PricebookEntryId = pbe2.Id, Quantity = 1, UnitPrice = 50.0);
        insert qli2;

        QBTriggerHandler.isAccountProcessing = false;
        QBTriggerHandler.isProductProcessing = false;
        QBTriggerHandler.isQuoteProcessing = false;

        Test.startTest();
        QBQuoteToEstimateSyncBatch batch = new QBQuoteToEstimateSyncBatch(new Set<Id>{ q2.Id }, true);
        Database.executeBatch(batch, 1);
        Test.stopTest();
    }

    @isTest
    static void sharedScopePreservesNestedLinesAndSyncToken() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');
        Quote quoteRecord = [SELECT Id FROM Quote LIMIT 1];
        setSObjectField(quoteRecord, 'QuickbookID__c', 'QBO_EXISTING_ESTIMATE');
        setSObjectField(quoteRecord, 'SyncToken__c', '7');
        QBTriggerHandler.isQuoteProcessing = true;
        try {
            update quoteRecord;
        } finally {
            QBTriggerHandler.isQuoteProcessing = false;
        }
        List<Quote> scope = QBQuoteToEstimateSyncBatch.loadQuotesForSharedExecution(
            new Set<Id>{ quoteRecord.Id }
        );
        Test.setMock(
            HttpCalloutMock.class,
            new SingleQuoteMock(
                200,
                '{"Estimate":{"Id":"QBO_EXISTING_ESTIMATE","SyncToken":"8","Line":[{"Id":"QBO_LINE_1","DetailType":"SalesItemLineDetail"}]}}'
            )
        );

        Test.startTest();
        ConnectorExecutionResult result = new QBQuoteToEstimateSyncBatch(
            new Set<Id>{ quoteRecord.Id },
            false
        ).executeSharedScope(scope);
        Test.stopTest();

        System.assertEquals(1, result.processedCount);
        System.assertEquals(
            1,
            result.successfulCount,
            'Shared Quote error: ' + result.errorSummary
        );
        System.assertEquals(0, result.failedCount);
        System.assert(
            lastRequestBody.contains('"SyncToken":"0"'),
            'Expected the legacy missing-token fallback in: ' + lastRequestBody
        );
        System.assert(
            lastRequestBody.contains('"ItemRef"'),
            'Expected nested ItemRef in: ' + lastRequestBody
        );
        System.assert(
            lastRequestBody.contains('"Qty":2'),
            'Expected nested quantity in: ' + lastRequestBody
        );
    }

    @isTest
    static void sharedScopeReportsRetryableProviderFailure() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');
        Quote quoteRecord = [SELECT Id FROM Quote LIMIT 1];
        List<Quote> scope = QBQuoteToEstimateSyncBatch.loadQuotesForSharedExecution(
            new Set<Id>{ quoteRecord.Id }
        );
        Test.setMock(
            HttpCalloutMock.class,
            new SingleQuoteMock(503, '{"Fault":{"Error":[{"Message":"Unavailable"}]}}')
        );

        Test.startTest();
        ConnectorExecutionResult result = new QBQuoteToEstimateSyncBatch(
            new Set<Id>{ quoteRecord.Id },
            true
        ).executeSharedScope(scope);
        Test.stopTest();

        System.assertEquals(1, result.processedCount);
        System.assertEquals(0, result.successfulCount);
        System.assertEquals(1, result.failedCount);
        System.assertEquals(true, result.retryable);
        System.assertEquals(new List<Id>{ quoteRecord.Id }, result.retryRecordIds);
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

    private static Object getSObjectField(SObject obj, String fieldName) {
        if (obj == null || String.isBlank(fieldName)) return null;
        Map<String, Schema.SObjectField> fields = obj.getSObjectType().getDescribe().fields.getMap();
        String key = fieldName.toLowerCase();
        if (fields.containsKey(key)) {
            try {
                Object val = obj.get(fields.get(key).getDescribe().getName());
                if (val != null) return val;
            } catch (Exception e) {}
        }
        if (fields.containsKey('quickbridgetlg__' + key)) {
            try {
                Object val = obj.get(fields.get('quickbridgetlg__' + key).getDescribe().getName());
                if (val != null) return val;
            } catch (Exception e) {}
        }
        return null;
    }
}
