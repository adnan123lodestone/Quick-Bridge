@isTest
private class QBCustomerToAccountSyncBatchTest {

    private class QBCustomerBatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Customer":[{"Id":"CUST-1","DisplayName":"Customer One","CompanyName":"Acme","GivenName":"John","FamilyName":"Doe","PrimaryEmailAddr":{"Address":"john@example.com"},"PrimaryPhone":{"FreeFormNumber":"12345"},"BillAddr":{"Line1":"Street 1","City":"City","CountrySubDivisionCode":"ST","PostalCode":"12345","Country":"US"}}]}}');
                return res;
            }

            System.assert(!endpoint.contains('/customer/'), 'Customer batch execute should use serialized query payloads instead of per-record hydration callouts.');

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    private class QBCustomerSingleRecordMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            if (endpoint.contains('/customer/cust-1')) {
                res.setStatusCode(200);
                res.setBody('{"Customer":{"Id":"CUST-1","DisplayName":"Customer One","CompanyName":"Acme","GivenName":"John","FamilyName":"Doe","PrimaryEmailAddr":{"Address":"john@example.com"},"PrimaryPhone":{"FreeFormNumber":"12345"},"BillAddr":{"Line1":"Street 1","City":"City","CountrySubDivisionCode":"ST","PostalCode":"12345","Country":"US"}}}');
                return res;
            }
            res.setStatusCode(404);
            res.setBody('{"Fault":{"Error":[{"Message":"not found"}]}}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        insert new Account(Name = 'Seed Account');
    }

    @isTest
    static void testBatchStartExecuteFinish() {
        Test.setMock(HttpCalloutMock.class, new QBCustomerBatchMock());

        Test.startTest();
        Database.executeBatch(new QBCustomerToAccountSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        System.assertEquals(false, QBTriggerHandler.isAccountProcessing);

        Account syncedAccount = [
            SELECT Id, Name, QuickbookID__c, BillingStreet, BillingState
            FROM Account
            WHERE QuickbookID__c = 'CUST-1'
            LIMIT 1
        ];
        System.assertEquals('Customer One', syncedAccount.Name);
        System.assertEquals('CUST-1', syncedAccount.QuickbookID__c);
    }

    // Reproduces the production failure: an existing Business Account whose
    // QuickBooks customer no longer has a CompanyName. The batch must NOT flip it
    // to a Person Account inline (which would throw
    // "Business Account may not use Person Account field PersonEmail"); it should
    // stay a Business Account and upsert cleanly.
    private class QBNoCompanyNameMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Customer":[{"Id":"CUST-2","DisplayName":"Jane Roe","GivenName":"Jane","FamilyName":"Roe","PrimaryEmailAddr":{"Address":"jane@example.com"}}]}}');
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @isTest
    static void testExistingBusinessAccountWithoutCompanyNameStaysBusiness() {
        Id customerRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Customer').getRecordTypeId();
        insert new Account(
            Name = 'Existing Business',
            QuickbookID__c = 'CUST-2',
            RecordTypeId = customerRtId
        );

        Test.setMock(HttpCalloutMock.class, new QBNoCompanyNameMock());

        Test.startTest();
        Database.executeBatch(new QBCustomerToAccountSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        Account result = [
            SELECT Id, RecordTypeId
            FROM Account
            WHERE QuickbookID__c = 'CUST-2'
            LIMIT 1
        ];
        // Must remain a Business Account; the inline person-account flip is suppressed.
        System.assertEquals(customerRtId, result.RecordTypeId,
            'Existing Business Account must not be converted to a Person Account inline.');
    }

    @isTest
    static void testProcessSingleCustomerFallbackStillHydratesById() {
        Test.setMock(HttpCalloutMock.class, new QBCustomerSingleRecordMock());

        Test.startTest();
        new QBCustomerToAccountSyncBatch('2025-01-01').processSingleCustomer('CUST-1');
        Test.stopTest();

        System.assertEquals(1, [SELECT Count() FROM Account WHERE QuickbookID__c = 'CUST-1']);
    }
}