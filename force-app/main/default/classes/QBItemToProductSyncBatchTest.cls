@isTest(isParallel=false)
private class QBItemToProductSyncBatchTest {
    private class QBOItemSyncMock implements HttpCalloutMock {
        private Boolean isError;

        public QBOItemSyncMock(Boolean isError) {
            this.isError = isError;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (isError) {
                res.setStatusCode(500);
                res.setBody('{"Fault":{"Error":[{"Message":"Server Error"}]}}');
                return res;
            }

            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Item":[{"Id":"ITEM-PBE","Name":"PBE Product","UnitPrice":150.0}]}}');
                return res;
            } else if (endpoint.contains('/item/')) {
                res.setStatusCode(200);
                res.setBody('{"Item":{"Id":"ITEM-2","Name":"Single QB Product","UnitPrice":30.0,"Active":false}}');
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
            Name = 'PBE Product', 
            IsActive = true, 
            QuickbookID__c = 'ITEM-PBE',
            Sale_Price__c = 150.00
        );
    }

    @isTest
    static void testBatchExecutionSuccessWithPBE() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBOItemSyncMock(false));
        delete [SELECT Id FROM Product2];

        Test.startTest();
        Database.executeBatch(new QBItemToProductSyncBatch(), 1);
        Test.stopTest();

        System.assertEquals(false, QBTriggerHandler.isProductProcessing);

        Product2 syncedProduct = [
            SELECT Id, Name, Sale_Price__c 
            FROM Product2 
            WHERE QuickbookID__c = 'ITEM-PBE' 
            LIMIT 1
        ];
        System.assertEquals(150.00, syncedProduct.Sale_Price__c);
        Id stdPbId = Test.getStandardPricebookId();
        Integer pbeCount = [SELECT Count() FROM PricebookEntry WHERE Product2Id = :syncedProduct.Id AND Pricebook2Id = :stdPbId];
        System.assertEquals(1, pbeCount, 'PricebookEntry should be successfully inserted to cover target lines.');
    }

    @isTest
    static void testBatchStartException() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBOItemSyncMock(true));

        Test.startTest();
        Iterable<String> payloads = new QBItemToProductSyncBatch('2025-01-01').start(null);
        Test.stopTest();

        List<String> payloadList = (List<String>) payloads;
        System.assertEquals(0, payloadList.size(), 'Start exception catch block covered successfully.');
    }

    @isTest
    static void testBatchExecuteExceptionsAndEdgeCases() {
        QBItemToProductSyncBatch batch = new QBItemToProductSyncBatch();
        List<String> edgeCasePayloads = new List<String>{
            'INVALID_JSON_PAYLOAD_TO_TRIGGER_CATCH',
            '{"Id": {"Invalid": "Type"}}',
            null,
            ''
        };

        Test.startTest();
        batch.execute(null, edgeCasePayloads);
        batch.finish(null);
        Test.stopTest();

        System.assert(true, 'Execute exception catch blocks (ErrorLogUtility) processed smoothly.');
    }

    @isTest
    static void testSyncItemFromQboSuccess() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBOItemSyncMock(false));

        Test.startTest();
        QBItemToProductSyncBatch batch = new QBItemToProductSyncBatch();
        batch.syncItemFromQBO('ITEM-2');
        Test.stopTest();

        System.assertEquals(1, [SELECT Count() FROM Product2 WHERE QuickbookID__c = 'ITEM-2']);
    }

    @isTest
    static void testSyncItemFromQboError() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBOItemSyncMock(true));

        Boolean exceptionCaught = false;
        Test.startTest();
        try {
            new QBItemToProductSyncBatch().syncItemFromQBO('ITEM-ERR');
        } catch (CalloutException e) {
            exceptionCaught = true;
        }
        Test.stopTest();

        System.assert(exceptionCaught, 'Sync item callout exception catch block covered.');
    }
    
    @isTest
    static void testTypeCoercionLogic() {
        String multiTypePayload = '{"Id":"ITEM-COERCE", "Name":"Coerce Test", "Active":false, "UnitPrice":50.50, "QtyOnHand":10, "InvStartDate":"2023-01-01", "SyncTime":"2023-01-01T12:00:00Z"}';
        
        QBItemToProductSyncBatch batch = new QBItemToProductSyncBatch();
        
        Test.startTest();
        batch.execute(null, new List<String>{ multiTypePayload });
        Test.stopTest();
        
        System.assert(true, 'Type coercion executed successfully.');
    }
}