@isTest
private class QBOItemSalesTaxBatchTest {

    private class QBMock implements HttpCalloutMock {
        private String scenario;
        
        public QBMock(String scenario) {
            this.scenario = scenario;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            if (scenario == 'Error') {
                res.setStatusCode(400);
                res.setBody('{"Fault": {"Error": [{"Message": "API Request Failed"}]}}');
            } else if (scenario == 'Empty') {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse": {}}'); 
            } else if (scenario == 'Pagination') {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse": {"TaxCode": [{"Id": "TAX-1", "Name": "Tax1", "Active": true, "SalesTaxRateList": {"TaxRateDetail": []}}], "maxResults": 1, "totalCount": 2}}');
            } else if (scenario == 'UpsertFail') {
                res.setStatusCode(200);
                String longName = 'A'.repeat(300);
                res.setBody('{"QueryResponse": {"TaxCode": [{"Id": "TAX-FAIL", "Name": "' + longName + '", "Active": true}], "maxResults": 1, "totalCount": 1}}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse": {"TaxCode": [{"Id": "TAX-123", "Name": "Standard Tax", "Active": true, "Description": "State Tax", "SalesTaxRateList": {"TaxRateDetail": [{"TaxRateRef": {"value": "8.5"}}]}}], "maxResults": 1, "totalCount": 1}}');
            }
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

        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'QuickBookSandbox', '65');
    }

    @isTest
    static void testValidExecution() {
        Test.setMock(HttpCalloutMock.class, new QBMock('Valid'));
        
        Test.startTest();
        Id jobId = Database.executeBatch(new QBOItemSalesTaxBatch(), 1);
        Test.stopTest();
        
        System.assertNotEquals(null, jobId);
        Integer errorLogs = [SELECT count() FROM Error_Log__c];
        System.assertEquals(0, errorLogs);
    }

    @isTest
    static void testPaginationAndFinish() {
        Test.setMock(HttpCalloutMock.class, new QBMock('Pagination'));
        
        Test.startTest();
        Id jobId = Database.executeBatch(new QBOItemSalesTaxBatch(), 1);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        Integer errorLogs = [SELECT count() FROM Error_Log__c];
        System.assertEquals(0, errorLogs);
    }

    @isTest
    static void testEmptyResponse() {
        Test.setMock(HttpCalloutMock.class, new QBMock('Empty'));
        
        Test.startTest();
        Id jobId = Database.executeBatch(new QBOItemSalesTaxBatch(), 1);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        Integer errorLogs = [SELECT count() FROM Error_Log__c];
        System.assertEquals(0, errorLogs);
    }

    @isTest
    static void testApiError() {
        Test.setMock(HttpCalloutMock.class, new QBMock('Error'));
        
        Test.startTest();
        Id jobId = Database.executeBatch(new QBOItemSalesTaxBatch(), 1);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        Integer errorLogs = [SELECT count() FROM Error_Log__c];
        System.assert(errorLogs >= 1);
    }

    @isTest
    static void testUpsertFailure() {
        Test.setMock(HttpCalloutMock.class, new QBMock('UpsertFail'));
        
        Test.startTest();
        Id jobId = Database.executeBatch(new QBOItemSalesTaxBatch(), 1);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        Integer errorLogs = [SELECT count() FROM Error_Log__c];
        System.assert(errorLogs >= 1);
    }
}