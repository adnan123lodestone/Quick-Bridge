@isTest(isParallel=false)
private class QBInvoiceToOrderSyncBatchTest {

    @testSetup
    static void setupData() {
        Connector_Instance__c instance = new Connector_Instance__c(
            Name = 'QuickBooks Online',
            Connector_Key__c = 'qbo',
            Connector_Label__c = 'QuickBooks Online',
            Active__c = true,
            Environment__c = 'Sandbox',
            Entitlement_Status__c = 'Active',
            Health_Status__c = 'Unknown',
            Named_Credential__c = 'QuickBookSandbox'
        );
        insert instance;

        Connector_Config_Value__c realmConfig = new Connector_Config_Value__c(
            Name = 'qbo.RealmId',
            Connector_Instance__c = instance.Id,
            Connector_Key__c = 'qbo',
            Field_Key__c = 'QuickBooks_Realm_ID__c',
            Value__c = '1234567890',
            Is_Secret_Reference__c = false
        );
        insert realmConfig;

        Connector_Config_Value__c activeConfig = new Connector_Config_Value__c(
            Name = 'qbo.Active',
            Connector_Instance__c = instance.Id,
            Connector_Key__c = 'qbo',
            Field_Key__c = 'QuickBooks_Is_Active__c',
            Value__c = 'true',
            Is_Secret_Reference__c = false
        );
        insert activeConfig;
    }

    private class QBInvoiceToOrderMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Invoice":[{"Id":"INV-1","TxnDate":"2025-01-15","CustomerMemo":{"value":"Invoice memo"},"CustomerRef":{"value":"QB-CUST-1","name":"Sync Customer"},"Line":[{"Id":"1","DetailType":"SalesItemLineDetail","Description":"Line 1","SalesItemLineDetail":{"Qty":2,"UnitPrice":10,"ItemRef":{"value":"QB-ITEM-1","name":"Sync Product"}}}],"BillAddr":{"Line1":"B1","City":"C1","CountrySubDivisionCode":"S1","PostalCode":"111","Country":"US"}}]}}');
                return res;
            }
            if (endpoint.contains('/invoice/inv-1')) {
                res.setStatusCode(200);
                res.setBody('{"Invoice":{"Id":"INV-1","TxnDate":"2025-01-15","CustomerMemo":{"value":"Invoice memo"},"CustomerRef":{"value":"QB-CUST-1","name":"Sync Customer"},"Line":[{"Id":"1","DetailType":"SalesItemLineDetail","Description":"Line 1","SalesItemLineDetail":{"Qty":2,"UnitPrice":10,"ItemRef":{"value":"QB-ITEM-1","name":"Sync Product"}}}]}}');
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    private class ErrorHttpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"Fault":{"Error":[{"Message":"Bad Request"}]}}');
            return res;
        }
    }

    private class QBInvoiceToOrderUpdateMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Invoice":[{"Id":"INV-1","TxnDate":"2025-01-15","CustomerMemo":{"value":"Updated memo"},"CustomerRef":{"value":"QB-CUST-1","name":"Sync Customer"},"Line":[{"Id":"1","DetailType":"SalesItemLineDetail","Description":"Line 1 Updated","SalesItemLineDetail":{"Qty":5,"UnitPrice":15,"ItemRef":{"value":"QB-ITEM-1","name":"Sync Product"}}}]}]}}');
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    private class ExistingOrderMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Invoice":[{"Id":"EXIST-ORDER-1","TxnDate":"2025-01-15","CustomerRef":{"value":"QB-CUST-EXIST","name":"Existing Order Customer"},"Line":[{"Id":"L1","DetailType":"SalesItemLineDetail","Description":"Item for existing order","SalesItemLineDetail":{"Qty":3,"UnitPrice":25,"ItemRef":{"value":"QB-ITEM-1","name":"Sync Product"}}}]}]}}');
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    private class NewProductMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Invoice":[{"Id":"INV-NEW","TxnDate":"2025-01-15","CustomerRef":{"value":"QB-CUST-2","name":"New Customer"},"Line":[{"Id":"L1","DetailType":"SalesItemLineDetail","Description":"Brand new product","SalesItemLineDetail":{"Qty":1,"UnitPrice":99.99,"ItemRef":{"value":"QB-NEW-PROD","name":"New Product"}}}]}]}}');
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @isTest
    static void testDefaultConstructorAndStart() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBInvoiceToOrderMock());
        Test.startTest();
        QBInvoiceToOrderSyncBatch batch = new QBInvoiceToOrderSyncBatch();
        Database.executeBatch(batch, 1);
        Test.stopTest();
    }

    @isTest
    static void testStartErrorCallout() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new ErrorHttpMock());
        Test.startTest();
        QBInvoiceToOrderSyncBatch batch = new QBInvoiceToOrderSyncBatch('2025-01-01');
        Database.executeBatch(batch, 1);
        Test.stopTest();
    }

    @isTest
    static void testInitialSyncBatch() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBInvoiceToOrderMock());

        Test.startTest();
        QBInvoiceToOrderSyncBatch batch = new QBInvoiceToOrderSyncBatch('2025-01-01');
        Database.executeBatch(batch, 1);
        Test.stopTest();

        List<Account> accs = [SELECT Id, Name FROM Account WHERE QuickbookID__c = 'QB-CUST-1'];
        System.assert(!accs.isEmpty());

        List<Order> ords = [SELECT Id, QuickbookID__c, Description FROM Order WHERE QuickbookID__c = 'INV-1'];
        System.assert(!ords.isEmpty());
    }

    @isTest
    static void testUpdateSyncBatch() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBInvoiceToOrderUpdateMock());

        Test.startTest();
        QBInvoiceToOrderSyncBatch batch = new QBInvoiceToOrderSyncBatch('2025-01-01');
        Database.executeBatch(batch, 1);
        Test.stopTest();
    }

    @isTest
    static void testNewProductSyncBatch() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new NewProductMock());

        Test.startTest();
        QBInvoiceToOrderSyncBatch batch = new QBInvoiceToOrderSyncBatch('2025-01-01');
        Database.executeBatch(batch, 1);
        Test.stopTest();
    }

    @isTest
    static void testExistingOrderNotInMap() {
        Account testAccount = new Account(Name = 'Existing Order Account', QuickbookID__c = 'QB-CUST-EXIST');
        insert testAccount;

        Order existingOrder = new Order(
            AccountId = testAccount.Id,
            QuickbookID__c = 'EXIST-ORDER-1',
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert existingOrder;

        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new ExistingOrderMock());

        Test.startTest();
        Database.executeBatch(new QBInvoiceToOrderSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        Order refreshedOrder = [SELECT Id, QuickbookID__c FROM Order WHERE Id = :existingOrder.Id];
        System.assertEquals('EXIST-ORDER-1', refreshedOrder.QuickbookID__c);
    }

    @isTest
    static void testProcessSingleInvoice() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBInvoiceToOrderMock());

        Test.startTest();
        QBInvoiceToOrderSyncBatch.processSingleInvoice('INV-1');
        Test.stopTest();
    }

    @isTest
    static void testProcessSingleInvoiceError() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new ErrorHttpMock());

        Boolean threw = false;
        Test.startTest();
        try {
            QBInvoiceToOrderSyncBatch.processSingleInvoice('INV-ERR');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }
}