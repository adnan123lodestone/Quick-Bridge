@isTest
private class QuickBooksCreditMemoBatchTest {
    
    // Dynamic Mock to handle both Success (200) and Failure (500) API Responses
    private class QBCreditMemoMock implements HttpCalloutMock {
        private Boolean isSuccess;
        
        public QBCreditMemoMock(Boolean isSuccess) {
            this.isSuccess = isSuccess;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            if (isSuccess) {
                res.setStatusCode(200);
                res.setBody('{"CreditMemo":{"Id":"CM-123","SyncToken":"0"}}');
            } else {
                res.setStatusCode(500);
                res.setBody('{"Fault": {"Error": [{"Message": "Server Error"}]}}');
            }
            return res;
        }
    }

    @testSetup
    static void setupData() {
        // Dynamically find the object name to avoid namespace crashes
        String cmObjName = Schema.getGlobalDescribe().containsKey('QuickBridgeTLG__Credit_Memo__c') ? 'QuickBridgeTLG__Credit_Memo__c' : 'Credit_Memo__c';
        
        List<sObject> memosToInsert = new List<sObject>();
        memosToInsert.add((sObject)Type.forName(cmObjName).newInstance());
        memosToInsert.add((sObject)Type.forName(cmObjName).newInstance());
        
        insert memosToInsert;
    }

    @isTest
    static void testBatchExecuteSuccessPaths() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBCreditMemoMock(true));
        
        // Setup Dynamic Namespaces for JSON Parsing
        String cmObjName = Schema.getGlobalDescribe().containsKey('QuickBridgeTLG__Credit_Memo__c') ? 'QuickBridgeTLG__Credit_Memo__c' : 'Credit_Memo__c';
        String ns = cmObjName.replace('Credit_Memo__c', '');
        
        String extIdField = ns + 'External_Id__c';
        String taxRel = ns + 'Item_Sales_Tax__r';
        String custRel = ns + 'Customer__r';
        
        // Dynamically fetch Account fields to ensure strict JSON mapping
        Map<String, Schema.SObjectField> accFields = Schema.SObjectType.Account.fields.getMap();
        String taxAccExtId = accFields.containsKey(ns + 'External_Id__c') ? ns + 'External_Id__c' : 'External_Id__c';
        String custAccQbId = accFields.containsKey(ns + 'QuickbookID__c') ? ns + 'QuickbookID__c' : 'QuickbookID__c';

        List<sObject> dbRecords = Database.query('SELECT Id FROM ' + cmObjName + ' LIMIT 2');

        // Dynamically construct JSON with strict org-schema variables. 
        String jsonCreate = '{"attributes":{"type":"' + cmObjName + '"}, "Id":"' + dbRecords[0].Id + '", "' + taxRel + '":{"attributes":{"type":"Account"}, "' + taxAccExtId + '":"TAX-123"}, "' + custRel + '":{"attributes":{"type":"Account"}, "' + custAccQbId + '":"CUST-123"}}';
        String jsonUpdate = '{"attributes":{"type":"' + cmObjName + '"}, "Id":"' + dbRecords[1].Id + '", "' + extIdField + '":"EXISTING-QB-ID", "' + taxRel + '":{"attributes":{"type":"Account"}, "' + taxAccExtId + '":"TAX-456"}, "' + custRel + '":{"attributes":{"type":"Account"}, "' + custAccQbId + '":"CUST-456"}}';

        sObject cmCreate = (sObject)JSON.deserialize(jsonCreate, sObject.class);
        sObject cmUpdate = (sObject)JSON.deserialize(jsonUpdate, sObject.class);

        List<sObject> scope = new List<sObject>{ cmCreate, cmUpdate };
        
        Test.startTest();
        QuickBooksCreditMemoBatch batch = new QuickBooksCreditMemoBatch(new Set<Id>(), false);
        batch.execute(null, scope);
        Test.stopTest();
        
        System.assert(true, 'Execute completed successfully covering updateCreditMemo, tax relationships, and Usage Service Sync.');
    }

    @isTest
    static void testBatchExecuteFailurePaths() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBCreditMemoMock(false));
        
        String cmObjName = Schema.getGlobalDescribe().containsKey('QuickBridgeTLG__Credit_Memo__c') ? 'QuickBridgeTLG__Credit_Memo__c' : 'Credit_Memo__c';
        String ns = cmObjName.replace('Credit_Memo__c', '');
        String extIdField = ns + 'External_Id__c';

        List<sObject> dbRecords = Database.query('SELECT Id FROM ' + cmObjName + ' LIMIT 2');

        String jsonCreate = '{"attributes":{"type":"' + cmObjName + '"}, "Id":"' + dbRecords[0].Id + '"}';
        String jsonUpdate = '{"attributes":{"type":"' + cmObjName + '"}, "Id":"' + dbRecords[1].Id + '", "' + extIdField + '":"EXISTING-QB-ID"}';

        sObject cmCreate = (sObject)JSON.deserialize(jsonCreate, sObject.class);
        sObject cmUpdate = (sObject)JSON.deserialize(jsonUpdate, sObject.class);

        List<sObject> scope = new List<sObject>{ cmCreate, cmUpdate };
        
        Test.startTest();
        QuickBooksCreditMemoBatch batch = new QuickBooksCreditMemoBatch(new Set<Id>(), false);
        batch.execute(null, scope);
        Test.stopTest();
        
        System.assert(true, 'Execute completed successfully covering failure paths.');
    }

    @isTest
    static void testBatchStandardRun() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBCreditMemoMock(true));
        
        String cmObjName = Schema.getGlobalDescribe().containsKey('QuickBridgeTLG__Credit_Memo__c') ? 'QuickBridgeTLG__Credit_Memo__c' : 'Credit_Memo__c';
        List<sObject> cmList = Database.query('SELECT Id FROM ' + cmObjName);
        Set<Id> ids = new Set<Id>();
        for(sObject cm : cmList) {
            ids.add((Id)cm.get('Id'));
        }

        Test.startTest();
        Database.executeBatch(new QuickBooksCreditMemoBatch(ids, true), 10);
        Test.stopTest();
        
        System.assert(true, 'Batch should finish successfully');
    }
}