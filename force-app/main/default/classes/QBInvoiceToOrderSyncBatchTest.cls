@isTest
private class QBInvoiceToOrderSyncBatchTest {

    // ======================= MOCK CLASSES =======================

    // Mock for initial creation (standard business account and existing product)
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

    // Mock for update scenario (changed line item details)
    private class QBInvoiceToOrderUpdateMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                // Always return the same invoice (ignoring date filter for test reliability)
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Invoice":[{"Id":"INV-1","TxnDate":"2025-01-15","CustomerMemo":{"value":"Updated memo"},"CustomerRef":{"value":"QB-CUST-1","name":"Sync Customer"},"Line":[{"Id":"1","DetailType":"SalesItemLineDetail","Description":"Line 1 Updated","SalesItemLineDetail":{"Qty":5,"UnitPrice":15,"ItemRef":{"value":"QB-ITEM-1","name":"Sync Product"}}}]}]}}');
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    // Mock for new product creation (product does not exist in Salesforce)
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

    // Mock for PersonAccount scenario (existing PersonAccount with QB ID)
    private class PersonAccountMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Invoice":[{"Id":"INV-PERSON","TxnDate":"2025-01-15","CustomerRef":{"value":"QB-PERSON-1","name":"John Doe"},"Line":[{"Id":"L1","DetailType":"SalesItemLineDetail","Description":"Person product","SalesItemLineDetail":{"Qty":1,"UnitPrice":50,"ItemRef":{"value":"QB-ITEM-1","name":"Sync Product"}}}]}]}}');
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    // Mock for existing order not in map scenario
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

    // ======================= SETUP =======================

