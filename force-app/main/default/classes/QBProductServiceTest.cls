@isTest
private class QBProductServiceTest {
    private static String lastCreateRequestBody;
    private static String lastUpdateRequestBody;
    private static String lastGetEndpoint;
    private static String lastPostEndpoint;

    private class QBProductServiceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String method = req.getMethod();

            if (method == 'GET' && endpoint.contains('/item/')) {
                lastGetEndpoint = req.getEndpoint();
                res.setStatusCode(200);
                res.setBody('{"Item":{"Id":"ITM-100","SyncToken":"0","Name":"Old","Type":"Inventory"}}');
                return res;
            }
            if (method == 'POST' && endpoint.contains('/item')) {
                lastPostEndpoint = req.getEndpoint();
                if (req.getBody() != null && req.getBody().contains('"Id":"ITM-100"')) {
                    lastUpdateRequestBody = req.getBody();
                } else {
                    lastCreateRequestBody = req.getBody();
                }
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
        insert new Product2(
            Name = 'QB Product Service Create',
            IsActive = true,
            Sale_Price__c = 25,
            Cost_Price__c = 10,
            Quantity_On_Hand__c = 3,
            Income_Account__c = '79',
            COGS_Account_Ref__c = 'Cost of Goods Sold',
            Asset_Account_Ref__c = 'Inventory Asset'
        );
        insert new Product2(
            Name = 'QB Product Service Update',
            IsActive = true,
            QuickbookID__c = 'ITM-100',
            Sale_Price__c = 30,
            Income_Account__c = '79'
        );
    }

    @isTest
    static void testCreatePathAddsRequiredQuickBooksItemFields() {
        lastCreateRequestBody = null;
        lastPostEndpoint = null;
        Test.setMock(HttpCalloutMock.class, new QBProductServiceMock());
        Product2 createProduct = [
            SELECT Id
            FROM Product2
            WHERE Name = 'QB Product Service Create'
            LIMIT 1
        ];

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ createProduct }, true);
        Test.stopTest();

        System.assertNotEquals(null, lastCreateRequestBody, 'Expected the create callout payload to be captured.');
        System.assertNotEquals(null, lastPostEndpoint, 'Expected the create endpoint to be captured.');
        System.assertEquals(-1, lastPostEndpoint.indexOf('?minorversion=65?minorversion=65'));

        Map<String, Object> requestMap = (Map<String, Object>)JSON.deserializeUntyped(lastCreateRequestBody);
        System.assertEquals('Inventory', (String)requestMap.get('Type'));
        System.assertEquals('79', String.valueOf(((Map<String, Object>)requestMap.get('IncomeAccountRef')).get('value')));
        System.assertEquals('80', String.valueOf(((Map<String, Object>)requestMap.get('ExpenseAccountRef')).get('value')));
        System.assertEquals('81', String.valueOf(((Map<String, Object>)requestMap.get('AssetAccountRef')).get('value')));
    }

    @isTest
    static void testUpdatePathUsesCleanItemEndpoints() {
        lastGetEndpoint = null;
        lastUpdateRequestBody = null;
        lastPostEndpoint = null;
        Test.setMock(HttpCalloutMock.class, new QBProductServiceMock());
        Product2 updateProduct = [
            SELECT Id, QuickbookID__c
            FROM Product2
            WHERE Name = 'QB Product Service Update'
            LIMIT 1
        ];

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ updateProduct }, false);
        Test.stopTest();

        System.assertNotEquals(null, lastGetEndpoint, 'Expected the item query endpoint to be captured.');
        System.assertNotEquals(null, lastUpdateRequestBody, 'Expected the update callout payload to be captured.');
        System.assertNotEquals(null, lastPostEndpoint, 'Expected the update endpoint to be captured.');
        System.assert(lastGetEndpoint.contains('/item/ITM-100'));
        System.assertEquals(-1, lastGetEndpoint.indexOf('?minorversion=65?minorversion=65'));
        System.assertEquals(-1, lastPostEndpoint.indexOf('?minorversion=65?minorversion=65'));
    }
}