@isTest
private class QBAccountServiceTest {

    private class QBAccountServiceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String method = req.getMethod();

            if (method == 'GET' && endpoint.contains('/customer/')) {
                res.setStatusCode(200);
                res.setBody('{"Customer":{"Id":"321","SyncToken":"0","DisplayName":"Existing QB"}}');
                return res;
            }

            if (method == 'POST' && endpoint.contains('/customer')) {
                res.setStatusCode(200);
                res.setBody('{"Customer":{"Id":"123"}}');
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
            insert new Account(
                Name = 'QB Service Base',
                Description = 'Single setup account for batch-safe tests'
            );
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
        }
    }

    @isTest
    static void testSyncAccountToQuickBooksCreatePath() {
        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());

        Account acc = [
            SELECT Id, Name, QuickbookID__c, Description, Phone
            FROM Account
            WHERE Name = 'QB Service Base'
            LIMIT 1
        ];
        acc.QuickbookID__c = null;

        Test.startTest();
        QBAccountService.SyncResult result = QBAccountService.syncAccountToQuickBooks(acc, true);
        Test.stopTest();

        System.assertEquals(true, result.created);
        System.assertNotEquals(null, result.quickBooksId);
    }

    @isTest
    static void testSyncAccountToQuickBooksUpdatePath() {
        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());

        Account acc = [
            SELECT Id, Name, QuickbookID__c, Description, Phone
            FROM Account
            WHERE Name = 'QB Service Base'
            LIMIT 1
        ];
        acc.QuickbookID__c = '321';

        Test.startTest();
        QBAccountService.SyncResult result = QBAccountService.syncAccountToQuickBooks(acc, false);
        Test.stopTest();

        System.assertEquals(false, result.created);
        System.assertEquals('321', result.quickBooksId);
    }

    @isTest
    static void testSyncAccountsToQuickBooksBulkMethod() {
        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());

        List<Account> accounts = [
            SELECT Id, Name, QuickbookID__c, Description, Phone
            FROM Account
            WHERE Name = 'QB Service Base'
            LIMIT 1
        ];

        Test.startTest();
        QBAccountService.syncAccountsToQuickBooks(accounts, true);
        Test.stopTest();

        System.assertEquals(1, accounts.size());
    }

    @isTest
    static void testSyncAccountToQuickBooksNullAccountThrows() {
        Boolean didThrow = false;
        try {
            QBAccountService.syncAccountToQuickBooks(null, true);
        } catch (Exception e) {
            didThrow = true;
            System.assert(e.getMessage().contains('Account is required'));
        }
        System.assertEquals(true, didThrow);
    }
}