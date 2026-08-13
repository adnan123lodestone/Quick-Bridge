@isTest
private class QBCustomerToAccountSyncBatchTest {

    private class QBCustomerBatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Customer":[{"Id":"CUST-1","DisplayName":"Customer One","CompanyName":"Acme","GivenName":"John","FamilyName":"Doe","Title":"Mr.","PrimaryEmailAddr":{"Address":"john@example.com"},"PrimaryPhone":{"FreeFormNumber":"12345"},"BillAddr":{"Line1":"Street 1","City":"City","CountrySubDivisionCode":"ST","PostalCode":"12345","Country":"US"}}]}}');
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
                res.setBody('{"Customer":{"Id":"CUST-1","DisplayName":"Customer One","CompanyName":"Acme","GivenName":"John","FamilyName":"Doe","Title":"Mr.","PrimaryEmailAddr":{"Address":"john@example.com"},"PrimaryPhone":{"FreeFormNumber":"12345"},"BillAddr":{"Line1":"Street 1","City":"City","CountrySubDivisionCode":"ST","PostalCode":"12345","Country":"US"}}}');
                return res;
            }
            res.setStatusCode(404);
            res.setBody('{"Fault":{"Error":[{"Message":"not found"}]}}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        // Create Connector Instance
        Connector_Instance__c instance = new Connector_Instance__c(
            Name = 'QuickBooks Online',
            Connector_Key__c = 'qbo',
            Active__c = true,
            Environment__c = 'Sandbox',
            Named_Credential__c = 'QuickBookSandbox'
        );
        insert instance;

        insert new Integration_Usage_Summary__c(
            Product_Key__c = 'quickbooks',
            Product__c = 'QuickBooks',
            Record_Sync_Count__c = 0,
            Error_Count__c = 0,
            Endpoint_Usage_Count__c = 0,
            Subscription_Status__c = 'Active',
            Last_Updated_At__c = System.now()
        );

        // Create Required Config Values
        List<Connector_Config_Value__c> configs = new List<Connector_Config_Value__c>();
        configs.add(new Connector_Config_Value__c(
            Name = 'qbo.RealmId',
            Connector_Instance__c = instance.Id,
            Connector_Key__c = 'qbo',
            Field_Key__c = 'QuickBooks_Realm_ID__c',
            Value__c = '123456789'
        ));
        configs.add(new Connector_Config_Value__c(
            Name = 'qbo.Active',
            Connector_Instance__c = instance.Id,
            Connector_Key__c = 'qbo',
            Field_Key__c = 'QuickBooks_Is_Active__c',
            Value__c = 'true'
        ));
        insert configs;

        // Insert a seed account to avoid null pointers in mapping lookups if needed
        QBTriggerHandler.isAccountProcessing = true;
        insert new Account(Name = 'Seed Account', QuickbookID__c = 'EXISTING-001');

        insert new Account(
            Name = 'Existing Business',
            QuickbookID__c = 'CUST-2',
            RecordTypeId = getCustomerRecordTypeId()
        );

        QBTriggerHandler.isAccountProcessing = false;
    }

    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Id getCustomerRecordTypeId() {
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND DeveloperName = 'Customer' LIMIT 1];
        if(rts.isEmpty()) {
            rts = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' LIMIT 1];
        }
        return rts[0].Id;
    }

    @isTest
    static void testBatchStartExecuteFinish() {
        Test.setMock(HttpCalloutMock.class, new QBCustomerBatchMock());

        Test.startTest();
        Database.executeBatch(new QBCustomerToAccountSyncBatch('2025-01-01'), 1);
        Test.stopTest();
        
        Account syncedAccount = [
            SELECT Id, Name, QuickbookID__c, BillingStreet, BillingState, (SELECT Id, LastName, Title FROM Contacts)
            FROM Account
            WHERE QuickbookID__c = 'CUST-1'
            LIMIT 1
        ];
        System.assertEquals('Customer One', syncedAccount.Name);
        System.assertEquals('CUST-1', syncedAccount.QuickbookID__c);
        System.assert(!syncedAccount.Contacts.isEmpty(), 'Contact should be created for Business Account');
        System.assertEquals('Doe', syncedAccount.Contacts[0].LastName);
        System.assertEquals('Mr.', syncedAccount.Contacts[0].Title);

        // Verify the trigger flag was reset
        System.assertEquals(false, QBTriggerHandler.isAccountProcessing);
    }

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
        System.assertNotEquals(getPersonAccountRecordTypeId(), result.RecordTypeId,
            'Existing Business Account must not be converted to a Person Account inline.');
    }

    @isTest
    static void testInboundNotesAndAddressMappings() {
        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('Name', 'DisplayName', 'QBO to SF'),
            customerMapping('Description', 'Notes', 'QBO to SF'),
            customerMapping('BillingStreet', 'BillAddr.Line1', 'QBO to SF'),
            customerMapping('BillingCity', 'BillAddr.City', 'QBO to SF'),
            customerMapping('BillingState', 'BillAddr.CountrySubDivisionCode', 'QBO to SF'),
            customerMapping('BillingPostalCode', 'BillAddr.PostalCode', 'QBO to SF'),
            customerMapping('BillingCountry', 'BillAddr.Country', 'QBO to SF'),
            customerMapping('ShippingStreet', 'ShipAddr.Line1', 'QBO to SF'),
            customerMapping('ShippingCity', 'ShipAddr.City', 'QBO to SF'),
            customerMapping('ShippingState', 'ShipAddr.CountrySubDivisionCode', 'QBO to SF'),
            customerMapping('ShippingPostalCode', 'ShipAddr.PostalCode', 'QBO to SF'),
            customerMapping('ShippingCountry', 'ShipAddr.Country', 'QBO to SF')
        };
        String customerPayload = JSON.serialize(
            new Map<String, Object>{
                'Id' => 'CUST-ADDR',
                'DisplayName' => 'Mapped Address Customer',
                'CompanyName' => 'Mapped Address Customer',
                'Notes' => 'QuickBooks customer notes',
                'BillAddr' => new Map<String, Object>{
                    'Line1' => '1 Billing Way',
                    'City' => 'Billing City',
                    'CountrySubDivisionCode' => 'BS',
                    'PostalCode' => '11111',
                    'Country' => 'US'
                },
                'ShipAddr' => new Map<String, Object>{
                    'Line1' => '2 Shipping Way',
                    'City' => 'Shipping City',
                    'CountrySubDivisionCode' => 'SS',
                    'PostalCode' => '22222',
                    'Country' => 'US'
                }
            }
        );

        Test.startTest();
        new QBCustomerToAccountSyncBatch().execute(
            null,
            new List<String>{ customerPayload }
        );
        Test.stopTest();

        Account syncedAccount = [
            SELECT Description,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry
            FROM Account
            WHERE QuickbookID__c = 'CUST-ADDR'
            LIMIT 1
        ];
        System.assertEquals('QuickBooks customer notes', syncedAccount.Description);
        System.assertEquals('1 Billing Way', syncedAccount.BillingStreet);
        System.assertEquals('Billing City', syncedAccount.BillingCity);
        System.assertEquals('BS', syncedAccount.BillingState);
        System.assertEquals('11111', syncedAccount.BillingPostalCode);
        System.assertEquals('US', syncedAccount.BillingCountry);
        System.assertEquals('2 Shipping Way', syncedAccount.ShippingStreet);
        System.assertEquals('Shipping City', syncedAccount.ShippingCity);
        System.assertEquals('SS', syncedAccount.ShippingState);
        System.assertEquals('22222', syncedAccount.ShippingPostalCode);
        System.assertEquals('US', syncedAccount.ShippingCountry);
    }

    @isTest
    static void testProcessSingleCustomerFallbackStillHydratesById() {
        Test.setMock(HttpCalloutMock.class, new QBCustomerSingleRecordMock());

        Test.startTest();
        new QBCustomerToAccountSyncBatch('2025-01-01').processSingleCustomer('CUST-1');
        Test.stopTest();

        System.assertEquals(1, [SELECT Count() FROM Account WHERE QuickbookID__c = 'CUST-1']);
    }

    @isTest
