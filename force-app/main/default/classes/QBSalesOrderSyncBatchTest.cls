@isTest(isParallel=false)
private class QBSalesOrderSyncBatchTest {

    private static String lastBody;

    @testSetup
    static void setupData() {
        QuickBooksAuthHandler.configureConnectionForTest('1234567890', 'QuickBookSandbox', null);
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

    private class CaptureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            lastBody = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"Estimate":{"Id":"999","SyncToken":"0","Line":[' +
                '{"Id":"1","DetailType":"SalesItemLineDetail"}]},' +
                '"Invoice":{"Id":"999","SyncToken":"0","Line":[' +
                '{"Id":"1","DetailType":"SalesItemLineDetail"}]}}');
            return res;
        }
    }

    private class FailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"Fault":{"Error":[{"Message":"Server error"}]}}');
            return res;
        }
    }

    private static String qboIdField(String sObjectName) {
        Map<String, Schema.SObjectField> flds = sObjectName == 'Account'
            ? Schema.SObjectType.Account.fields.getMap()
            : sObjectName == 'Product2'
                ? Schema.SObjectType.Product2.fields.getMap()
                : Schema.SObjectType.Order.fields.getMap();
        for (String key : flds.keySet()) {
            if (key.endsWith('quickbookid__c')) return flds.get(key).getDescribe().getName();
        }
        return 'QuickbookID__c';
    }

    private static String syncTokenField(String sObjectName) {
        Map<String, Schema.SObjectField> flds = Schema.SObjectType.Order.fields.getMap();
        for (String key : flds.keySet()) {
            if (key.endsWith('synctoken__c')) return flds.get(key).getDescribe().getName();
        }
        return 'SyncToken__c';
    }

    private static Order queryOrder(Id orderId) {
        String qField = qboIdField('Order');
        String sField = syncTokenField('Order');
        String query = 'SELECT Id, ' + qField + ', ' + sField + ' FROM Order WHERE Id = :orderId';
        return (Order) Database.query(query)[0];
    }

    private static String getQboIdVal(Order ord) {
        return (String) ord.get(qboIdField('Order'));
    }

    private static String getSyncTokenVal(Order ord) {
        return (String) ord.get(syncTokenField('Order'));
    }

    private static Account makeAccount(String name, String qboId) {
        Account acc = new Account(Name = name);
        if (String.isNotBlank(qboId)) {
            acc.put(qboIdField('Account'), qboId);
        }
        insert acc;
        return acc;
    }

    private static Product2 makeProduct(String name, String qboId) {
        Product2 prod = new Product2(Name = name, IsActive = true);
        if (String.isNotBlank(qboId)) {
            prod.put(qboIdField('Product2'), qboId);
        }
        insert prod;
        return prod;
    }

    private static Order createOrderWithLineItem(Account acc, Product2 prod, String status, String orderQboId) {
        QuickBooksAuthHandler.configureConnectionForTest('1234567890', 'QuickBookSandbox', null);
        Id pricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = prod.Id,
            UnitPrice = 10,
            IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = pricebookId,
            Description = 'Invoice memo'
        );
        if (String.isNotBlank(orderQboId)) {
            ord.put(qboIdField('Order'), orderQboId);
        }
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 10,
            Product2Id = prod.Id
        );
        insert oi;

        if (status == 'Activated') {
            ord.Status = 'Activated';
            update ord;
        }

        return queryOrder(ord.Id);
    }

    // =========================================================================
    // SUCCESS TESTS
    // =========================================================================

    @isTest
    static void testDottedLineMappingsProduceValidQboJson() {
        Account acc = makeAccount('Acme', '87');
        Product2 prod = makeProduct('Widget', '22');
        Order ord = createOrderWithLineItem(acc, prod, 'Draft', null);

        Test.setMock(HttpCalloutMock.class, new CaptureMock());
        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        if (lastBody != null) {
            System.assert(!lastBody.contains('Line.SalesItemLineDetail'), 'No dotted keys: ' + lastBody);
            System.assert(!lastBody.contains('"TotalAmt"'), 'TotalAmt should be omitted');
        }

        Order synced = queryOrder(ord.Id);
        System.assertEquals('999', getQboIdVal(synced), 'Order should store QBO id');
    }

    @isTest
    static void testDynamicMappingFieldsDoNotCauseSObjectException() {
        Account acc = makeAccount('Acme', '87');
        Product2 prod = makeProduct('Widget', '22');
        Order ord = createOrderWithLineItem(acc, prod, 'Draft', null);
        ord.Description = 'Test memo';
        update ord;

        Test.setMock(HttpCalloutMock.class, new CaptureMock());
        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        Order synced = queryOrder(ord.Id);
        System.assertEquals('999', getQboIdVal(synced), 'Callout must succeed');
    }

    // =========================================================================
    // MISSING ID TESTS
    // =========================================================================

    @isTest
    static void testMissingAccountQboId_skipsCalloutAndEnqueuesAccountUpsert() {
        Account acc = makeAccount('No QBO Account', null);
        Product2 prod = makeProduct('Widget', '22');
        Order ord = createOrderWithLineItem(acc, prod, 'Draft', null);

        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        Order unsynced = queryOrder(ord.Id);
        System.assert(String.isBlank(getQboIdVal(unsynced)), 'Order must not get QBO id');

        List<Integration_Work_Item__c> work = [
            SELECT Operation__c FROM Integration_Work_Item__c
            WHERE Source_Record_Id__c = :String.valueOf(acc.Id) AND Operation__c = 'AccountUpsert'
        ];
        System.assertEquals(1, work.size(), 'AccountUpsert must be queued');

        List<Error_Log__c> logs = [SELECT Id FROM Error_Log__c WHERE Source_Record_Id__c = :String.valueOf(ord.Id)];
        System.assert(!logs.isEmpty(), 'Error log must be written');
    }

    @isTest
    static void testMissingProductQboId_skipsCalloutAndEnqueuesProductUpsert() {
        Account acc = makeAccount('Good Account', '42');
        Product2 prod = makeProduct('Unsynced Widget', null);
        Order ord = createOrderWithLineItem(acc, prod, 'Draft', null);

        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        Order unsynced = queryOrder(ord.Id);
        System.assert(String.isBlank(getQboIdVal(unsynced)), 'Order must not get QBO id');

        List<Integration_Work_Item__c> work = [
            SELECT Operation__c FROM Integration_Work_Item__c
            WHERE Source_Record_Id__c = :String.valueOf(prod.Id) AND Operation__c = 'ProductUpsert'
        ];
        System.assertEquals(1, work.size(), 'ProductUpsert must be queued');

        List<Error_Log__c> logs = [SELECT Id FROM Error_Log__c WHERE Source_Record_Id__c = :String.valueOf(ord.Id)];
        System.assert(!logs.isEmpty(), 'Error log must be written');
    }

    // =========================================================================
    // STATUS BRANCH TESTS
    // =========================================================================

    @isTest
    static void testActivatedOrderCreatesInvoice() {
        Account acc = makeAccount('Acme', '87');
        Product2 prod = makeProduct('Widget', '22');
        // Order has an existing estimate QBO Id, but when activated it will convert to invoice
        Order ord = createOrderWithLineItem(acc, prod, 'Activated', 'OLD-ESTIMATE-123');

        Test.setMock(HttpCalloutMock.class, new CaptureMock());
        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        Order synced = queryOrder(ord.Id);
        System.assertEquals('999', getQboIdVal(synced), 'Order should get new QBO invoice Id');
        System.assertEquals('0', getSyncTokenVal(synced), 'SyncToken should be updated');
    }

    @isTest
    static void testDraftOrderAsEstimateWhenConfigTrue() {
        Connector_Instance__c instance = [SELECT Id FROM Connector_Instance__c LIMIT 1];
        Connector_Config_Value__c setting = new Connector_Config_Value__c(
            Name = 'qbo.Map_Draft_Orders_as_Estimates__c',
            Connector_Instance__c = instance.Id,
            Connector_Key__c = 'qbo',
            Field_Key__c = 'Map_Draft_Orders_as_Estimates__c',
            Value__c = 'true',
            Is_Secret_Reference__c = false
        );
        insert setting;

        Account acc = makeAccount('Acme', '87');
        Product2 prod = makeProduct('Widget', '22');
        Order ord = createOrderWithLineItem(acc, prod, 'Draft', null);

        Test.setMock(HttpCalloutMock.class, new CaptureMock());
        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        Order synced = queryOrder(ord.Id);
        System.assertEquals('999', getQboIdVal(synced));
    }

    // =========================================================================
    // UPDATE PATH TESTS
    // =========================================================================

    @isTest
    static void testUpdatePathWithExistingQboId() {
        Account acc = makeAccount('Acme', '87');
        Product2 prod = makeProduct('Widget', '22');
        Order ord = createOrderWithLineItem(acc, prod, 'Draft', 'OLD-123');

        Test.setMock(HttpCalloutMock.class, new CaptureMock());
        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        Order synced = queryOrder(ord.Id);
        System.assertEquals('999', getQboIdVal(synced), 'Update request should process cleanly');
    }

    // =========================================================================
    // FAILURE TESTS
    // =========================================================================

    @isTest
    static void testQboCalloutFailureLogsError() {
        Account acc = makeAccount('Acme', '87');
        Product2 prod = makeProduct('Widget', '22');
        Order ord = createOrderWithLineItem(acc, prod, 'Draft', null);

        Test.setMock(HttpCalloutMock.class, new FailMock());
        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        List<Error_Log__c> logs = [SELECT Id FROM Error_Log__c WHERE Source_Record_Id__c = :String.valueOf(ord.Id)];
        System.assert(!logs.isEmpty(), 'Error log must be written for callout failure');
        Order unsynced = queryOrder(ord.Id);
        System.assert(String.isBlank(getQboIdVal(unsynced)), 'Order should not be updated');
    }

    @isTest
    static void testOrderWithoutLineItemsIsSkipped() {
        Account acc = makeAccount('Acme', '87');
        Product2 prod = makeProduct('Widget', '22');
        Id pricebookId = Test.getStandardPricebookId();
        Order ord = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Pricebook2Id = pricebookId);
        insert ord;

        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        List<Integration_Work_Item__c> workForOrder = [
            SELECT Id FROM Integration_Work_Item__c
            WHERE Source_Record_Id__c = :String.valueOf(ord.Id)
        ];
        System.assertEquals(0, workForOrder.size(), 'No work items should be queued for the order');

        Order stillDraft = queryOrder(ord.Id);
        System.assert(String.isBlank(getQboIdVal(stillDraft)), 'Order should have no QBO Id');
    }
}