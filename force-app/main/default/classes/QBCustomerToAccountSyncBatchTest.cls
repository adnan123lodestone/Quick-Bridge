@isTest
private class QBCustomerToAccountSyncBatchTest {

    private class QBCustomerBatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Customer":[{"Id":"CUST-1"}]}}');
                return res;
            }

            if (endpoint.contains('/customer/cust-1')) {
                res.setStatusCode(200);
                res.setBody('{"Customer":{"Id":"CUST-1","DisplayName":"Customer One","CompanyName":"Acme","GivenName":"John","FamilyName":"Doe","PrimaryEmailAddr":{"Address":"john@example.com"},"PrimaryPhone":{"FreeFormNumber":"12345"},"BillAddr":{"Line1":"Street 1","City":"City","CountrySubDivisionCode":"ST","PostalCode":"12345","Country":"US"}}}');
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
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
        System.assertEquals('Street 1', syncedAccount.BillingStreet);
        System.assertEquals('ST', syncedAccount.BillingState);
    }
}