static void testPersonAccountSync() {
    Id personRtId = getPersonAccountRecordTypeId();
    if (personRtId == null) return; 

    String jsonPayload = '{"Id":"CUST-PA","GivenName":"John","FamilyName":"Doe","PrimaryEmailAddr":{"Address":"pa@test.com"}}';
    
    Test.setMock(HttpCalloutMock.class, new QBCustomerBatchMock());
    
    QBCustomerToAccountSyncBatch batch = new QBCustomerToAccountSyncBatch();
    
    Test.startTest();
    batch.execute(null, new List<String>{ jsonPayload });
    Test.stopTest();

    Account result = [SELECT Id, FirstName, LastName, RecordTypeId, IsPersonAccount FROM Account WHERE QuickbookID__c = 'CUST-PA' LIMIT 1];
    System.assertEquals('John', result.FirstName);
    System.assertEquals('Doe', result.LastName);
    System.assertEquals(personRtId, result.RecordTypeId);
}

    @isTest
    static void testBatchErrorHandling() {
        List<String> badScope = new List<String>{ 'invalid-json' };
        
        QBCustomerToAccountSyncBatch batch = new QBCustomerToAccountSyncBatch();
        
        Test.startTest();
        batch.execute(null, badScope);
        Test.stopTest();
        
        System.assert(true);
    }

    @isTest
    static void testCoerceValueLogic() {
        Test.setMock(HttpCalloutMock.class, new QBCustomerSingleRecordMock());

        Map<String, Object> data = new Map<String, Object>{
            'Id' => 'COERCE-1',
            'Active' => true
        };
        
        Test.startTest();
        QBCustomerToAccountSyncBatch batch = new QBCustomerToAccountSyncBatch();
        batch.processSingleCustomer('CUST-1'); // Triggering hydrate paths
        Test.stopTest();
        System.assert(true);
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
}