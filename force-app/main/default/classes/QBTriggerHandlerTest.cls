@isTest
private class QBTriggerHandlerTest {

    private class QBTriggerCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            if (endpoint.contains('/customer/')) {
                res.setBody('{"Customer":{"Id":"TRG-CUST","SyncToken":"0"}}');
            } else if (endpoint.contains('/item/')) {
                res.setBody('{"Item":{"Id":"TRG-ITEM","SyncToken":"0"}}');
            } else if (endpoint.contains('/customer')) {
                res.setBody('{"Customer":{"Id":"TRG-CUST"}}');
            } else if (endpoint.contains('/item')) {
                res.setBody('{"Item":{"Id":"TRG-ITEM"}}');
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    @testSetup
    static void setupData() {
        insert new Account(Name = 'Trigger Handler Account');
        insert new Product2(Name = 'Trigger Handler Product', IsActive = true, Sale_Price__c = 12);
    }

    @isTest
    static void testHandleAccountTriggerInsertAndUpdate() {
        Test.setMock(HttpCalloutMock.class, new QBTriggerCalloutMock());
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Trigger Handler Account' LIMIT 1];

        Account oldAcc = acc.clone(false, true, true, true);
        acc.Phone = '123456';

        Test.startTest();
        
        QBTriggerHandler.handleAccountTrigger(new List<Account>{ acc }, new Map<Id, Account>(), true, false);
        
        QBTriggerHandler.handleAccountTrigger(new List<Account>{ acc }, new Map<Id, Account>{ acc.Id => oldAcc }, false, true);
        
        Test.stopTest();

        System.assertEquals(false, QBTriggerHandler.isAccountProcessing);
    }

    @isTest
    static void testHandleProductTriggerInsertAndUpdate() {
        Test.setMock(HttpCalloutMock.class, new QBTriggerCalloutMock());
        Product2 prod = [SELECT Id, Name, ProductCode FROM Product2 WHERE Name = 'Trigger Handler Product' LIMIT 1];

        Product2 oldProd = prod.clone(false, true, true, true);
        prod.ProductCode = 'NEW-CODE';

        Test.startTest();
        
        // Insert Path Call
        QBTriggerHandler.handleProductTrigger(new List<Product2>{ prod }, new Map<Id, Product2>(), true, false);
        
        // Update Path Call
        QBTriggerHandler.handleProductTrigger(new List<Product2>{ prod }, new Map<Id, Product2>{ prod.Id => oldProd }, false, true);
        
        Test.stopTest();

        System.assertEquals(false, QBTriggerHandler.isProductProcessing);
    }
}