    @testSetup
    static void setupData() {
        // QuickBooks configuration
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

        // Create a product with pricebook entry for the standard pricebook
        Product2 prod = new Product2(Name = 'Existing Product', QuickbookID__c = 'QB-ITEM-1', IsActive = true);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 10,
            IsActive = true
        );
        insert pbe;
    }

    // ======================= TEST METHODS =======================

    // Original test – creates new records (business account, existing product)
    @isTest
    static void testBatchStartExecuteFinish() {
        Test.setMock(HttpCalloutMock.class, new QBInvoiceToOrderMock());

        Test.startTest();
        Database.executeBatch(new QBInvoiceToOrderSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        System.assertEquals(false, QBInvoiceToOrderSyncBatch.isProcessing);

        Account syncedAccount = [SELECT Id, QuickbookID__c, Name, FirstName, LastName FROM Account WHERE QuickbookID__c = 'QB-CUST-1' LIMIT 1];
        Product2 syncedProduct = [SELECT Id, QuickbookID__c FROM Product2 WHERE QuickbookID__c = 'QB-ITEM-1' LIMIT 1];
        Order syncedOrder = [SELECT Id, QuickbookID__c, AccountId, EffectiveDate, Description FROM Order WHERE QuickbookID__c = 'INV-1' LIMIT 1];
        OrderItem syncedItem = [SELECT Id, OrderId, Product2Id, Quantity, UnitPrice, Description, QB_LineItemID__c FROM OrderItem WHERE OrderId = :syncedOrder.Id LIMIT 1];

        System.assertEquals('QB-CUST-1', syncedAccount.QuickbookID__c);
        System.assertEquals('Sync Customer', syncedAccount.Name);
        System.assertEquals(null, syncedAccount.FirstName);
        System.assertEquals(null, syncedAccount.LastName);
        System.assertEquals('QB-ITEM-1', syncedProduct.QuickbookID__c);
        System.assertEquals('INV-1', syncedOrder.QuickbookID__c);
        System.assertEquals(syncedAccount.Id, syncedOrder.AccountId);
        System.assertEquals(Date.newInstance(2025, 1, 15), syncedOrder.EffectiveDate);
        System.assertEquals('Invoice memo', syncedOrder.Description);
        System.assertEquals(syncedProduct.Id, syncedItem.Product2Id);
        System.assertEquals(2, syncedItem.Quantity);
        System.assertEquals(10, syncedItem.UnitPrice);
        System.assertEquals('Line 1', syncedItem.Description);
        System.assertEquals('INV-1:1', syncedItem.QB_LineItemID__c);
    }

    // Test update path: existing OrderItem changed (covers needsUpdate block)
    @isTest
    static void testBatchUpdateOrderItem() {
        // First run – create initial records
        Test.setMock(HttpCalloutMock.class, new QBInvoiceToOrderMock());
        Database.executeBatch(new QBInvoiceToOrderSyncBatch('2025-01-01'), 1);

        // Second run – updated data (ensures invoice is returned regardless of date)
        Test.setMock(HttpCalloutMock.class, new QBInvoiceToOrderUpdateMock());

        Test.startTest();
        Database.executeBatch(new QBInvoiceToOrderSyncBatch('2025-01-02'), 1);
        Test.stopTest();

        OrderItem updatedItem = [SELECT Quantity, UnitPrice, Description FROM OrderItem WHERE QB_LineItemID__c = 'INV-1:1' LIMIT 1];
        System.assertEquals(5, updatedItem.Quantity, 'Quantity should be updated');
        System.assertEquals(15, updatedItem.UnitPrice, 'UnitPrice should be updated');
        System.assertEquals('Line 1 Updated', updatedItem.Description, 'Description should be updated');
    }

    // Test new product creation (covers product not in map and productsToUpsert not empty)
    @isTest
    static void testNewProductCreation() {
        // Ensure no product with QB-NEW-PROD exists
        List<Product2> existing = [SELECT Id FROM Product2 WHERE QuickbookID__c = 'QB-NEW-PROD'];
        System.assertEquals(0, existing.size(), 'Product should not exist before test');

        Test.setMock(HttpCalloutMock.class, new NewProductMock());

        Test.startTest();
        Database.executeBatch(new QBInvoiceToOrderSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        // Product should be created
        Product2 newProduct = [SELECT Id, Name, QuickbookID__c FROM Product2 WHERE QuickbookID__c = 'QB-NEW-PROD' LIMIT 1];
        System.assertEquals('New Product', newProduct.Name);

        // Pricebook Entry should be created for standard pricebook
        PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice, IsActive FROM PricebookEntry WHERE Product2Id = :newProduct.Id AND Pricebook2Id = :Test.getStandardPricebookId() LIMIT 1];
        System.assertNotEquals(null, pbe, 'Pricebook Entry should be created');
        System.assertEquals(0, pbe.UnitPrice, 'Default price is 0 until updated from invoice? Actually price comes from line item, but entry price remains 0');
        System.assertEquals(true, pbe.IsActive);

        // Order and OrderItem should be created
        Order createdOrder = [SELECT Id, QuickbookID__c FROM Order WHERE QuickbookID__c = 'INV-NEW' LIMIT 1];
        OrderItem createdItem = [SELECT Id, Quantity, UnitPrice, Description, Product2Id FROM OrderItem WHERE OrderId = :createdOrder.Id LIMIT 1];
        System.assertEquals(1, createdItem.Quantity);
        System.assertEquals(99.99, createdItem.UnitPrice);
        System.assertEquals('Brand new product', createdItem.Description);
        System.assertEquals(newProduct.Id, createdItem.Product2Id);
    }

    private static Id getPersonAccountRecordTypeId() {
    List<RecordType> rt = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1];
    if (rt.isEmpty()) {
        return null;
    }
    return rt[0].Id;
}

    @isTest
