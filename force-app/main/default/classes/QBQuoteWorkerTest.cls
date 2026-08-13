@isTest
private class QBQuoteWorkerTest {
    private class SingleQuoteMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"Estimate":{"Id":"QBO_WORKER_EST_100","SyncToken":"0"}}');
            return res;
        }
    }

    private class FailedQuoteMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setBody('{"Fault":{"Error":[{"Message":"Unavailable"}]}}');
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
            Account acc = new Account(Name = 'Worker Test Account');
            setSObjectField(acc, 'QuickbookID__c', 'QB_ACC_WORKER');
            insert acc;

            Product2 prod = new Product2(Name = 'Worker Test Product', IsActive = true);
            setSObjectField(prod, 'QuickbookID__c', 'QB_PROD_WORKER');
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
                Name = 'Worker Test Opp',
                AccountId = acc.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            );
            insert opp;

            Quote q = new Quote(
                Name = 'Worker Test Quote',
                OpportunityId = opp.Id,
                Pricebook2Id = pricebookId
            );
            insert q;

            QuoteLineItem qli = new QuoteLineItem(
                QuoteId = q.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = 100.0
            );
            insert qli;
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
            QBTriggerHandler.isProductProcessing = false;
            QBTriggerHandler.isQuoteProcessing = false;
        }
    }

    @isTest
    static void testWorkerProcessSuccess() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');
        Test.setMock(HttpCalloutMock.class, new SingleQuoteMock());

        Quote q = [SELECT Id FROM Quote LIMIT 1];

        Integration_Work_Item__c item = new Integration_Work_Item__c(
            Integration__c = 'QuickBooks',
            Operation__c = 'QuoteUpsert',
            Source_Object__c = 'Quote',
            Source_Record_Id__c = q.Id,
            Source_Salesforce_Id__c = q.Id,
            Unique_Key__c = 'Quote:' + q.Id,
            Payload__c = '{"isInitialSync":true}'
        );
        insert item;

        Test.startTest();
        QBQuoteWorker worker = new QBQuoteWorker();
        worker.handle(item);
        Test.stopTest();

        Quote updatedQuote = [SELECT Id, QuickbookID__c FROM Quote WHERE Id = :q.Id];
        System.assertEquals('QBO_WORKER_EST_100', updatedQuote.QuickbookID__c);
    }

    @isTest
    static void testWorkerPropagatesProviderFailure() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBooksNC', '65');
        Test.setMock(HttpCalloutMock.class, new FailedQuoteMock());
        Quote quoteRecord = [SELECT Id FROM Quote LIMIT 1];
        Integration_Work_Item__c item = new Integration_Work_Item__c(
            Source_Record_Id__c = quoteRecord.Id,
            Source_Salesforce_Id__c = quoteRecord.Id,
            Payload__c = '{"isInitialSync":true}'
        );

        Test.startTest();
        try {
            QBQuoteWorker.process(item);
            System.assert(false, 'Quote work must not complete after a provider failure.');
        } catch (QBQuoteWorker.QBQuoteWorkerException expected) {
            System.assert(expected.getMessage().contains('synchronization failed'));
        }
        Test.stopTest();
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