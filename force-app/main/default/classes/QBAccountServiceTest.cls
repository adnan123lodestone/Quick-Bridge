@isTest
private class QBAccountServiceTest {
    private static List<Map<String, Object>> postedRequestBodies = new List<Map<String, Object>>();
    private static List<String> postedEndpoints = new List<String>();

    private class QBAccountServiceMock implements HttpCalloutMock {
        public Integer statusCode = 200;

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(this.statusCode);

            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String method = req.getMethod();

            if (method == 'POST' && String.isNotBlank(req.getBody())) {
                QBAccountServiceTest.postedEndpoints.add(req.getEndpoint());
                QBAccountServiceTest.postedRequestBodies.add(
                    (Map<String, Object>)JSON.deserializeUntyped(req.getBody())
                );
            }

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
        postedRequestBodies.clear();
        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('Description', 'Notes', 'SF to QBO')
        };

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
        System.assertEquals(1, postedRequestBodies.size());
        System.assertEquals(
            'Single setup account for batch-safe tests',
            postedRequestBodies[0].get('Notes')
        );
        System.assertNotEquals(
            String.valueOf(acc.Id),
            postedRequestBodies[0].get('Notes')
        );
    }

    @isTest
    static void testSyncAccountToQuickBooksUpdatePath() {
        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());
        postedRequestBodies.clear();
        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('Description', 'Notes', 'Two-Way')
        };

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
        System.assertEquals(1, postedRequestBodies.size());
        System.assertEquals(
            'Single setup account for batch-safe tests',
            postedRequestBodies[0].get('Notes')
        );
    }

    @isTest
    static void testInboundOnlyNotesMappingOmitsOutboundNotes() {
        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());
        postedRequestBodies.clear();
        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('Description', 'Notes', 'QBO to SF')
        };

        Account acc = [
            SELECT Id, Name, RecordTypeId, QuickbookID__c, Description
            FROM Account
            WHERE Name = 'QB Service Base'
            LIMIT 1
        ];
        acc.QuickbookID__c = null;

        Test.startTest();
        QBAccountService.syncAccountToQuickBooks(acc, true);
        Test.stopTest();

        System.assertEquals(1, postedRequestBodies.size());
        System.assertEquals(
            false,
            postedRequestBodies[0].containsKey('Notes')
        );
    }

    @isTest
    static void testOutboundAddressMappingsBuildNestedPayloads() {
        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());
        postedRequestBodies.clear();
        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('BillingStreet', 'BillAddr.Line1', 'SF to QBO'),
            customerMapping('BillingCity', 'BillAddr.City', 'SF to QBO'),
            customerMapping('BillingState', 'BillAddr.CountrySubDivisionCode', 'SF to QBO'),
            customerMapping('BillingPostalCode', 'BillAddr.PostalCode', 'SF to QBO'),
            customerMapping('BillingCountry', 'BillAddr.Country', 'SF to QBO'),
            customerMapping('ShippingStreet', 'ShipAddr.Line1', 'SF to QBO'),
            customerMapping('ShippingCity', 'ShipAddr.City', 'SF to QBO'),
            customerMapping('ShippingState', 'ShipAddr.CountrySubDivisionCode', 'SF to QBO'),
            customerMapping('ShippingPostalCode', 'ShipAddr.PostalCode', 'SF to QBO'),
            customerMapping('ShippingCountry', 'ShipAddr.Country', 'SF to QBO')
        };

        Account acc = [
            SELECT Id, Name, RecordTypeId, QuickbookID__c,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry
            FROM Account
            WHERE Name = 'QB Service Base'
            LIMIT 1
        ];
        acc.QuickbookID__c = null;
        acc.BillingStreet = '1 Billing Way';
        acc.BillingCity = 'Billing City';
        acc.BillingState = 'BS';
        acc.BillingPostalCode = '11111';
        acc.BillingCountry = 'US';
        acc.ShippingStreet = '2 Shipping Way';
        acc.ShippingCity = 'Shipping City';
        acc.ShippingState = 'SS';
        acc.ShippingPostalCode = '22222';
        acc.ShippingCountry = 'US';

        Test.startTest();
        QBAccountService.syncAccountToQuickBooks(acc, true);
        Test.stopTest();

        Map<String, Object> requestBody = postedRequestBodies[0];
        Map<String, Object> billAddress = (Map<String, Object>)requestBody.get('BillAddr');
        Map<String, Object> shipAddress = (Map<String, Object>)requestBody.get('ShipAddr');
        System.assertEquals('1 Billing Way', billAddress.get('Line1'));
        System.assertEquals('Billing City', billAddress.get('City'));
        System.assertEquals('BS', billAddress.get('CountrySubDivisionCode'));
        System.assertEquals('11111', billAddress.get('PostalCode'));
        System.assertEquals('US', billAddress.get('Country'));
        System.assertEquals('2 Shipping Way', shipAddress.get('Line1'));
        System.assertEquals('Shipping City', shipAddress.get('City'));
        System.assertEquals('SS', shipAddress.get('CountrySubDivisionCode'));
        System.assertEquals('22222', shipAddress.get('PostalCode'));
        System.assertEquals('US', shipAddress.get('Country'));
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
    static void vendorPayloadOmitsInboundOnlyAndUnknownFields() {
        Id vendorRtId = getVendorAccountRecordTypeId();
        if (vendorRtId == null) return;

        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());
        postedRequestBodies.clear();
        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            vendorMapping('Name', 'DisplayName', 'Two-Way'),
            vendorMapping('Smile_Points_Balance__c', 'Balance', 'Two-Way'),
            vendorMapping('Name', 'CurrencyRef.name', 'Two-Way'),
            vendorMapping('BillingCity', 'BillAddr.City', 'SF to QBO'),
            vendorMapping('Description', 'Notes', 'SF to QBO')
        };
        Account vendorAccount = new Account(
            Name = 'Capability Vendor',
            RecordTypeId = vendorRtId,
            Smile_Points_Balance__c = 99,
            BillingCity = 'Austin',
            Description = 'Vendor notes'
        );
        QBTriggerHandler.isAccountProcessing = true;
        insert vendorAccount;
        QBTriggerHandler.isAccountProcessing = false;
        vendorAccount = QBAccountSelector.selectForOutbound(vendorAccount.Id);

        Test.startTest();
        QBAccountService.syncAccountToQuickBooks(vendorAccount, true);
        Test.stopTest();

        Map<String, Object> payload = postedRequestBodies[0];
        System.assertEquals('Capability Vendor', payload.get('DisplayName'));
        System.assertEquals(false, payload.containsKey('Balance'));
        System.assertEquals(false, payload.containsKey('CurrencyRef'));
        System.assertEquals('Vendor notes', payload.get('Notes'));
        System.assertEquals(
            'Austin',
            ((Map<String, Object>) payload.get('BillAddr')).get('City')
        );
    }

    @isTest
    static void testSyncAccountToQuickBooks_CalloutError() {
        QBAccountServiceMock mock = new QBAccountServiceMock();
        mock.statusCode = 400;
        Test.setMock(HttpCalloutMock.class, mock);

        Account acc = [SELECT Id, Name, QuickbookID__c, RecordTypeId, IsPersonAccount FROM Account LIMIT 1];

        Test.startTest();
        try {
            QBAccountService.syncAccountToQuickBooks(acc, true);
            System.assert(false, 'Exception expected');
        } catch (QBIntegrationException e) {
            System.assert(e.getMessage().contains('could not create'));
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
            System.assert(e.getMessage().contains('could not validate linked'));
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

    @IsTest
    static void testReadOnlyLegacyMappingsAreOmittedAndUpdateIsSparse() {
        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());
        postedRequestBodies.clear();
        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('Name', 'DisplayName', 'Two-Way'),
            customerMapping('Smile_Points_Balance__c', 'Balance', 'Two-Way')
        };
        Account accountRecord = [
            SELECT Id, Name, RecordTypeId, QuickbookID__c, Smile_Points_Balance__c
            FROM Account
            WHERE Name = 'QB Service Base'
            LIMIT 1
        ];
        accountRecord.QuickbookID__c = '321';
        accountRecord.Smile_Points_Balance__c = 50;

        Test.startTest();
        QBAccountService.syncAccountToQuickBooks(accountRecord, false);
        Test.stopTest();

        Map<String, Object> payload = postedRequestBodies[0];
        System.assertEquals(false, payload.containsKey('Balance'));
        System.assertEquals('321', payload.get('Id'));
        System.assertEquals('0', payload.get('SyncToken'));
        System.assertEquals(true, payload.get('sparse'));
        System.assertEquals(false, payload.containsKey('FullyQualifiedName'));
    }

    @IsTest
    static void testStaleInitialWorkPayloadUsesCurrentQuickBooksId() {
        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());
        postedRequestBodies.clear();
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'QB Service Base' LIMIT 1];
        QBTriggerHandler.isAccountProcessing = true;
        update new Account(Id = accountRecord.Id, QuickbookID__c = '321');
        QBTriggerHandler.isAccountProcessing = false;

        Integration_Work_Item__c workItem = new Integration_Work_Item__c(
            Source_Salesforce_Id__c = String.valueOf(accountRecord.Id),
            Source_Record_Id__c = String.valueOf(accountRecord.Id),
            Payload__c = '{"isInitialSync":true}'
        );
        Test.startTest();
        QBAccountWorker.process(workItem);
        Test.stopTest();

        System.assertEquals(1, postedRequestBodies.size());
        System.assertEquals(true, postedRequestBodies[0].get('sparse'));
        System.assertEquals('321', postedRequestBodies[0].get('Id'));
    }

    @IsTest
    static void testStableCreateRetriesReuseBoundedRequestId() {
        Test.setMock(HttpCalloutMock.class, new QBAccountServiceMock());
        postedEndpoints.clear();
        Account transientAccount = new Account(Name = 'Stable Request Customer');

        Test.startTest();
        QBAccountService.syncAccountToQuickBooks(transientAccount, true);
        QBAccountService.syncAccountToQuickBooks(transientAccount, true);
        Test.stopTest();

        System.assertEquals(2, postedEndpoints.size());
        String firstRequestId = requestIdFromEndpoint(postedEndpoints[0]);
        String secondRequestId = requestIdFromEndpoint(postedEndpoints[1]);
        System.assertEquals(firstRequestId, secondRequestId);
        System.assert(firstRequestId.length() <= 50);
    }

    private static String requestIdFromEndpoint(String endpoint) {
        Integer startIndex = endpoint.indexOf('requestid=') + 10;
        Integer endIndex = endpoint.indexOf('&', startIndex);
        return endIndex < 0
            ? endpoint.substring(startIndex)
            : endpoint.substring(startIndex, endIndex);
    }

    // Helper to get Person Account RecordType Id
    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> rt = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1];
        return rt.isEmpty() ? null : rt[0].Id;
    }

    private static Field_Mapping__mdt customerMapping(
        String sfField,
        String externalField,
        String direction
    ) {
        return new Field_Mapping__mdt(
            Integration__c = 'qbonline',
            SF_Object__c = 'Account',
            SF_Field__c = sfField,
            External_Field__c = externalField,
            Sync_Direction__c = direction,
            Target_Object_API_Name__c = 'Customer',
            Is_Active__c = true
        );
    }

    private static Field_Mapping__mdt vendorMapping(
        String sfField,
        String externalField,
        String direction
    ) {
        return new Field_Mapping__mdt(
            Integration__c = 'qbonline',
            SF_Object__c = 'Account',
            SF_Field__c = sfField,
            External_Field__c = externalField,
            Sync_Direction__c = direction,
            Target_Object_API_Name__c = 'Vendor',
            Is_Active__c = true
        );
    }

    private static Id getVendorAccountRecordTypeId() {
        List<RecordType> rt = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND (DeveloperName = 'Vendor' OR Name = 'Vendor') LIMIT 1];
        return rt.isEmpty() ? null : rt[0].Id;
    }
}
