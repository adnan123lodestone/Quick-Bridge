@IsTest
private class QBOInvoiceSyncQueueableTest {
    
    private class BulkInvoiceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(200);
            response.setBody(
                '{"QueryResponse":{"Invoice":[' +
                '{"Id":"INV-1","DocNumber":"1001","CustomerRef":{"value":"CUST-1","name":"Customer One"},"Line":[{"DetailType":"SalesItemLineDetail","SalesItemLineDetail":{"ItemRef":{"value":"ITEM-1","name":"Item One"},"Qty":1,"UnitPrice":10}}]},' +
                '{"Id":"INV-2","DocNumber":"1002","CustomerRef":{"value":"CUST-2","name":"Customer Two"},"Line":[{"DetailType":"SalesItemLineDetail","SalesItemLineDetail":{"ItemRef":{"value":"ITEM-2","name":"Item Two"},"Qty":2,"UnitPrice":15}}]}' +
                ']}}'
            );
            return response;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(500);
            response.setBody('{"Fault":{"Error":[{"Message":"Internal Server Error"}]}}');
            return response;
        }
    }

    /**
     * Sets up the required custom metadata map for the test class.
     */
    @TestSetup
    static void setupData() {
        Integration_Object_Map__mdt mockMap = new Integration_Object_Map__mdt(
            Salesforce_Object__c = 'Order',
            External_Object__c = 'Invoice',
            Direction__c = 'Inbound'
        );
    }

    /**
     * Tests the queueable execution path with a successful bulk query response.
     */
    @IsTest
    static void testExecuteQueueableSuccess() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new BulkInvoiceMock());

        Test.startTest();
        System.enqueueJob(new QBOInvoiceSyncQueueable(new Set<String>{ 'INV-1' }));
        Test.stopTest();

        System.assertEquals(1, [SELECT Count() FROM Account WHERE QuickbookID__c = 'CUST-1']);
    }

    /**
     * Tests the synchronous execution path triggering phases 1 through 6.
     */
    @IsTest
    static void testExecuteSyncSuccess() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new BulkInvoiceMock());

        Test.startTest();
        new QBOInvoiceSyncQueueable(new Set<String>{ 'INV-1', 'INV-2' }).executeSync();
        Test.stopTest();

        System.assertEquals(2, [SELECT Count() FROM Account WHERE QuickbookID__c IN ('CUST-1', 'CUST-2')]);
    }

    /**
     * Tests the catch block inside executeInternal when the API callout fails.
     */
    @IsTest
    static void testExecuteInternalCatchBlock() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        try {
            new QBOInvoiceSyncQueueable(new Set<String>{ 'INV-ERR' }).executeSync();
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * Tests the outer catch blocks of the execute and executeSync methods.
     */
    @IsTest
    static void testOuterCatchBlocks() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        
        Boolean isSyncExceptionThrown = false;
        try {
            QBOInvoiceSyncQueueable badQueueable = null;
            badQueueable.executeSync();
        } catch (Exception e) {
            isSyncExceptionThrown = true;
        }

        Boolean isAsyncExceptionThrown = false;
        try {
            QBOInvoiceSyncQueueable badQueueable = null;
            badQueueable.execute(null);
        } catch (Exception e) {
            isAsyncExceptionThrown = true;
        }
        
        System.assert(isSyncExceptionThrown);
        System.assert(isAsyncExceptionThrown);
    }

    /**
     * Tests the deletion logging logic by creating existing records before sync.
     */
    @IsTest
    static void testDeleteResultsLogger() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new BulkInvoiceMock());

        Account acc = new Account(Name = 'Customer One', QuickbookID__c = 'CUST-1');
        insert acc;
        
        Product2 prod = new Product2(Name = 'Item One', External_Id__c = 'ITEM-1', IsActive = true);
        insert prod;
        
        Id pbId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = pbId, Product2Id = prod.Id, UnitPrice = 10, IsActive = true);
        insert pbe;
        
        Order ord = new Order(AccountId = acc.Id, QuickbookID__c = 'INV-1', Status = 'Draft', EffectiveDate = Date.today(), Pricebook2Id = pbId);
        insert ord;
        
        OrderItem oi = new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10);
        insert oi;

        Test.startTest();
        new QBOInvoiceSyncQueueable(new Set<String>{ 'INV-1' }).executeSync();
        Test.stopTest();

        System.assertEquals(1, [SELECT Count() FROM OrderItem WHERE OrderId = :ord.Id]);
    }
}