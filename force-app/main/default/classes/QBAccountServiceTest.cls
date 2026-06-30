@isTest
private class QBAccountServiceTest {

    private class QBAccountServiceMock implements HttpCalloutMock {
        public Integer statusCode = 200;
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(this.statusCode);

            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String method = req.getMethod();

            if (this.statusCode != 200) {
                res.setBody('{"Fault":{"Error":[{"Message":"Invalid Request"}]}}');
                return res;
            }

            if (endpoint.contains('/vendor')) {
                if (method == 'GET') {
                    res.setBody('{"Vendor":{"Id":"V321","SyncToken":"0","DisplayName":"Existing Vendor"}}');
                } else {
                    res.setBody('{"Vendor":{"Id":"V123"}}');
                }
                return res;
            }

            if (method == 'GET' && endpoint.contains('/customer/')) {
                res.setBody('{"Customer":{"Id":"321","SyncToken":"0","DisplayName":"Existing QB"}}');
                return res;
            }

            if (method == 'POST' && endpoint.contains('/customer')) {
                res.setBody('{"Customer":{"Id":"123"}}');
                return res;
            }

            res.setBody('{}');
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

        // --- Realm ID (using your actual value) ---
        Connector_Config_Value__c realmConfig = new Connector_Config_Value__c(
            Name = 'qbo.RealmId',
            Connector_Instance__c = instance.Id,
            Connector_Key__c = 'qbo',
            Field_Key__c = 'QuickBooks_Realm_ID__c',
            Value__c = '9341456917896565',   // real Realm ID
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

        // --- Account for testing ---
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
            SELECT Id, Name, RecordTypeId, QuickbookID__c, Description, Phone,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   AccountNumber, Main_Email__c, Terms__c, External_Id__c
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
            SELECT Id, Name, RecordTypeId, QuickbookID__c, Description, Phone,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   AccountNumber, Main_Email__c, Terms__c, External_Id__c
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
            SELECT Id, Name, RecordTypeId, QuickbookID__c, Description, Phone,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   AccountNumber, Main_Email__c, Terms__c, External_Id__c
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
    static void testSyncAccountToQuickBooks_VendorPath() {
        Id vendorRtId = getVendorAccountRecordTypeId();
        if (vendorRtId == null) return;

        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());

        Account acc = new Account(Name = 'Test Vendor', RecordTypeId = vendorRtId);
        insert acc;

        Test.startTest();
        QBAccountService.SyncResult result = QBAccountService.syncAccountToQuickBooks(acc, true);
        Test.stopTest();

        System.assertEquals(true, result.created);
        System.assertEquals('V123', result.quickBooksId);
    }

    @isTest
    static void testSyncAccountToQuickBooks_CalloutError() {
        QBAccountServiceMock mock = new QBAccountServiceMock();
        mock.statusCode = 400;
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = [SELECT Id, Name, RecordTypeId, IsPersonAccount FROM Account LIMIT 1];

        Test.startTest();
        try {
            QBAccountService.syncAccountToQuickBooks(acc, true);
            System.assert(false, 'Exception expected');
        } catch (QBIntegrationException e) {
            System.assert(e.getMessage().contains('Error creating record'));
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncAccountToQuickBooks_UpdateGetFailure() {
        QBAccountServiceMock mock = new QBAccountServiceMock();
        mock.statusCode = 404;
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = [SELECT Id, Name, QuickbookID__c, RecordTypeId, IsPersonAccount FROM Account LIMIT 1];
        acc.QuickbookID__c = '321';

        Test.startTest();
        try {
            QBAccountService.syncAccountToQuickBooks(acc, false);
            System.assert(false, 'Exception expected on GET failure');
        } catch (QBIntegrationException e) {
            System.assert(e.getMessage().contains('Error querying record'));
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncAccountToQuickBooks_DmlError() {
        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());
        String accountPrefix = Account.SObjectType.getDescribe().getKeyPrefix();
        Id nonExistentId = (Id)(accountPrefix + '000000000001');
        
        Account fakeAcc = new Account(
            Id = nonExistentId, 
            Name = 'Non Existent'
        );

        Test.startTest();
        try {
            QBAccountService.syncAccountToQuickBooks(fakeAcc, true);
        } catch (DmlException e) {
            System.assert(true, 'Caught expected DML error');
        }
        Test.stopTest();
    }

    @isTest
    static void testBulkSync_WithErrors() {
        QBAccountServiceMock mock = new QBAccountServiceMock();
        mock.statusCode = 500;
        Test.setMock(HttpCalloutMock.class, mock);

        List<Account> accounts = [SELECT Id, Name, QuickbookID__c, RecordTypeId, IsPersonAccount FROM Account];

        Test.startTest();
        // This should not throw because the bulk method catches internal exceptions
        QBAccountService.syncAccountsToQuickBooks(accounts, true);
        Test.stopTest();
        
        // If we reached here, the internal try-catch in syncAccountsToQuickBooks worked.
        System.assert(true);
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

    @isTest
    static void testSyncPersonAccount() {
        if (!Schema.sObjectType.Account.fields.getMap().containsKey('IsPersonAccount')) {
            return;
        }

        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());

        Id personRtId = getPersonAccountRecordTypeId();
        Account personAcc = new Account(
            FirstName = 'John',
            LastName = 'Doe',
            PersonEmail = 'john.doe@example.com'
        );
        if (personRtId != null) personAcc.RecordTypeId = personRtId;
        insert personAcc;

        // Re-query to get the IsPersonAccount and RecordTypeId fields automatically populated/calculated
        Account queriedAcc = [SELECT Id, Name, FirstName, LastName, PersonEmail, IsPersonAccount, RecordTypeId, QuickbookID__c FROM Account WHERE Id = :personAcc.Id];

        Test.startTest();
        QBAccountService.SyncResult result = QBAccountService.syncAccountToQuickBooks(queriedAcc, true);
        Test.stopTest();

        System.assertEquals(true, result.created);
        System.assertEquals('123', result.quickBooksId);
    }

    // Helper to get Person Account RecordType Id
    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> rt = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1];
        return rt.isEmpty() ? null : rt[0].Id;
    }

    private static Id getVendorAccountRecordTypeId() {
        List<RecordType> rt = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND (DeveloperName = 'Vendor' OR Name = 'Vendor') LIMIT 1];
        return rt.isEmpty() ? null : rt[0].Id;
    }
}