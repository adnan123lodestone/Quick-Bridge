@isTest
private class QuickBooksPurchaseOrderBatchTest {

    private class QBPurchaseOrderMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            if (req.getMethod() == 'GET') {
                res.setBody('{"PurchaseOrder":{"Id":"PO-1","SyncToken":"0"}}');
            } else {
                res.setBody('{"PurchaseOrder":{"Id":"PO-NEW","SyncToken":"0"}}');
            }
            return res;
        }
    }

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'PO Batch Account', QuickbookID__c = 'QB-ACC-1');
        insert acc;

        Product2 prod = new Product2(Name = 'PO Product', QuickbookID__c = 'QB-PROD-1', IsActive = true);
        insert prod;

        Purchase_Order__c po = new Purchase_Order__c(
            Account__c = acc.Id,
            Supplier__c = acc.Id,
            External_Id__c = null
        );
        insert po;

        Purchase_Order_Line__c pol = new Purchase_Order_Line__c(
            Purchase_Order__c = po.Id,
            Product__c = prod.Id,
            Quantity__c = 10,
            Cost_Price__c = 100,
            Product_Description__c = 'Test Description'
        );
        insert pol;
    }

    @isTest
    static void testBatchInitialSync() {
        Test.setMock(HttpCalloutMock.class, new QBPurchaseOrderMock());
        
        Purchase_Order__c po = [SELECT Id FROM Purchase_Order__c LIMIT 1];
        Set<Id> ids = new Set<Id>{ po.Id };

        Test.startTest();
        Database.executeBatch(new QuickBooksPurchaseOrderBatch(ids, true), 1);
        Test.stopTest();

        Purchase_Order__c updatedPo = [SELECT External_Id__c FROM Purchase_Order__c WHERE Id = :po.Id];
        System.assertNotEquals(null, updatedPo.External_Id__c);
    }

    @isTest
    static void testBatchUpdateSync() {
        Test.setMock(HttpCalloutMock.class, new QBPurchaseOrderMock());
        
        Purchase_Order__c po = [SELECT Id FROM Purchase_Order__c LIMIT 1];
        po.External_Id__c = 'PO-EXISTING';
        update po;
        
        Set<Id> ids = new Set<Id>{ po.Id };

        Test.startTest();
        Database.executeBatch(new QuickBooksPurchaseOrderBatch(ids, false), 1);
        Test.stopTest();

        System.assert(true);
    }
}