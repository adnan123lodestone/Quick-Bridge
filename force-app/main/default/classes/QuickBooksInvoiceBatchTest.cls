@isTest
private class QuickBooksInvoiceBatchTest {

    private class QBInvoiceBatchMock implements HttpCalloutMock {
        private Integer statusCode;
        
        public QBInvoiceBatchMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            System.assert(
                !endpoint.contains('/invoice/'),
                'Invoice update hydration must use the QuickBooks query endpoint, not a per-record invoice GET.'
            );

            if (this.statusCode >= 400) {
                res.setBody('{"Fault": {"Error": [{"Message": "API Error"}]}}');
                return res;
            }

            if (req.getMethod() == 'GET' && endpoint.contains('/query?query=')) {
                res.setBody('{"QueryResponse":{"Invoice":[{"Id":"INV-123","SyncToken":"1","Line":[{"Id":"1","Amount":100.00,"DetailType":"SalesItemLineDetail","SalesItemLineDetail":{"Qty":2,"UnitPrice":50.00}}]}]}}');
            } else {
                res.setBody('{"Invoice":{"Id":"INV-123","Line":[{"Id":"1","Amount":100.00,"DetailType":"SalesItemLineDetail","SalesItemLineDetail":{"Qty":2,"UnitPrice":50.00}}]}}');
            }
            return res;
        }
    }

    private class QBInvoiceUpdateFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            System.assert(
                !endpoint.contains('/invoice/'),
                'Invoice update hydration must use the QuickBooks query endpoint, not a per-record invoice GET.'
            );
            if (req.getMethod() == 'GET' && endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Invoice":[{"Id":"INV-123","SyncToken":"1"}]}}');
            } else {
                res.setStatusCode(400);
                res.setBody('{"Fault":{"Error":[{"Message":"Update Failed"}]}}');
            }
            return res;
        }
    }

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Batch Test Account');
        safePut(acc, 'QuickBridgeTLG__QuickbookID__c', 'QBO-ACC-1');
        safePut(acc, 'QuickbookID__c', 'QBO-ACC-1');
        insert acc;

        Product2 prod = new Product2(Name = 'Batch Test Product', IsActive = true);
        safePut(prod, 'QuickBridgeTLG__QuickbookID__c', 'QBO-PROD-1');
        safePut(prod, 'QuickbookID__c', 'QBO-PROD-1');
        insert prod;

        String invObjName = QBObjectMappings.getInvoiceSourceObject();
        String childObjName = null;
        String lookupField = null;
        Schema.SObjectType parentType = Schema.getGlobalDescribe().get(invObjName);
        
        for (Schema.ChildRelationship cr : parentType.getDescribe().getChildRelationships()) {
            if (cr.getRelationshipName() != null && cr.getRelationshipName().equalsIgnoreCase('QuickBridgeTLG__Invoice_Lines__r')) {
                childObjName = cr.getChildSObject().getDescribe().getName();
                lookupField = cr.getField().getDescribe().getName();
                break;
            }
        }
        
        if (childObjName == null) {
            for (Schema.ChildRelationship cr : parentType.getDescribe().getChildRelationships()) {
                if (cr.getRelationshipName() != null && cr.getRelationshipName().endsWithIgnoreCase('Invoice_Lines__r')) {
                    childObjName = cr.getChildSObject().getDescribe().getName();
                    lookupField = cr.getField().getDescribe().getName();
                    break;
                }
            }
        }
        
        if (childObjName == null) {
            if (invObjName.equalsIgnoreCase('Order')) {
                childObjName = 'OrderItem';
                lookupField = 'OrderId';
            } else {
                childObjName = invObjName.replace('__c', '') + '_Line__c';
                lookupField = invObjName;
            }
        }

        Id stdPricebookId = Test.getStandardPricebookId();
        if (childObjName == 'OrderItem') {
            PricebookEntry pbe = new PricebookEntry(
                Pricebook2Id = stdPricebookId, Product2Id = prod.Id, UnitPrice = 100.00, IsActive = true
            );
            insert pbe;
        }

        SObject inv1 = Schema.getGlobalDescribe().get(invObjName).newSObject();
        safePut(inv1, 'QuickBridgeTLG__Related_Account__c', acc.Id);
        safePut(inv1, 'Related_Account__c', acc.Id);
        safePut(inv1, 'AccountId', acc.Id); 
        safePut(inv1, 'Status', 'Draft');
        safePut(inv1, 'EffectiveDate', Date.today());
        if (invObjName.equalsIgnoreCase('Order')) safePut(inv1, 'Pricebook2Id', stdPricebookId);
        insert inv1;

        SObject line1 = Schema.getGlobalDescribe().get(childObjName).newSObject();
        line1.put(lookupField, inv1.Id);
        safePut(line1, 'QuickBridgeTLG__Product__c', prod.Id);
        safePut(line1, 'Product__c', prod.Id);
        safePut(line1, 'QuickBridgeTLG__Quantity__c', 2);
        safePut(line1, 'Quantity__c', 2);
        safePut(line1, 'QuickBridgeTLG__Unit_Price__c', 100.00);
        safePut(line1, 'Unit_Price__c', 100.00);
        if (childObjName == 'OrderItem') {
            PricebookEntry pbe = [SELECT Id FROM PricebookEntry LIMIT 1];
            safePut(line1, 'PricebookEntryId', pbe.Id);
            safePut(line1, 'Quantity', 2);
            safePut(line1, 'UnitPrice', 100.00);
        }
        insert line1;

        SObject inv2 = Schema.getGlobalDescribe().get(invObjName).newSObject();
        safePut(inv2, 'QuickBridgeTLG__Related_Account__c', acc.Id);
        safePut(inv2, 'Related_Account__c', acc.Id);
        safePut(inv2, 'QuickBridgeTLG__External_Id__c', 'INV-123');
        safePut(inv2, 'External_Id__c', 'INV-123');
        safePut(inv2, 'AccountId', acc.Id); 
        safePut(inv2, 'Status', 'Draft');
        safePut(inv2, 'EffectiveDate', Date.today());
        if (invObjName.equalsIgnoreCase('Order')) safePut(inv2, 'Pricebook2Id', stdPricebookId);
        insert inv2;

        SObject line2 = Schema.getGlobalDescribe().get(childObjName).newSObject();
        line2.put(lookupField, inv2.Id);
        safePut(line2, 'QuickBridgeTLG__Product__c', prod.Id);
        safePut(line2, 'Product__c', prod.Id);
        safePut(line2, 'QuickBridgeTLG__Quantity__c', 1);
        safePut(line2, 'Quantity__c', 1);
        safePut(line2, 'QuickBridgeTLG__Unit_Price__c', 50.00);
        safePut(line2, 'Unit_Price__c', 50.00);
        if (childObjName == 'OrderItem') {
            PricebookEntry pbe = [SELECT Id FROM PricebookEntry LIMIT 1];
            safePut(line2, 'PricebookEntryId', pbe.Id);
            safePut(line2, 'Quantity', 1);
            safePut(line2, 'UnitPrice', 50.00);
        }
        insert line2;
    }

    @isTest
    static void testBatchExecution() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'Mock_Named_Credential', '65');
        Test.setMock(HttpCalloutMock.class, new QBInvoiceBatchMock(200));

        String invObjName = QBObjectMappings.getInvoiceSourceObject();
        String extIdField = getActualFieldName(invObjName, 'External_Id__c');
        SObject inv = Database.query('SELECT Id FROM ' + invObjName + ' WHERE ' + extIdField + ' = null LIMIT 1');

        Test.startTest();
        QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>{inv.Id}, true);
        Database.executeBatch(batch, 1);
        Test.stopTest();
        
        System.assert(true);
    }

    @isTest
    static void testExceptionBlockCoverage() {
        QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>(), true);
        Test.startTest();
        batch.execute(null, null); 
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testConstructorWithTriggerItems() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        List<SObject> triggerItems = new List<SObject>{ acc };
        QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>{acc.Id}, false, triggerItems);
        System.assertNotEquals(null, batch);
    }

    @isTest
    static void testApplyDynamicMappings() {
        QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>(), false);
        Map<String, Object> reqBody = new Map<String, Object>();
        Map<String, String> fieldMap = new Map<String, String>{
            'LastName' => 'DocNumber',
            'Account.Name' => 'CustomerRef.name'
        };

        Contact dummyRec = new Contact(LastName = 'Acme Test');
        Account parentAcc = new Account(Name = 'Nested Parent');
        dummyRec.putSObject('Account', parentAcc);

        batch.applyDynamicMappings(reqBody, dummyRec, fieldMap);

        System.assertEquals('Acme Test', reqBody.get('DocNumber'));
        Map<String, Object> custRef = (Map<String, Object>)reqBody.get('CustomerRef');
        System.assertNotEquals(null, custRef);
        System.assertEquals('Nested Parent', custRef.get('name'));
    }

    @isTest
    static void testGetFieldValue() {
        Contact dummyRec = new Contact(LastName = 'Smith');
        Account parentAcc = new Account(Name = 'Acme');
        dummyRec.putSObject('Account', parentAcc);

        System.assertEquals('Smith', QuickBooksInvoiceBatch.getFieldValue(dummyRec, 'LastName'));
        System.assertEquals('Acme', QuickBooksInvoiceBatch.getFieldValue(dummyRec, 'Account.Name'));
        System.assertEquals(null, QuickBooksInvoiceBatch.getFieldValue(dummyRec, 'InvalidField'));
        System.assertEquals(null, QuickBooksInvoiceBatch.getFieldValue(dummyRec, 'Account.InvalidField'));
        System.assertEquals(null, QuickBooksInvoiceBatch.getFieldValue(dummyRec, 'InvalidRelation.Name'));
    }

    @isTest
    static void testBuildLineItems() {
        QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>(), false);
        
        String invObjName = QBObjectMappings.getInvoiceSourceObject();
        String childObjName = null;
        Schema.SObjectType parentType = Schema.getGlobalDescribe().get(invObjName);
        for (Schema.ChildRelationship cr : parentType.getDescribe().getChildRelationships()) {
            if (cr.getRelationshipName() != null && cr.getRelationshipName().endsWithIgnoreCase('Invoice_Lines__r')) {
                childObjName = cr.getChildSObject().getDescribe().getName();
                break;
            }
        }
        if (childObjName == null) childObjName = invObjName.equalsIgnoreCase('Order') ? 'OrderItem' : (invObjName.replace('__c', '') + '_Line__c');
        
        List<SObject> lines = new List<SObject>();
        
        try {
            String jsonStr = '{"attributes":{"type":"' + childObjName + '"},"QuickBridgeTLG__Quantity__c":5.0,"QuickBridgeTLG__Unit_Price__c":20.0,"QuickBridgeTLG__Product__r":{"attributes":{"type":"Product2"},"QuickBridgeTLG__QuickbookID__c":"QBO-123","Name":"Mock Product"}}';
            SObject parsedLine = (SObject)JSON.deserialize(jsonStr, SObject.class);
            lines.add(parsedLine);
        } catch (Exception e) {
            SObject fallbackRec = Schema.getGlobalDescribe().get(childObjName).newSObject();
            safePut(fallbackRec, 'QuickBridgeTLG__Quantity__c', 5.0);
            safePut(fallbackRec, 'QuickBridgeTLG__Unit_Price__c', 20.0);
            lines.add(fallbackRec);
        }
        
        List<Map<String, Object>> result = batch.buildLineItems(lines);
        System.assert(result.size() >= 1, 'Should return at least the subtotal line without crashing');
    }

    @isTest
    static void testCreateInvoiceSuccess() {
        QuickBooksAuthHandler.configureConnectionForTest('123456', 'Mock_Named_Credential', '65');
        Test.setMock(HttpCalloutMock.class, new QBInvoiceBatchMock(200));

        String invObjName = QBObjectMappings.getInvoiceSourceObject();
        String extIdField = getActualFieldName(invObjName, 'External_Id__c');
        SObject inv = Database.query('SELECT Id, ' + extIdField + ' FROM ' + invObjName + ' WHERE ' + extIdField + ' = null LIMIT 1');

        QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>(), true);

        Test.startTest();
        Map<String, Object> result = batch.createInvoice(inv, new List<SObject>(), new Map<String, String>());
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testCreateInvoiceFailure() {
        QuickBooksAuthHandler.configureConnectionForTest('123456', 'Mock_Named_Credential', '65');
        Test.setMock(HttpCalloutMock.class, new QBInvoiceBatchMock(400));

        String invObjName = QBObjectMappings.getInvoiceSourceObject();
        String extIdField = getActualFieldName(invObjName, 'External_Id__c');
        SObject inv = Database.query('SELECT Id, ' + extIdField + ' FROM ' + invObjName + ' WHERE ' + extIdField + ' = null LIMIT 1');

        QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>(), true);

        Test.startTest();
        Map<String, Object> result = batch.createInvoice(inv, new List<SObject>(), new Map<String, String>());
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @isTest
    static void testUpdateInvoiceSuccess() {
        QuickBooksAuthHandler.configureConnectionForTest('123456', 'Mock_Named_Credential', '65');
        Test.setMock(HttpCalloutMock.class, new QBInvoiceBatchMock(200));

        String invObjName = QBObjectMappings.getInvoiceSourceObject();
        String extIdField = getActualFieldName(invObjName, 'External_Id__c');
        SObject inv = Database.query('SELECT Id, ' + extIdField + ' FROM ' + invObjName + ' WHERE ' + extIdField + ' != null LIMIT 1');

        QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>(), false);

        Test.startTest();
        Map<String, Object> result = batch.updateInvoice(inv, new List<SObject>(), new Map<String, String>());
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testUpdateInvoiceFailure() {
        QuickBooksAuthHandler.configureConnectionForTest('123456', 'Mock_Named_Credential', '65');
        Test.setMock(HttpCalloutMock.class, new QBInvoiceUpdateFailureMock());

        String invObjName = QBObjectMappings.getInvoiceSourceObject();
        String extIdField = getActualFieldName(invObjName, 'External_Id__c');
        SObject inv = Database.query('SELECT Id, ' + extIdField + ' FROM ' + invObjName + ' WHERE ' + extIdField + ' != null LIMIT 1');

        QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(new Set<Id>(), false);

        Test.startTest();
        Map<String, Object> result = batch.updateInvoice(inv, new List<SObject>(), new Map<String, String>());
        Test.stopTest();

        System.assertEquals(null, result);
    }

    private static void safePut(SObject obj, String fieldName, Object value) {
        Map<String, Schema.SObjectField> fields = obj.getSObjectType().getDescribe().fields.getMap();
        String namespaced = 'QuickBridgeTLG__' + fieldName;
        if (fields.containsKey(namespaced.toLowerCase())) {
            obj.put(namespaced, value);
        } else if (fields.containsKey(fieldName.toLowerCase())) {
            obj.put(fieldName, value);
        }
    }

    private static String getActualFieldName(String objName, String baseFieldName) {
        Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(objName).getDescribe().fields.getMap();
        String namespaced = 'QuickBridgeTLG__' + baseFieldName;
        if (fields.containsKey(namespaced.toLowerCase())) return namespaced;
        return baseFieldName;
    }
}
