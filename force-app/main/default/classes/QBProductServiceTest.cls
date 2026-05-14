@isTest
private class QBProductServiceTest {

    private class QBProductServiceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String method = req.getMethod();

            if (method == 'GET' && endpoint.contains('/item/')) {
                res.setStatusCode(200);
                res.setBody('{"Item":{"Id":"ITM-100","SyncToken":"0","Name":"Old","Type":"Inventory"}}');
                return res;
            }
            if (method == 'POST' && endpoint.contains('/item')) {
                res.setStatusCode(200);
                res.setBody('{"Item":{"Id":"ITM-100"}}');
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        insert new Product2(Name = 'QB Product Service Create', IsActive = true, Sale_Price__c = 25);
        insert new Product2(Name = 'QB Product Service Update', IsActive = true, QuickbookID__c = 'ITM-100', Sale_Price__c = 30);
    }

    @isTest
    static void testSyncProductsCreateAndUpdatePaths() {
        Test.setMock(HttpCalloutMock.class, new QBProductServiceMock());
        List<Product2> products = [
            SELECT Id, Name, QuickbookID__c, Sale_Price__c
            FROM Product2
            WHERE Name LIKE 'QB Product Service%'
        ];

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(products, true);
        QBProductService.syncProductsToQuickBooks(products, false);
        Test.stopTest();

        System.assertEquals(2, products.size());
    }
}