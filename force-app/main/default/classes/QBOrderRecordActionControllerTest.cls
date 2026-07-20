@isTest
private class QBOrderRecordActionControllerTest {

    private class QBOrderActionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String method = req.getMethod();

            if (method == 'GET' && endpoint.contains('/invoice/')) {
                res.setStatusCode(200);
                res.setBody('{"Invoice":{"Id":"999","SyncToken":"1","CustomerRef":{"value":"ACC-1"},"Line":[{"Id":"1","DetailType":"SalesItemLineDetail","Amount":10.00,"SalesItemLineDetail":{"Qty":1,"UnitPrice":10.00,"ItemRef":{"value":"PROD-1","name":"Widget"}}}]}}');
                return res;
            }
            if (method == 'GET' && endpoint.contains('/estimate/')) {
                res.setStatusCode(200);
                res.setBody('{"Estimate":{"Id":"999","SyncToken":"1","CustomerRef":{"value":"ACC-1"},"Line":[{"Id":"1","DetailType":"SalesItemLineDetail","Amount":10.00,"SalesItemLineDetail":{"Qty":1,"UnitPrice":10.00,"ItemRef":{"value":"PROD-1","name":"Widget"}}}]}}');
                return res;
            }
            if (method == 'POST' && (endpoint.contains('/invoice') || endpoint.contains('/estimate'))) {
                res.setStatusCode(200);
                String objName = endpoint.contains('/estimate') ? 'Estimate' : 'Invoice';
                res.setBody('{"' + objName + '":{"Id":"999","SyncToken":"1","Line":[{"Id":"1","DetailType":"SalesItemLineDetail"}]}}');
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    private class QBOrderErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('{"Fault":{"Error":[{"Message":"Internal Server Error"}]}}');
            return res;
        }
    }

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

        Connector_Config_Value__c draftConfig = new Connector_Config_Value__c(
            Name = 'qbo.Map_Draft_Orders_as_Estimates__c',
            Connector_Instance__c = instance.Id,
            Connector_Key__c = 'qbo',
            Field_Key__c = 'Map_Draft_Orders_as_Estimates__c',
            Value__c = 'true',
            Is_Secret_Reference__c = false
        );
        insert draftConfig;

        // Setup Accounts
        QBTriggerHandler.isAccountProcessing = true;
        Account accSynced = new Account(Name = 'Synced Account', QuickbookID__c = 'ACC-1');
        Account accUnsynced = new Account(Name = 'Unsynced Account');
        insert new List<Account>{ accSynced, accUnsynced };
        QBTriggerHandler.isAccountProcessing = false;

        // Setup Products
        Product2 prodSynced = new Product2(Name = 'Widget Synced', QuickbookID__c = 'PROD-1', IsActive = true);
        Product2 prodUnsynced = new Product2(Name = 'Widget Unsynced', IsActive = true);
        insert new List<Product2>{ prodSynced, prodUnsynced };

        // Setup Standard Pricebook Entries
        Id stdPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbeSynced = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id = prodSynced.Id,
            UnitPrice = 10,
            IsActive = true
        );
        PricebookEntry pbeUnsynced = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id = prodUnsynced.Id,
            UnitPrice = 10,
            IsActive = true
        );
        insert new List<PricebookEntry>{ pbeSynced, pbeUnsynced };

        // Setup Orders
        Order ordDraft = new Order(
            AccountId = accSynced.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPricebookId
        );
        Order ordUnsyncedAcc = new Order(
            AccountId = accUnsynced.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPricebookId
        );
        insert new List<Order>{ ordDraft, ordUnsyncedAcc };

        // Setup OrderItems
        OrderItem oiDraft = new OrderItem(
            OrderId = ordDraft.Id,
            PricebookEntryId = pbeSynced.Id,
            Quantity = 1,
            UnitPrice = 10,
            Product2Id = prodSynced.Id
        );
        OrderItem oiUnsyncedAcc = new OrderItem(
            OrderId = ordUnsyncedAcc.Id,
            PricebookEntryId = pbeSynced.Id,
            Quantity = 1,
            UnitPrice = 10,
            Product2Id = prodSynced.Id
        );
        insert new List<OrderItem>{ oiDraft, oiUnsyncedAcc };
    }

    private static void configureQuickBooksConnection() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
    }

    @isTest
    static void testSyncToQuickBooks_Draft_AsEstimate() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBOrderActionMock());
        Order ord = [SELECT Id FROM Order WHERE Account.Name = 'Synced Account' LIMIT 1];

        Test.startTest();
        QBOrderRecordActionController.ActionResponse response = QBOrderRecordActionController.syncToQuickBooks(ord.Id);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('999', response.quickBooksId);
        System.assert(response.message.contains('Estimate'));
    }

    @isTest
    static void testSyncToQuickBooks_Activated_AsInvoice() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBOrderActionMock());
        Order ord = [SELECT Id FROM Order WHERE Account.Name = 'Synced Account' LIMIT 1];
        ord.Status = 'Activated';
        update ord;

        Test.startTest();
        QBOrderRecordActionController.ActionResponse response = QBOrderRecordActionController.syncToQuickBooks(ord.Id);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('999', response.quickBooksId);
        System.assert(response.message.contains('Invoice'));
    }

    @isTest
    static void testSyncToQuickBooks_MissingAccountQboId() {
        configureQuickBooksConnection();
        Order ord = [SELECT Id FROM Order WHERE Account.Name = 'Unsynced Account' LIMIT 1];

        Test.startTest();
        try {
            QBOrderRecordActionController.syncToQuickBooks(ord.Id);
            System.assert(false, 'Expected preflight check to throw exception for missing Account QuickBooks ID.');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException thrown as expected.');
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncToQuickBooks_MissingProductQboId() {
        configureQuickBooksConnection();
        Order ord = [SELECT Id FROM Order WHERE Account.Name = 'Synced Account' LIMIT 1];
        Product2 prodUnsynced = [SELECT Id FROM Product2 WHERE Name = 'Widget Unsynced' LIMIT 1];
        PricebookEntry pbeUnsynced = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prodUnsynced.Id LIMIT 1];

        OrderItem newOi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbeUnsynced.Id,
            Quantity = 1,
            UnitPrice = 5,
            Product2Id = prodUnsynced.Id
        );
        insert newOi;

        Test.startTest();
        try {
            QBOrderRecordActionController.syncToQuickBooks(ord.Id);
            System.assert(false, 'Expected preflight check to throw exception for missing Product QuickBooks ID.');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException thrown as expected.');
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncFromQuickBooks_Success() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBOrderActionMock());
        Order ord = [SELECT Id FROM Order WHERE Account.Name = 'Synced Account' LIMIT 1];
        ord.QuickbookID__c = '999';
        update ord;

        Test.startTest();
        QBOrderRecordActionController.ActionResponse response = QBOrderRecordActionController.syncFromQuickBooks(ord.Id);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('999', response.quickBooksId);
        
        Order updatedOrd = [SELECT Id, QuickbookID__c, SyncToken__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('999', updatedOrd.QuickbookID__c);
        System.assertEquals('1', updatedOrd.SyncToken__c);
    }

    @isTest
    static void testSyncFromQuickBooks_MissingQBId() {
        configureQuickBooksConnection();
        Order ord = [SELECT Id FROM Order WHERE Account.Name = 'Synced Account' LIMIT 1];

        Test.startTest();
        try {
            QBOrderRecordActionController.syncFromQuickBooks(ord.Id);
            System.assert(false, 'Expected exception for missing QuickBooks ID.');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException thrown as expected.');
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncToQuickBooks_Error() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBOrderErrorMock());
        Order ord = [SELECT Id FROM Order WHERE Account.Name = 'Synced Account' LIMIT 1];

        Test.startTest();
        try {
            QBOrderRecordActionController.syncToQuickBooks(ord.Id);
            System.assert(false, 'Expected callout error to be handled.');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException thrown as expected.');
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncToQuickBooks_NullId() {
        Test.startTest();
        try {
            QBOrderRecordActionController.syncToQuickBooks(null);
            System.assert(false, 'Expected exception for null Id.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncToQuickBooks_InvalidId() {
        Test.startTest();
        try {
            String fakeId = Order.SObjectType.getDescribe().getKeyPrefix() + '000000000000';
            QBOrderRecordActionController.syncToQuickBooks((Id)fakeId);
            System.assert(false, 'Expected exception for invalid Id.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncFromQuickBooks_NullId() {
        Test.startTest();
        try {
            QBOrderRecordActionController.syncFromQuickBooks(null);
            System.assert(false, 'Expected exception for null Id.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    private class QBSyncEmptyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"Invoice": null}');
            return res;
        }
    }

    @isTest
    static void testSyncFromQuickBooks_EmptyResponse() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBSyncEmptyMock());
        
        Order ord = [SELECT Id FROM Order WHERE Account.Name = 'Synced Account' LIMIT 1];
        ord.QuickbookID__c = '999';
        update ord;

        Test.startTest();
        try {
            QBOrderRecordActionController.syncFromQuickBooks(ord.Id);
            System.assert(false, 'Expected exception for empty response.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    private class QBEmptyBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('');
            return res;
        }
    }

    @isTest
    static void testSyncToQuickBooks_EmptyBodyError() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBEmptyBodyMock());
        Order ord = [SELECT Id FROM Order WHERE Account.Name = 'Synced Account' LIMIT 1];

        Test.startTest();
        try {
            QBOrderRecordActionController.syncToQuickBooks(ord.Id);
            System.assert(false, 'Expected callout error to be handled.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    private class QBSyncNewProductMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"Estimate":{"Id":"999","SyncToken":"1","CustomerRef":{"value":"ACC-1"},"Line":[{"Id":"2","DetailType":"SalesItemLineDetail","Amount":50.00,"SalesItemLineDetail":{"Qty":2,"UnitPrice":25.00,"ItemRef":{"value":"PROD-999","name":"New Awesome Widget"}}}]}}');
            return res;
        }
    }

    @isTest
    static void testSyncFromQuickBooks_NewProduct() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBSyncNewProductMock());
        
        Order ord = [SELECT Id FROM Order WHERE Account.Name = 'Synced Account' LIMIT 1];
        ord.QuickbookID__c = '999';
        update ord;

        Test.startTest();
        QBOrderRecordActionController.ActionResponse response = QBOrderRecordActionController.syncFromQuickBooks(ord.Id);
        Test.stopTest();

        System.assertEquals(true, response.success);
        
        // Assert the new Product2 was created
        List<Product2> newProds = [SELECT Id, Name FROM Product2 WHERE QuickbookID__c = 'PROD-999'];
        System.assertEquals(1, newProds.size(), 'New product should have been created from QBO sync.');
        System.assertEquals('New Awesome Widget', newProds[0].Name);
        
        // Assert PricebookEntry was created
        List<PricebookEntry> pbes = [SELECT Id FROM PricebookEntry WHERE Product2Id = :newProds[0].Id];
        System.assert(pbes.size() > 0, 'PricebookEntry should have been created for the new product.');
    }
}