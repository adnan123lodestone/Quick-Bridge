@isTest
private class QBItemToProductSyncBatchTest {

    private class QBItemBatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Item":[{"Id":"ITEM-1"}]}}');
                return res;
            }

            if (endpoint.contains('/item/item-1')) {
                res.setStatusCode(200);
                res.setBody('{"Item":{"Id":"ITEM-1","Name":"QB Product","Description":"Desc","Sku":"SKU-1","Active":true,"UnitPrice":25.5,"PurchaseCost":11.1,"QtyOnHand":5}}');
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        insert new Product2(Name = 'Seed Product', IsActive = true);
    }

    @isTest
    static void testBatchStartExecuteFinish() {
        Test.setMock(HttpCalloutMock.class, new QBItemBatchMock());

        Test.startTest();
        Database.executeBatch(new QBItemToProductSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        System.assertEquals(false, QBTriggerHandler.isProductProcessing);

        Product2 syncedProduct = [
            SELECT Id, Name, QuickbookID__c, ProductCode, Sale_Price__c
            FROM Product2
            WHERE QuickbookID__c = 'ITEM-1'
            LIMIT 1
        ];
        System.assertEquals('QB Product', syncedProduct.Name);
        System.assertEquals('ITEM-1', syncedProduct.QuickbookID__c);
        System.assertEquals('Desc', syncedProduct.ProductCode);
        System.assertEquals(25.5, syncedProduct.Sale_Price__c);
    }
}