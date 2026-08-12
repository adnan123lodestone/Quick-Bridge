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
                res.setBody('{"Customer":{"Id":"ACT-1","SyncToken":"0","GivenName":"Jane","FamilyName":"Doe","Notes":"Action customer notes","PrimaryEmailAddr":{"Address":"jane@example.com"},"PrimaryPhone":{"FreeFormNumber":"999"},"BillAddr":{"Line1":"Street","City":"City","CountrySubDivisionCode":"ST","PostalCode":"12345","Country":"US"},"ShipAddr":{"Line1":"Ship Street","City":"Ship City","CountrySubDivisionCode":"SS","PostalCode":"54321","Country":"US"}}}');
                return res;
            }
            if (method == 'GET' && endpoint.contains('/vendor/')) {
                res.setStatusCode(200);
                res.setBody('{"Vendor":{"Id":"VEND-ACT-1","SyncToken":"0","DisplayName":"Action Vendor","CompanyName":"Action Vendor Co","PrimaryEmailAddr":{"Address":"vendor-action@example.com"},"PrimaryPhone":{"FreeFormNumber":"888"},"BillAddr":{"Line1":"Vendor Street","City":"Vendor City","CountrySubDivisionCode":"VS","PostalCode":"54321","Country":"US"}}}');
                return res;
            }
            if (method == 'POST' && endpoint.contains('/vendor')) {
                res.setStatusCode(200);
                res.setBody('{"Vendor":{"Id":"VEND-ACT-1"}}');
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
    
    private class QBAccountErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('{"Fault":{"Error":[{"Message":"Internal Server Error"}]}}');
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
    
    private static void configureQuickBooksConnection() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
    }
    
    @isTest
    static void testSyncToQuickBooks_Customer_New() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBAccountActionMock());
        Account acc = [SELECT Id FROM Account WHERE Name = 'Action Controller Acc' LIMIT 1];
        
        Test.startTest();
        QBAccountRecordActionController.ActionResponse response = QBAccountRecordActionController.syncToQuickBooks(acc.Id);
        Test.stopTest();
        
        System.assertEquals(true, response.success);
        System.assertEquals('ACT-1', response.quickBooksId);
        System.assert(response.message.contains('synced to QuickBooks') || response.message.contains('Account synced'));
    }
    
    @isTest
    static void testSyncToQuickBooks_WithExistingId() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBAccountActionMock());
        Account acc = [SELECT Id, QuickbookID__c FROM Account WHERE Name = 'Action Controller Synced' LIMIT 1];
        
        Test.startTest();
        QBAccountRecordActionController.ActionResponse response = QBAccountRecordActionController.syncToQuickBooks(acc.Id);
        Test.stopTest();
        
        System.assertEquals(true, response.success);
        System.assertEquals('ACT-1', response.quickBooksId);
        System.assert(response.message.contains('updated') || response.message.contains('updated in QuickBooks'));
    }
    
    @isTest
    static void testSyncFromQuickBooks_Customer() {
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBAccountActionMock());
        QBObjectMappings.testDynamicMappings = new List<Field_Mapping__mdt>{
            customerMapping('Description', 'Notes', 'QBO to SF'),
            customerMapping('BillingStreet', 'BillAddr.Line1', 'QBO to SF'),
            customerMapping('ShippingStreet', 'ShipAddr.Line1', 'QBO to SF'),
            customerMapping('ShippingCity', 'ShipAddr.City', 'QBO to SF')
        };
        Account acc = [SELECT Id FROM Account WHERE Name = 'Action Controller Synced' LIMIT 1];
        
        Test.startTest();
        QBAccountRecordActionController.ActionResponse response = QBAccountRecordActionController.syncFromQuickBooks(acc.Id);
        Test.stopTest();
        
        System.assertEquals(true, response.success);
        System.assertEquals('ACT-1', response.quickBooksId);
        System.assert(response.message.contains('synced from QuickBooks'));

        Account syncedAccount = [
            SELECT Name, Description, BillingStreet, ShippingStreet, ShippingCity
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals('Action Controller Synced', syncedAccount.Name);
        System.assertEquals('Action customer notes', syncedAccount.Description);
        System.assertEquals('Street', syncedAccount.BillingStreet);
        System.assertEquals('Ship Street', syncedAccount.ShippingStreet);
        System.assertEquals('Ship City', syncedAccount.ShippingCity);
        
        Contact[] contacts = [SELECT Id, Email, Email__c, AccountId FROM Contact WHERE AccountId = :acc.Id];
        System.assertEquals(1, contacts.size());
        System.assertEquals('jane@example.com', contacts[0].Email);
    }
    
    @isTest
    static void testSyncFromQuickBooks_Vendor() {
        Id vendorRecordTypeId = getVendorAccountRecordTypeId();
        if (vendorRecordTypeId == null) {
            System.assertEquals(null, vendorRecordTypeId);
            return;
        }
        
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBAccountActionMock());
        Account acc = [SELECT Id FROM Account WHERE Name = 'Action Controller Vendor' LIMIT 1];
        
        Test.startTest();
        QBAccountRecordActionController.ActionResponse response = QBAccountRecordActionController.syncFromQuickBooks(acc.Id);
        Test.stopTest();
        
        System.assertEquals(true, response.success);
        System.assertEquals('VEND-ACT-1', response.quickBooksId);
        System.assert(response.message.contains('synced from QuickBooks'));
        
        Account updatedAccount = [SELECT Id, Name, BillingStreet FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Action Vendor', updatedAccount.Name);
        System.assertEquals('Vendor Street', updatedAccount.BillingStreet);
    }
    
    @isTest
    static void testSyncFromQuickBooks_MissingQBId() {
        configureQuickBooksConnection();
        Account acc = [SELECT Id FROM Account WHERE Name = 'Action Controller Acc' LIMIT 1];
        
        Test.startTest();
        try {
            QBAccountRecordActionController.syncFromQuickBooks(acc.Id);
            System.assert(false, 'Expected exception due to missing QuickBooks ID.');
        } catch (AuraHandledException e) {
            // Exception thrown as expected – test passes
            System.assert(true, 'Exception thrown as expected.');
        } catch (Exception e) {
            System.assert(false, 'Expected AuraHandledException but got: ' + e.getTypeName());
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSyncToQuickBooks_NullId() {
        configureQuickBooksConnection();
        
        Test.startTest();
        try {
            QBAccountRecordActionController.syncToQuickBooks(null);
            System.assert(false, 'Expected exception for null Account Id.');
        } catch (AuraHandledException e) {
            // Exception thrown as expected – test passes
            System.assert(true, 'Exception thrown as expected.');
        } catch (Exception e) {
            System.assert(false, 'Expected AuraHandledException but got: ' + e.getTypeName());
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
        
        configureQuickBooksConnection();
        Test.setMock(HttpCalloutMock.class, new QBAccountActionMock());
        
        Test.startTest();
        QBAccountRecordActionController.ActionResponse response = QBAccountRecordActionController.syncFromQuickBooks(vendorAccount.Id);
        Test.stopTest();
        
        System.assertEquals(true, response.success);
        System.assertEquals('VEND-ACT-1', response.quickBooksId);
        System.assert(response.message.contains('synced from QuickBooks'));
        
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
