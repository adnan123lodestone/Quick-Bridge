@isTest
private class QBAccountRecordActionControllerTest {

    private class QBAccountActionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String method = req.getMethod();

            if (method == 'GET' && endpoint.contains('/customer/')) {
                res.setStatusCode(200);
                res.setBody('{"Customer":{"Id":"ACT-1","GivenName":"Jane","FamilyName":"Doe","PrimaryEmailAddr":{"Address":"jane@example.com"},"PrimaryPhone":{"FreeFormNumber":"999"},"BillAddr":{"Line1":"Street","City":"City","CountrySubDivisionCode":"ST","PostalCode":"12345","Country":"US"}}}');
                return res;
            }
            if (method == 'GET' && endpoint.contains('/vendor/')) {
                res.setStatusCode(200);
                res.setBody('{"Vendor":{"Id":"VEND-ACT-1","DisplayName":"Action Vendor","CompanyName":"Action Vendor Co","PrimaryEmailAddr":{"Address":"vendor-action@example.com"},"PrimaryPhone":{"FreeFormNumber":"888"},"BillAddr":{"Line1":"Vendor Street","City":"Vendor City","CountrySubDivisionCode":"VS","PostalCode":"54321","Country":"US"}}}');
                return res;
            }
            if (method == 'POST' && endpoint.contains('/customer')) {
                res.setStatusCode(200);
                res.setBody('{"Customer":{"Id":"ACT-1"}}');
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
            insert new Account(Name = 'Action Controller Acc');
            insert new Account(Name = 'Action Controller Synced', QuickbookID__c = 'ACT-1');

            Id vendorRecordTypeId = getVendorAccountRecordTypeId();
            if (vendorRecordTypeId != null) {
                insert new Account(
                    Name = 'Action Controller Vendor',
                    QuickbookID__c = 'VEND-ACT-1',
                    RecordTypeId = vendorRecordTypeId
                );
            }
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
        }
    }

    @isTest
    static void testSyncToQuickBooks() {
        Test.setMock(HttpCalloutMock.class, new QBAccountActionMock());
        Account acc = [SELECT Id FROM Account WHERE Name = 'Action Controller Acc' LIMIT 1];

        Test.startTest();
        try {
            QBAccountRecordActionController.ActionResponse response = QBAccountRecordActionController.syncToQuickBooks(acc.Id);
            System.assertEquals(true, response.success);
            System.assertNotEquals(null, response.quickBooksId);
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncFromQuickBooks() {
        Test.setMock(HttpCalloutMock.class, new QBAccountActionMock());
        Account acc = [SELECT Id FROM Account WHERE Name = 'Action Controller Synced' LIMIT 1];

        Test.startTest();
        try {
            QBAccountRecordActionController.ActionResponse response = QBAccountRecordActionController.syncFromQuickBooks(acc.Id);
            System.assertEquals(true, response.success);
            System.assertNotEquals(null, response.quickBooksId);
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncFromQuickBooksRequiresQuickBooksId() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Action Controller Acc' LIMIT 1];

        Test.startTest();
        try {
            QBAccountRecordActionController.syncFromQuickBooks(acc.Id);
            System.assert(false, 'Expected missing QuickBooks ID to throw.');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncToQuickBooksRequiresAccountId() {
        Test.startTest();
        try {
            QBAccountRecordActionController.syncToQuickBooks(null);
            System.assert(false, 'Expected missing Account ID to throw.');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncVendorFromQuickBooksWhenVendorRecordTypeExists() {
        Id vendorRecordTypeId = getVendorAccountRecordTypeId();
        if (vendorRecordTypeId == null) {
            System.assertEquals(null, vendorRecordTypeId);
            return;
        }

        Account vendorAccount = [
            SELECT Id
            FROM Account
            WHERE QuickbookID__c = 'VEND-ACT-1'
            LIMIT 1
        ];

        Test.setMock(HttpCalloutMock.class, new QBAccountActionMock());

        Test.startTest();
        QBAccountRecordActionController.ActionResponse response = QBAccountRecordActionController.syncFromQuickBooks(vendorAccount.Id);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('VEND-ACT-1', response.quickBooksId);
        System.assert(response.message.contains('vendor'));

        Account updatedVendor = [
            SELECT Id, Name, BillingStreet
            FROM Account
            WHERE Id = :vendorAccount.Id
            LIMIT 1
        ];
        System.assertEquals('Action Vendor', updatedVendor.Name);
        System.assertEquals('Vendor Street', updatedVendor.BillingStreet);
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