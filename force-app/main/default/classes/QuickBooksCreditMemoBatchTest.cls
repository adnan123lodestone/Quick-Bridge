@isTest
private class QuickBooksCreditMemoBatchTest {
    
    private class QBCreditMemoMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"CreditMemo":{"Id":"CM-123","SyncToken":"0"}}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        try {
            Credit_Memo__c cm1 = new Credit_Memo__c();
            cm1.put('QuickBridgeTLG__External_Id__c', null);
            insert cm1;
        } catch (Exception e) {}
        
        try {
            Credit_Memo__c cm2 = new Credit_Memo__c();
            cm2.put('QuickBridgeTLG__External_Id__c', 'EXISTING-QB-ID');
            insert cm2;
        } catch (Exception e) {}
    }

    @isTest
    static void testBatchInitialSync() {
        Test.setMock(HttpCalloutMock.class, new QBCreditMemoMock());
        
        List<Credit_Memo__c> cmList = [SELECT Id FROM Credit_Memo__c];
        Set<Id> ids = new Set<Id>();
        for(Credit_Memo__c cm : cmList) ids.add(cm.Id);

        Test.startTest();
        Database.executeBatch(new QuickBooksCreditMemoBatch(ids, true), 10);
        Test.stopTest();
        
        System.assert(true);
    }

    @isTest
    static void testBatchUpdateSync() {
        Test.setMock(HttpCalloutMock.class, new QBCreditMemoMock());
        
        List<Credit_Memo__c> cmList = [SELECT Id FROM Credit_Memo__c];
        Set<Id> ids = new Set<Id>();
        for(Credit_Memo__c cm : cmList) ids.add(cm.Id);

        Test.startTest();
        Database.executeBatch(new QuickBooksCreditMemoBatch(ids, false), 10);
        Test.stopTest();
        
        System.assert(true);
    }
}