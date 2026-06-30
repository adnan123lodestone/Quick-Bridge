@isTest
private class QBVendorToAccountSyncBatchTest {

    private class QBVendorBatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Vendor":[{"Id":"VEND-1","DisplayName":"Vendor One","CompanyName":"Vendor Co","PrimaryEmailAddr":{"Address":"vendor@example.com"},"PrimaryPhone":{"FreeFormNumber":"555-1212"},"BillAddr":{"Line1":"Vendor Street","City":"Vendor City","CountrySubDivisionCode":"VS","PostalCode":"54321","Country":"US"}}]}}');
                return res;
            }
            if (endpoint.contains('/vendor/vend-sync')) {
                res.setStatusCode(200);
                res.setBody('{"Vendor":{"Id":"VEND-SYNC","DisplayName":"Single Vendor","CompanyName":"Sync Co"}}');
                return res;
            }
            if (endpoint.contains('/vendor/vend-fail')) {
                res.setStatusCode(404);
                res.setBody('{"Fault":{"Error":[{"Message":"Not Found"}]}}');
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    private class QBVendorEmptyQueryMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"QueryResponse":{}}');
            return res;
        }
    }

    private class QBVendorCompanyNameMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Vendor":[{"Id":"VEND-EXIST","CompanyName":"Vendor Existing Co","Balance":12.34},{"Id":"VEND-COMPANY","CompanyName":"Vendor Company Only","Balance":56.78},{"Id":"VEND-PRINT","PrintOnCheckName":"Print Vendor"},{"Id":"VEND-NAME","GivenName":"John","FamilyName":"Doe"},{"Id":"VEND-NONAME"}]}}');
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    private class QBVendorErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Server Error');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        QBTriggerHandler.isAccountProcessing = true;
        try {
            insert new Account(Name = 'Existing Vendor Account', QuickbookID__c = 'VEND-EXIST');
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
        }
    }

    @isTest
    static void testBatchStartExecuteFinish() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBVendorBatchMock());

        Test.startTest();
        Database.executeBatch(new QBVendorToAccountSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        System.assertEquals(false, QBTriggerHandler.isAccountProcessing);
        Account syncedAccount = [SELECT Id, Name, QuickbookID__c, BillingStreet FROM Account WHERE QuickbookID__c = 'VEND-1' LIMIT 1];
        System.assertEquals('Vendor One', syncedAccount.Name);
        System.assertEquals('VEND-1', syncedAccount.QuickbookID__c);
    }

    @isTest
    static void testDefaultConstructorWithNoVendors() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBVendorEmptyQueryMock());

        Test.startTest();
        Database.executeBatch(new QBVendorToAccountSyncBatch(), 1);
        Test.stopTest();
        System.assertEquals(false, QBTriggerHandler.isAccountProcessing);
    }

    @isTest
    static void testExistingAccountAndVendorNameFallbacks() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBVendorCompanyNameMock());

        Test.startTest();
        Database.executeBatch(new QBVendorToAccountSyncBatch('2025-01-01'), 5);
        Test.stopTest();

        Account existing = [SELECT Name FROM Account WHERE QuickbookID__c = 'VEND-EXIST' LIMIT 1];
        System.assertEquals('Existing Vendor Account', existing.Name);
        Account company = [SELECT Name FROM Account WHERE QuickbookID__c = 'VEND-COMPANY' LIMIT 1];
        System.assertEquals('Vendor Company Only', company.Name);
        Account print = [SELECT Name FROM Account WHERE QuickbookID__c = 'VEND-PRINT' LIMIT 1];
        System.assertEquals('Print Vendor', print.Name);
        Account fullName = [SELECT Name FROM Account WHERE QuickbookID__c = 'VEND-NAME' LIMIT 1];
        System.assertEquals('John Doe', fullName.Name);
        Account noName = [SELECT Name FROM Account WHERE QuickbookID__c = 'VEND-NONAME' LIMIT 1];
        System.assertEquals('Unknown Vendor', noName.Name);
    }

    @isTest
    static void testSyncVendorFromQBOSuccess() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBVendorBatchMock());
        QBVendorToAccountSyncBatch batch = new QBVendorToAccountSyncBatch();

        Test.startTest();
        batch.syncVendorFromQBO('VEND-SYNC');
        Test.stopTest();

        Account synced = [SELECT Id, Name, QuickbookID__c FROM Account WHERE QuickbookID__c = 'VEND-SYNC' LIMIT 1];
        System.assertEquals('Single Vendor', synced.Name);
    }

    @isTest
    static void testSyncVendorFromQBOFailure() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBVendorBatchMock());
        QBVendorToAccountSyncBatch batch = new QBVendorToAccountSyncBatch();

        Boolean threw = false;
        Test.startTest();
        try {
            batch.syncVendorFromQBO('VEND-FAIL');
        } catch (CalloutException e) {
            threw = true;
            System.assert(e.getMessage().contains('Unable to fetch vendor'));
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testBatchQueryErrorLogsException() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBVendorErrorMock());

        Test.startTest();
        Database.executeBatch(new QBVendorToAccountSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        List<Error_Log__c> logs = [SELECT Id FROM Error_Log__c];
        System.assert(!logs.isEmpty());
    }

    @isTest
    static void testProcessVendorWithInvalidPayload() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new QBVendorBatchMock());

        QBVendorToAccountSyncBatch batch = new QBVendorToAccountSyncBatch();
        Test.startTest();
        Database.executeBatch(batch, 1);
        Test.stopTest();
    }
}