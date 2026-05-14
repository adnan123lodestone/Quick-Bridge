@isTest
private class QBVendorToAccountSyncBatchTest {

    private class QBVendorBatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Vendor":[{"Id":"VEND-1"}]}}');
                return res;
            }

            if (endpoint.contains('/vendor/vend-1')) {
                res.setStatusCode(200);
                res.setBody('{"Vendor":{"Id":"VEND-1","DisplayName":"Vendor One","CompanyName":"Vendor Co","PrimaryEmailAddr":{"Address":"vendor@example.com"},"PrimaryPhone":{"FreeFormNumber":"555-1212"},"BillAddr":{"Line1":"Vendor Street","City":"Vendor City","CountrySubDivisionCode":"VS","PostalCode":"54321","Country":"US"}}}');
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
                res.setBody('{"QueryResponse":{"Vendor":[{"Id":"VEND-EXIST"},{"Id":"VEND-COMPANY"}]}}');
                return res;
            }

            if (endpoint.contains('/vendor/vend-exist')) {
                res.setStatusCode(200);
                res.setBody('{"Vendor":{"Id":"VEND-EXIST","CompanyName":"Vendor Existing Co","Balance":12.34}}');
                return res;
            }

            if (endpoint.contains('/vendor/vend-company')) {
                res.setStatusCode(200);
                res.setBody('{"Vendor":{"Id":"VEND-COMPANY","CompanyName":"Vendor Company Only","Balance":56.78}}');
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
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
        Test.setMock(HttpCalloutMock.class, new QBVendorBatchMock());

        Test.startTest();
        Database.executeBatch(new QBVendorToAccountSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        System.assertEquals(false, QBTriggerHandler.isAccountProcessing);

        Account syncedAccount = [
            SELECT Id, Name, QuickbookID__c, BillingStreet, BillingState, RecordTypeId
            FROM Account
            WHERE QuickbookID__c = 'VEND-1'
            LIMIT 1
        ];
        System.assertEquals('Vendor One', syncedAccount.Name);
        System.assertEquals('VEND-1', syncedAccount.QuickbookID__c);
        System.assertEquals('Vendor Street', syncedAccount.BillingStreet);
        System.assertEquals('VS', syncedAccount.BillingState);

        Id vendorRecordTypeId = getVendorAccountRecordTypeId();
        if (vendorRecordTypeId != null) {
            System.assertEquals(vendorRecordTypeId, syncedAccount.RecordTypeId);
        }
    }

    @isTest
    static void testDefaultConstructorWithNoVendors() {
        Test.setMock(HttpCalloutMock.class, new QBVendorEmptyQueryMock());

        Test.startTest();
        Database.executeBatch(new QBVendorToAccountSyncBatch(), 1);
        Test.stopTest();

        System.assertEquals(false, QBTriggerHandler.isAccountProcessing);
    }

    @isTest
    static void testExistingAccountAndVendorNameFallback() {
        Test.setMock(HttpCalloutMock.class, new QBVendorCompanyNameMock());

        Test.startTest();
        Database.executeBatch(new QBVendorToAccountSyncBatch('2025-01-01'), 2);
        Test.stopTest();

        Account syncedAccount = [
            SELECT Id, Name, QuickbookID__c
            FROM Account
            WHERE QuickbookID__c = 'VEND-EXIST'
            LIMIT 1
        ];
        System.assertEquals('Existing Vendor Account', syncedAccount.Name);
        System.assertEquals('VEND-EXIST', syncedAccount.QuickbookID__c);

        Account companyOnlyVendor = [
            SELECT Id, Name, QuickbookID__c
            FROM Account
            WHERE QuickbookID__c = 'VEND-COMPANY'
            LIMIT 1
        ];
        System.assertEquals('Vendor Company Only', companyOnlyVendor.Name);
        System.assertEquals('VEND-COMPANY', companyOnlyVendor.QuickbookID__c);
    }

    private static Id getVendorAccountRecordTypeId() {
        List<RecordType> vendorRecordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account'
            AND IsActive = true
            AND (Name = 'Vendor' OR DeveloperName = 'Vendor')
            LIMIT 1
        ];

        return vendorRecordTypes.isEmpty() ? null : vendorRecordTypes[0].Id;
    }
}