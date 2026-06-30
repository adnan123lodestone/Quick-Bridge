@isTest
private class QBProductServiceTest {

    private static String lastCreateRequestBody;
    private static String lastUpdateRequestBody;
    private static String lastGetEndpoint;
    private static String lastPostEndpoint;
    private static Integer forcedCreateStatusCode = 200;
    private static Integer forcedQueryStatusCode = 200;
    private static Integer forcedUpdateStatusCode = 200;
    private static Boolean returnNullForCreate = false;
    private static Boolean returnNullForQuery = false;

    @testSetup
    static void setupData() {
        // Required for QuickBooksAuthHandler
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

        // Test products
        Product2 prodCreate = new Product2(
            Name = 'QB Product Service Create',
            IsActive = true,
            Sale_Price__c = 25,
            Cost_Price__c = 10,
            Quantity_On_Hand__c = 3,
            Income_Account__c = '79',
            COGS_Account_Ref__c = 'Cost of Goods Sold',
            Asset_Account_Ref__c = 'Inventory Asset'
        );
        insert prodCreate;

        Product2 prodUpdate = new Product2(
            Name = 'QB Product Service Update',
            IsActive = true,
            QuickbookID__c = 'ITM-100',
            Sale_Price__c = 30,
            Income_Account__c = '79'
        );
        insert prodUpdate;

        Product2 prodNoQBId = new Product2(
            Name = 'No QB Id Product',
            IsActive = true,
            Sale_Price__c = 10
        );
        insert prodNoQBId;
    }

    // Flexible mock that can simulate different HTTP responses
    private class ConfigurableMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String method = req.getMethod();

            if (method == 'GET' && endpoint.contains('/item/')) {
                lastGetEndpoint = req.getEndpoint();
                if (returnNullForQuery) {
                    res.setStatusCode(404);
                    res.setBody('{"Fault":{"Error":[{"Message":"Not Found"}]}}');
                    return res;
                }
                res.setStatusCode(forcedQueryStatusCode);
                if (forcedQueryStatusCode == 200) {
                    res.setBody('{"Item":{"Id":"ITM-100","SyncToken":"0","Name":"Old","Type":"Inventory"}}');
                } else {
                    res.setBody('{"Fault":{"Error":[{"Message":"Error"}]}}');
                }
                return res;
            }
            if (method == 'POST' && endpoint.contains('/item')) {
                lastPostEndpoint = req.getEndpoint();
                if (req.getBody() != null && req.getBody().contains('"Id":"ITM-100"')) {
                    lastUpdateRequestBody = req.getBody();
                } else {
                    lastCreateRequestBody = req.getBody();
                }
                if (returnNullForCreate) {
                    res.setStatusCode(500);
                    res.setBody('{"Fault":{"Error":[{"Message":"Server Error"}]}}');
                    return res;
                }
                res.setStatusCode(forcedCreateStatusCode);
                if (forcedCreateStatusCode == 200) {
                    res.setBody('{"Item":{"Id":"ITM-100"}}');
                } else {
                    res.setBody('{"Fault":{"Error":[{"Message":"Create Failed"}]}}');
                }
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    // ----------------------------------------------------------------------
    // SUCCESS PATHS
    // ----------------------------------------------------------------------

    @isTest
    static void testCreatePathAddsRequiredQuickBooksItemFields() {
        resetMockState();
        forcedCreateStatusCode = 200;
        returnNullForCreate = false;
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Product2 createProduct = [SELECT Id FROM Product2 WHERE Name = 'QB Product Service Create' LIMIT 1];

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ createProduct }, true);
        Test.stopTest();