static void testPersonAccountHandling() {
    Id personRtId = getPersonAccountRecordTypeId();
    if (personRtId == null) {
        // Person Accounts not enabled in this org – skip test gracefully
        System.debug('Person Accounts not enabled, skipping testPersonAccountHandling');
        return;
    }

    // Create a Person Account with the QuickBooks ID that will be used in the mock
    Account personAcc = new Account(
        RecordTypeId = personRtId,
        QuickbookID__c = 'QB-PERSON-1',
        FirstName = 'OriginalFirst',
        LastName = 'OriginalLast',
        PersonEmail = 'person@example.com'
        // Do NOT set IsPersonAccount – it's read-only
    );
    insert personAcc;

    // Verify it's a Person Account by querying the read-only field
    Account inserted = [SELECT Id, IsPersonAccount, FirstName, LastName, Name FROM Account WHERE Id = :personAcc.Id];
    System.assertEquals(true, inserted.IsPersonAccount, 'Account should be a Person Account');
    System.assertEquals('OriginalFirst', inserted.FirstName);
    System.assertEquals('OriginalLast', inserted.LastName);

    Test.setMock(HttpCalloutMock.class, new PersonAccountMock());

    Test.startTest();
    Database.executeBatch(new QBInvoiceToOrderSyncBatch('2025-01-01'), 1);
    Test.stopTest();

    // Reload the account – the batch should update FirstName/LastName from the invoice's customer name "John Doe"
    Account updatedAcc = [SELECT Id, FirstName, LastName, Name FROM Account WHERE Id = :personAcc.Id];
    // "John Doe" splits into FirstName=John, LastName=Doe
    System.assertEquals('John', updatedAcc.FirstName, 'FirstName should be updated from customer name');
    System.assertEquals('Doe', updatedAcc.LastName, 'LastName should be updated from customer name');
    // Name is a formula for Person Accounts, so we don't assert on it directly
}

    // Test existing Order not in batch map (covers else branch of orderIdMap.containsKey)
    @isTest
    static void testExistingOrderNotInMap() {
        // Pre-create an Order with QuickbookID__c that matches the invoice ID from the mock
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

        // Ensure no OrderItem exists yet
        List<OrderItem> beforeItems = [SELECT Id FROM OrderItem WHERE OrderId = :existingOrder.Id];
        System.assertEquals(0, beforeItems.size(), 'Order should have no items initially');

        Test.setMock(HttpCalloutMock.class, new ExistingOrderMock());

        Test.startTest();
        Database.executeBatch(new QBInvoiceToOrderSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        // The batch should find the existing Order (via else branch) and add OrderItems
        Order refreshedOrder = [SELECT Id, QuickbookID__c FROM Order WHERE Id = :existingOrder.Id];
        System.assertEquals('EXIST-ORDER-1', refreshedOrder.QuickbookID__c);

        OrderItem createdItem = [SELECT Id, OrderId, Quantity, UnitPrice, Description, Product2Id FROM OrderItem WHERE OrderId = :refreshedOrder.Id LIMIT 1];
        System.assertNotEquals(null, createdItem, 'OrderItem should have been created under the existing Order');
        System.assertEquals(3, createdItem.Quantity);
        System.assertEquals(25, createdItem.UnitPrice);
        System.assertEquals('Item for existing order', createdItem.Description);
    }

    // Test processSingleInvoice
    @isTest
    static void testProcessSingleInvoice() {
        Test.setMock(HttpCalloutMock.class, new QBInvoiceToOrderMock());

        Test.startTest();
        QBInvoiceToOrderSyncBatch.processSingleInvoice('INV-1');
        Test.stopTest();

        Account syncedAccount = [SELECT Id FROM Account WHERE QuickbookID__c = 'QB-CUST-1' LIMIT 1];
        Order syncedOrder = [SELECT Id FROM Order WHERE QuickbookID__c = 'INV-1' LIMIT 1];
        OrderItem syncedItem = [SELECT Id FROM OrderItem WHERE OrderId = :syncedOrder.Id LIMIT 1];

        System.assertNotEquals(null, syncedAccount);
        System.assertNotEquals(null, syncedOrder);
        System.assertNotEquals(null, syncedItem);
    }
}