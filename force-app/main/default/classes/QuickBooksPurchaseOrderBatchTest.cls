@isTest
private class QuickBooksPurchaseOrderBatchTest {

    private class QBPurchaseOrderMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            System.assert(
                !endpoint.contains('/purchaseorder/'),
                'Purchase order update hydration must use the QuickBooks query endpoint, not a per-record purchase order GET.'
            );
            if (req.getMethod() == 'GET' && endpoint.contains('/query?query=')) {
                res.setBody('{"QueryResponse":{"PurchaseOrder":[{"Id":"PO-EXISTING","SyncToken":"5"}]}}');
            } else if (req.getMethod() == 'POST') {
                res.setBody('{"PurchaseOrder":{"Id":"PO-NEW","SyncToken":"0"}}');
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    private class QBPurchaseOrderFailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Server Error');
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

        Account acc = new Account(Name = 'PO Batch Account', QuickbookID__c = 'QB-ACC-1');
        insert acc;

        Product2 prod = new Product2(Name = 'PO Product', QuickbookID__c = 'QB-PROD-1', IsActive = true);
        insert prod;

        Purchase_Order__c po = new Purchase_Order__c(
            Account__c = acc.Id,
            Supplier__c = acc.Id,
            External_Id__c = null
        );
        insert po;

        Purchase_Order_Line__c pol = new Purchase_Order_Line__c(
            Purchase_Order__c = po.Id,
            Product__c = prod.Id,
            Quantity__c = 10,
            Cost_Price__c = 100,
            Product_Description__c = 'Test Description'
        );
        insert pol;
    }

    @isTest
    static void testBatchInitialSync() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBPurchaseOrderMock());
        
        Purchase_Order__c po = [SELECT Id FROM Purchase_Order__c WHERE External_Id__c = null LIMIT 1];
        Set<Id> ids = new Set<Id>{ po.Id };

        Test.startTest();
        Database.executeBatch(new QuickBooksPurchaseOrderBatch(ids, true), 1);
        Test.stopTest();

        Purchase_Order__c updatedPo = [SELECT External_Id__c FROM Purchase_Order__c WHERE Id = :po.Id];
        System.assertNotEquals(null, updatedPo.External_Id__c);
        System.assertEquals('PO-NEW', updatedPo.External_Id__c);
    }

    @isTest
    static void testBatchUpdateSync() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBPurchaseOrderMock());
        
        Purchase_Order__c po = [SELECT Id FROM Purchase_Order__c LIMIT 1];
        po.External_Id__c = 'PO-EXISTING';
        update po;
        
        Set<Id> ids = new Set<Id>{ po.Id };

        Test.startTest();
        Database.executeBatch(new QuickBooksPurchaseOrderBatch(ids, false), 1);
        Test.stopTest();

        Purchase_Order__c updatedPo = [SELECT External_Id__c FROM Purchase_Order__c WHERE Id = :po.Id];
        System.assertEquals('PO-EXISTING', updatedPo.External_Id__c);
    }

    @isTest
    static void testBatchCreateFailure() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBPurchaseOrderFailMock());
        
        Purchase_Order__c po = [SELECT Id FROM Purchase_Order__c WHERE External_Id__c = null LIMIT 1];
        Set<Id> ids = new Set<Id>{ po.Id };

        Test.startTest();
        Database.executeBatch(new QuickBooksPurchaseOrderBatch(ids, true), 1);
        Test.stopTest();

        Purchase_Order__c updatedPo = [SELECT External_Id__c FROM Purchase_Order__c WHERE Id = :po.Id];
        System.assertEquals(null, updatedPo.External_Id__c);
        
        List<Error_Log__c> logs = [SELECT Id FROM Error_Log__c];
        System.assert(!logs.isEmpty());
    }

    @isTest
    static void testBatchUpdateQueryFailure() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBPurchaseOrderFailMock());
        
        Purchase_Order__c po = [SELECT Id FROM Purchase_Order__c LIMIT 1];
        po.External_Id__c = 'PO-EXISTING';
        update po;
        
        Set<Id> ids = new Set<Id>{ po.Id };

        Test.startTest();
        Database.executeBatch(new QuickBooksPurchaseOrderBatch(ids, false), 1);
        Test.stopTest();

        List<Error_Log__c> logs = [SELECT Id FROM Error_Log__c];
        System.assert(!logs.isEmpty());
    }

    @isTest
    static void testBatchNoChildItems() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBPurchaseOrderMock());
        
        Purchase_Order__c po = new Purchase_Order__c(
            Account__c = [SELECT Id FROM Account LIMIT 1].Id,
            Supplier__c = [SELECT Id FROM Account LIMIT 1].Id,
            External_Id__c = null
        );
        insert po;
        
        Set<Id> ids = new Set<Id>{ po.Id };

        Test.startTest();
        Database.executeBatch(new QuickBooksPurchaseOrderBatch(ids, true), 1);
        Test.stopTest();

        Purchase_Order__c updatedPo = [SELECT External_Id__c FROM Purchase_Order__c WHERE Id = :po.Id];
        System.assertEquals(null, updatedPo.External_Id__c);
    }
}