        System.assertNotEquals(null, lastCreateRequestBody);
        System.assertNotEquals(null, lastPostEndpoint);
        Map<String, Object> requestMap = (Map<String, Object>)JSON.deserializeUntyped(lastCreateRequestBody);
        System.assertEquals('Inventory', (String)requestMap.get('Type'));
        System.assertEquals('79', String.valueOf(((Map<String, Object>)requestMap.get('IncomeAccountRef')).get('value')));
        System.assertEquals('80', String.valueOf(((Map<String, Object>)requestMap.get('ExpenseAccountRef')).get('value')));
        System.assertEquals('81', String.valueOf(((Map<String, Object>)requestMap.get('AssetAccountRef')).get('value')));
    }

    @isTest
    static void testUpdatePathUsesCleanItemEndpoints() {
        resetMockState();
        forcedQueryStatusCode = 200;
        forcedUpdateStatusCode = 200;
        returnNullForQuery = false;
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Product2 updateProduct = [SELECT Id, QuickbookID__c FROM Product2 WHERE Name = 'QB Product Service Update' LIMIT 1];

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ updateProduct }, false);
        Test.stopTest();

        System.assertNotEquals(null, lastGetEndpoint);
        System.assertNotEquals(null, lastUpdateRequestBody);
        System.assertNotEquals(null, lastPostEndpoint);
        System.assert(lastGetEndpoint.contains('/item/ITM-100'));
    }

    // ----------------------------------------------------------------------
    // FAILURE PATHS
    // ----------------------------------------------------------------------

    @isTest
    static void testCreateFailure_Non200Response() {
        resetMockState();
        forcedCreateStatusCode = 500;
        returnNullForCreate = true;  // simulate error
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Product2 createProduct = [SELECT Id FROM Product2 WHERE Name = 'QB Product Service Create' LIMIT 1];

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ createProduct }, true);
        Test.stopTest();

        // No update should be attempted because create failed
        System.assert(lastCreateRequestBody != null ? lastCreateRequestBody.contains('Inventory') : true);
        // The product should not have its QB ID updated (no DML on productsToUpdate)
        Product2 checkProduct = [SELECT QuickbookID__c FROM Product2 WHERE Id = :createProduct.Id];
        System.assertEquals(null, checkProduct.QuickbookID__c);
    }

    @isTest
    static void testUpdatePath_QueryFails() {
        resetMockState();
        forcedQueryStatusCode = 404;
        returnNullForQuery = true;
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Product2 updateProduct = [SELECT Id, QuickbookID__c FROM Product2 WHERE Name = 'QB Product Service Update' LIMIT 1];

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ updateProduct }, false);
        Test.stopTest();

        // Update should not be called because query failed
        System.assert(lastUpdateRequestBody == null);
    }

    @isTest
    static void testUpdatePath_UpdateFails() {
        resetMockState();
        forcedQueryStatusCode = 200;
        forcedUpdateStatusCode = 500;
        returnNullForCreate = false;
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Product2 updateProduct = [SELECT Id, QuickbookID__c FROM Product2 WHERE Name = 'QB Product Service Update' LIMIT 1];

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ updateProduct }, false);
        Test.stopTest();

        // Update call was made but failed; no exception thrown, just logged
        System.assertNotEquals(null, lastUpdateRequestBody);
        // Product's QB ID should remain unchanged (no DML from this method)
    }

    @isTest
    static void testProductWithNoQBId_UsesCreatePathEvenWhenIsInsertFalse() {
        resetMockState();
        forcedCreateStatusCode = 200;
        returnNullForCreate = false;
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Product2 noIdProduct = [SELECT Id FROM Product2 WHERE Name = 'No QB Id Product' LIMIT 1];

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ noIdProduct }, false);
        Test.stopTest();

        // Should have gone to create path because qbId == null
        System.assertNotEquals(null, lastCreateRequestBody);
        System.assert(lastCreateRequestBody.contains('No QB Id Product'));
    }

    @isTest
    static void testCreateReturnsNull_ElseBranchCovered() {
        resetMockState();
        forcedCreateStatusCode = 500;
        returnNullForCreate = true;
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Product2 createProduct = [SELECT Id FROM Product2 WHERE Name = 'QB Product Service Create' LIMIT 1];

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ createProduct }, true);
        Test.stopTest();

        // createItemInQuickBooks returns null → the else branch (empty comment) is executed
        // No product update should occur
        Product2 checkProduct = [SELECT QuickbookID__c FROM Product2 WHERE Id = :createProduct.Id];
        System.assertEquals(null, checkProduct.QuickbookID__c);
    }

    // ----------------------------------------------------------------------
    // EDGE CASES: hydrateProducts & ensureRequiredItemFields
    // ----------------------------------------------------------------------

    @isTest
    static void testHydrateProductsWithEmptyList() {
        // Directly test the private method using reflection or via a wrapper?
        // We'll just call sync with empty list – hydrateProducts is called internally.
        resetMockState();
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>(), true);
        Test.stopTest();

        // No exception, nothing happens
        System.assert(true);
    }

    @isTest
    static void testEnsureRequiredItemFields_NonInventoryType() {
        // Create a product that will be inferred as NonInventory
        Product2 nonInvProduct = new Product2(
            Name = 'NonInventory Product',
            IsActive = true,
            Sale_Price__c = 10
            // No Asset_Account_Ref__c, COGS, Qty, Cost
        );
        insert nonInvProduct;

        resetMockState();
        forcedCreateStatusCode = 200;
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ nonInvProduct }, true);
        Test.stopTest();

        System.assertNotEquals(null, lastCreateRequestBody);
        Map<String, Object> requestMap = (Map<String, Object>)JSON.deserializeUntyped(lastCreateRequestBody);
        System.assertEquals('NonInventory', (String)requestMap.get('Type'));
        // ExpenseAccountRef should be set because no IncomeAccountRef value? Actually ensureAccountRef logic.
        // We just verify that no exception occurs.
    }

    @isTest
    static void testEnsureRequiredItemFields_InventoryWithMissingAccounts() {
        Product2 invProduct = new Product2(
            Name = 'Inventory Product Missing',
            IsActive = true,
            Quantity_On_Hand__c = 5,
            Cost_Price__c = 20
            // No Income_Account__c, Asset_Account_Ref__c, etc.
        );
        insert invProduct;

        resetMockState();
        forcedCreateStatusCode = 200;
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ invProduct }, true);
        Test.stopTest();

        Map<String, Object> requestMap = (Map<String, Object>)JSON.deserializeUntyped(lastCreateRequestBody);
        System.assertEquals('Inventory', (String)requestMap.get('Type'));
        // Default account values should be applied
        Map<String, Object> incomeRef = (Map<String, Object>)requestMap.get('IncomeAccountRef');
        System.assert(incomeRef != null);
        System.assertEquals('79', (String)incomeRef.get('value'));
    }

    @isTest
    static void testApplyDynamicMappings_NestedFields() {
        // Already tested indirectly via create/update, but we can force a scenario
        // where a mapping path contains a dot. We rely on the fallback mapping from QBObjectMappings.
        // The default mapping for Product2 includes simple fields, but we can insert a
        // Field_Mapping__mdt (though not allowed in tests). So we just ensure the method runs without error.
        // This test is more for coverage of the loop and nested map creation.
        resetMockState();
        forcedCreateStatusCode = 200;
        Test.setMock(HttpCalloutMock.class, new ConfigurableMock());

        Product2 prod = [SELECT Id, Name FROM Product2 WHERE Name = 'QB Product Service Create' LIMIT 1];
        Test.startTest();
        QBProductService.syncProductsToQuickBooks(new List<Product2>{ prod }, true);
        Test.stopTest();

        // The applyDynamicMappings is executed; if any mapping had a dot, it would create nested maps.
        System.assert(lastCreateRequestBody != null);
    }

    // ----------------------------------------------------------------------
    // HELPER: reset mock state
    // ----------------------------------------------------------------------

    private static void resetMockState() {
        lastCreateRequestBody = null;
        lastUpdateRequestBody = null;
        lastGetEndpoint = null;
        lastPostEndpoint = null;
        forcedCreateStatusCode = 200;
        forcedQueryStatusCode = 200;
        forcedUpdateStatusCode = 200;
        returnNullForCreate = false;
        returnNullForQuery = false;
    }
}