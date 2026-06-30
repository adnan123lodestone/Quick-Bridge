@isTest
private class QBSalesOrderSyncBatchTest {

    private static String lastBody;

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
        Schema.SObjectField tok = flds.get('QuickBridgeTLG__quickbookid__c');
        if (tok != null) return tok.getDescribe().getName();
        tok = flds.get('quickbookid__c');
        return tok != null ? tok.getDescribe().getName() : 'QuickbookID__c';
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
            Pricebook2Id = pricebookId
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

        return [SELECT Id, AccountId, Account.QuickbookID__c, Status, EffectiveDate, Pricebook2Id,
                       (SELECT Id, Quantity, UnitPrice, Description, TotalPrice,
                               Product2Id, Product2.QuickbookID__c, QB_LineiTemID__c
                        FROM OrderItems)
                FROM Order WHERE Id = :ord.Id];
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

        System.assertNotEquals(null, lastBody, 'Request body should not be null');
        System.assert(!lastBody.contains('Line.SalesItemLineDetail'), 'No dotted keys: ' + lastBody);
        System.assert(!lastBody.contains('"TotalAmt"'), 'TotalAmt should be omitted');
        System.assert(lastBody.contains('"Qty"'), 'Qty property missing');
        System.assert(lastBody.contains('"UnitPrice"'), 'UnitPrice property missing');
        System.assert(lastBody.contains('"ItemRef"'), 'ItemRef property missing');

        Order synced = [SELECT QuickbookID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('999', synced.QuickbookID__c, 'Order should store QBO id');
    }

    @isTest
    static void testDynamicMappingFieldsDoNotCauseSObjectException() {
        Account acc = makeAccount('Acme', '87');
        Product2 prod = makeProduct('Widget', '22');
        Order ord = createOrderWithLineItem(acc, prod, 'Draft', null);
        ord.Description = 'Test memo';
        update ord;
        ord = [SELECT Id, AccountId, Account.QuickbookID__c, Status, EffectiveDate, Pricebook2Id, Description,
                      (SELECT Id, Quantity, UnitPrice, Description, TotalPrice,
                              Product2Id, Product2.QuickbookID__c, QB_LineiTemID__c
                       FROM OrderItems)
               FROM Order WHERE Id = :ord.Id];

        Test.setMock(HttpCalloutMock.class, new CaptureMock());
        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        System.assertNotEquals(null, lastBody, 'Callout must succeed');
        System.assert(lastBody.contains('"TxnDate"'), 'EffectiveDate mapped to TxnDate');
        System.assert(lastBody.contains('"CustomerMemo"'), 'Description mapped to CustomerMemo');
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

        Order unsynced = [SELECT QuickbookID__c FROM Order WHERE Id = :ord.Id];
        System.assert(String.isBlank(unsynced.QuickbookID__c), 'Order must not get QBO id');

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

        Order unsynced = [SELECT QuickbookID__c FROM Order WHERE Id = :ord.Id];
        System.assert(String.isBlank(unsynced.QuickbookID__c), 'Order must not get QBO id');

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
        ord.SyncToken__c = '5';
        update ord;

        Test.setMock(HttpCalloutMock.class, new CaptureMock());
        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        System.assertNotEquals(null, lastBody, 'Invoice callout should be made');
        // For activated order (conversion), the batch does NOT send the existing Id
        System.assert(!lastBody.contains('"Id":"OLD-ESTIMATE-123"'), 'Existing Id should NOT be sent for conversion');
        // Verify it's an invoice request (basic structure)
        System.assert(lastBody.contains('"CustomerRef"'), 'Invoice should have CustomerRef');
        System.assert(lastBody.contains('"Line"'), 'Invoice should have Line items');

        Order synced = [SELECT QuickbookID__c, SyncToken__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('999', synced.QuickbookID__c, 'Order should get new QBO invoice Id');
        System.assertEquals('0', synced.SyncToken__c, 'SyncToken should be updated');
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

        System.assertNotEquals(null, lastBody, 'Estimate callout should be made');
        Order synced = [SELECT QuickbookID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('999', synced.QuickbookID__c);
    }

    // =========================================================================
    // UPDATE PATH TESTS
    // =========================================================================

    @isTest
    static void testUpdatePathWithExistingQboId() {
        Account acc = makeAccount('Acme', '87');
        Product2 prod = makeProduct('Widget', '22');
        Order ord = createOrderWithLineItem(acc, prod, 'Draft', 'OLD-123');
        ord.SyncToken__c = '5';
        update ord;

        Test.setMock(HttpCalloutMock.class, new CaptureMock());
        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        System.assertNotEquals(null, lastBody, 'Update request should be sent');
        System.assert(lastBody.contains('"Id":"OLD-123"'), 'Existing Id should be in request');
        System.assert(lastBody.contains('"SyncToken":"5"'), 'SyncToken should be in request');
        System.assert(lastBody.contains('"sparse":true'), 'Update should be sparse');
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
        Order unsynced = [SELECT QuickbookID__c FROM Order WHERE Id = :ord.Id];
        System.assert(String.isBlank(unsynced.QuickbookID__c), 'Order should not be updated');
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

        Order stillDraft = [SELECT QuickbookID__c FROM Order WHERE Id = :ord.Id];
        System.assert(String.isBlank(stillDraft.QuickbookID__c), 'Order should have no QBO Id');
    }
}