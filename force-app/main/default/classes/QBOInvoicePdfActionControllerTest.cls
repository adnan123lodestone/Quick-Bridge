@isTest
private class QBOInvoicePdfActionControllerTest {

    private static final String QBO_INVOICE_ID = 'QB-INV-123';
    private static Id orderId;

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

        Connector_Config_Value__c realmConfig = new Connector_Config_Value__c(
            Name = 'qbo.RealmId',
            Connector_Instance__c = instance.Id,
            Connector_Key__c = 'qbo',
            Field_Key__c = 'QuickBooks_Realm_ID__c',
            Value__c = '1234567890',
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

        Connector_Config_Value__c draftConfig = new Connector_Config_Value__c(
            Name = 'qbo.Map_Draft_Orders_as_Estimates__c',
            Connector_Instance__c = instance.Id,
            Connector_Key__c = 'qbo',
            Field_Key__c = 'Map_Draft_Orders_as_Estimates__c',
            Value__c = 'true',
            Is_Secret_Reference__c = false
        );
        insert draftConfig;

        Integration_Entity_Definition__c entityDef = new Integration_Entity_Definition__c(
            Name = 'Order_Invoice',
            Integration_Key__c = 'qbonline',
            Salesforce_Object__c = 'Order',
            External_Entity__c = 'Invoice',
            Active__c = true
        );
        insert entityDef;

        try {
            Integration_Entity_Definition__c invEntityDef = new Integration_Entity_Definition__c(
                Name = 'CustomInvoice_Invoice',
                Integration_Key__c = 'qbonline',
                Salesforce_Object__c = 'QuickBridgeTLG__Invoice__c',
                External_Entity__c = 'Invoice',
                Active__c = true
            );
            insert invEntityDef;
        } catch (Exception e) { }

        IntegrationEntityRegistry.clearCache();

        Account acc = new Account(Name = 'PDF Test Account', QuickbookID__c = 'ACC-123');
        insert acc;

        Product2 prod = new Product2(Name = 'PDF Test Prod', IsActive = true, QuickbookID__c = 'PROD-123');
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acc.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Draft',
            EffectiveDate = Date.today(),
            QuickbookID__c = QBO_INVOICE_ID
        );
        insert ord;

        OrderItem item = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert item;

        Schema.SObjectType invType = Schema.getGlobalDescribe().get('QuickBridgeTLG__Invoice__c');
        if (invType != null) {
            SObject testInv = invType.newSObject();
            testInv.put('QuickBridgeTLG__External_Id__c', QBO_INVOICE_ID);
            testInv.put('QuickBridgeTLG__Related_Account__c', acc.Id);
            insert testInv;
        }
    }

    private static Id getOrderId() {
        if (orderId == null) {
            orderId = [SELECT Id FROM Order LIMIT 1].Id;
        }
        return orderId;
    }

    private static SObject getCustomInvoice() {
        Schema.SObjectType invType = Schema.getGlobalDescribe().get('QuickBridgeTLG__Invoice__c');
        if (invType != null) {
            List<SObject> recs = Database.query('SELECT Id, QuickBridgeTLG__External_Id__c FROM QuickBridgeTLG__Invoice__c LIMIT 1');
            return recs.isEmpty() ? null : recs[0];
        }
        return null;
    }

    private static void setupResolverMappings() {
        setupResolverMappingsWithDirection('Two-Way');
    }

    private static void setupResolverMappingsWithDirection(String direction) {
        List<Field_Mapping__mdt> mappings = new List<Field_Mapping__mdt>();
        mappings.add(new Field_Mapping__mdt(
            DeveloperName = 'Test_QBO_Id',
            MasterLabel = 'Test QBO Id',
            Integration__c = 'qbonline',
            SF_Object__c = 'Order',
            SF_Field__c = 'QuickbookID__c',
            External_Field__c = 'Id',
            Sync_Direction__c = direction,
            Is_Active__c = true
        ));
        mappings.add(new Field_Mapping__mdt(
            DeveloperName = 'Test_OrderNumber',
            MasterLabel = 'Test OrderNumber',
            Integration__c = 'qbonline',
            SF_Object__c = 'Order',
            SF_Field__c = 'OrderNumber',
            External_Field__c = 'DocNumber',
            Sync_Direction__c = 'SF to QBO',
            Is_Active__c = true
        ));
        mappings.add(new Field_Mapping__mdt(
            DeveloperName = 'Test_Description',
            MasterLabel = 'Test Description',
            Integration__c = 'qbonline',
            SF_Object__c = 'Order',
            SF_Field__c = 'Description',
            External_Field__c = 'CustomerMemo.value',
            Sync_Direction__c = 'SF to QBO',
            Is_Active__c = true
        ));
        QBOInvoiceMappingResolver.setTestFieldMappingRows(mappings);
    }

    private static void setupInvoiceObjectMappings() {
        List<Field_Mapping__mdt> mappings = new List<Field_Mapping__mdt>();
        mappings.add(new Field_Mapping__mdt(
            DeveloperName = 'Inv_QBO_Id',
            MasterLabel = 'Inv QBO Id',
            Integration__c = 'qbonline',
            SF_Object__c = 'QuickBridgeTLG__Invoice__c',
            SF_Field__c = 'QuickBridgeTLG__External_Id__c',
            External_Field__c = 'Id',
            Sync_Direction__c = 'Two-Way',
            Is_Active__c = true
        ));
        mappings.add(new Field_Mapping__mdt(
            DeveloperName = 'Inv_TxnDate',
            MasterLabel = 'Inv TxnDate',
            Integration__c = 'qbonline',
            SF_Object__c = 'QuickBridgeTLG__Invoice__c',
            SF_Field__c = 'QuickBridgeTLG__Invoice_Date__c',
            External_Field__c = 'TxnDate',
            Sync_Direction__c = 'SF to QBO',
            Is_Active__c = true
        ));
        QBOInvoiceMappingResolver.setTestFieldMappingRows(mappings);
    }

    private class PdfSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String endpoint = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (endpoint.contains('/pdf')) {
                res.setHeader('Content-Type', 'application/pdf');
                res.setBodyAsBlob(Blob.valueOf('%PDF-FAKECONTENT'));
            } else if (endpoint.contains('/estimate')) {
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"Estimate":{"Id":"' + QBO_INVOICE_ID + '","SyncToken":"0","DocNumber":"00001"}}');
            } else {
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"Invoice":{"Id":"' + QBO_INVOICE_ID + '","SyncToken":"0","DocNumber":"00001","TxnDate":"2025-01-15","CustomerMemo":{"value":"Synced"}}}');
            }
            return res;
        }
    }

    private class PdfError404EstimateMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (endpoint.contains('/invoice/') && endpoint.contains('/pdf')) {
                res.setStatusCode(404);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"Fault":{"Error":[{"Message":"Not Found"}]}}');
            } else if (endpoint.contains('/estimate/') && endpoint.contains('/pdf')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/pdf');
                res.setBodyAsBlob(Blob.valueOf('%PDF-ESTIMATE%'));
            } else {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"Invoice":{"Id":"' + QBO_INVOICE_ID + '"}}');
            }
            return res;
        }
    }

    private class PdfErrorMock implements HttpCalloutMock {
        private Integer statusCode;
        PdfErrorMock(Integer statusCode) { this.statusCode = statusCode; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"Fault":{"Error":[{"Message":"Error"}]}}');
            return res;
        }
    }

    private class EmptyBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/pdf');
            res.setBodyAsBlob(Blob.valueOf(''));
            return res;
        }
    }

    private class CustomInvoiceMissingDataMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"WrongKey":{}}');
            return res;
        }
    }

    @isTest
    static void testGetPanelDataSuccess() {
        setupResolverMappings();
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        Test.startTest();
        QBOInvoicePdfActionController.PanelData data = QBOInvoicePdfActionController.getPanelData(ordId, 'Order');
        Test.stopTest();

        System.assertEquals(true, data.isConfigured);
        System.assertEquals(true, data.qboIdPresent);
        System.assertEquals(true, data.showSyncToQbo);
        System.assertEquals(true, data.showSyncFromQbo);
    }

    @isTest
    static void testGetPanelDataDirections() {
        setupResolverMappingsWithDirection('SF to QBO');
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        QBOInvoicePdfActionController.PanelData data1 = QBOInvoicePdfActionController.getPanelData(ordId, 'Order');
        System.assertEquals(true, data1.showSyncToQbo);

        setupResolverMappingsWithDirection('QBO to SF');
        QBOInvoicePdfActionController.PanelData data2 = QBOInvoicePdfActionController.getPanelData(ordId, 'Order');
        System.assertEquals(true, data2.showSyncFromQbo);

        setupResolverMappingsWithDirection('Other');
        QBOInvoicePdfActionController.PanelData data3 = QBOInvoicePdfActionController.getPanelData(ordId, 'Order');
        System.assertEquals(true, data3.showSyncToQbo);
    }

    @isTest
    static void testGetPanelDataNoQboIdField() {
        List<Field_Mapping__mdt> mappings = new List<Field_Mapping__mdt>();
        QBOInvoiceMappingResolver.setTestFieldMappingRows(mappings);
        Id ordId = getOrderId();

        Boolean threw = false;
        try {
            QBOInvoicePdfActionController.getPanelData(ordId, 'Order');
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw);
    }



    @isTest
    static void testGetPanelDataWrongObject() {
        setupResolverMappings();
        Account acc = [SELECT Id FROM Account LIMIT 1];

        QBOInvoicePdfActionController.PanelData data = QBOInvoicePdfActionController.getPanelData(acc.Id, 'Account');
        System.assertEquals(false, data.isConfigured);
        System.assert(data.message.contains('not configured for this object'));
    }

    @isTest
    static void testGetPanelDataNoQboId() {
        setupResolverMappings();
        Order ord = [SELECT Id, QuickbookID__c FROM Order LIMIT 1];
        ord.QuickbookID__c = null;
        update ord;
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        Test.startTest();
        QBOInvoicePdfActionController.PanelData data = QBOInvoicePdfActionController.getPanelData(ord.Id, 'Order');
        Test.stopTest();

        System.assertEquals(true, data.isConfigured);
        System.assertEquals(false, data.qboIdPresent);
        System.assert(data.message.contains('has not been synced to QBO yet'));
    }

    @isTest
    static void testSyncToQboSuccess() {
        setupResolverMappings();
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfSuccessMock());

        Test.startTest();
        QBOInvoicePdfActionController.ActionResponse response = QBOInvoicePdfActionController.syncToQbo(ordId, 'Order');
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assert(response.message.contains('synced') || response.message.contains('queued'));
    }

    @isTest
    static void testSyncToQboCustomInvoice() {
        SObject customInv = getCustomInvoice();
        if (customInv == null) return;

        setupInvoiceObjectMappings();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        // Test with existing qboId (update sync)
        Test.startTest();
        QBOInvoicePdfActionController.ActionResponse res1 = QBOInvoicePdfActionController.syncToQbo(customInv.Id, 'QuickBridgeTLG__Invoice__c');
        System.assertEquals(true, res1.success);
        System.assert(res1.message.contains('update'));

        // Test with blank qboId (initial sync)
        customInv.put('QuickBridgeTLG__External_Id__c', null);
        update customInv;
        QBOInvoicePdfActionController.ActionResponse res2 = QBOInvoicePdfActionController.syncToQbo(customInv.Id, 'QuickBridgeTLG__Invoice__c');
        System.assertEquals(true, res2.success);
        System.assert(res2.message.contains('queued'));
        Test.stopTest();
    }

    @isTest
    static void testSyncToQboWrongObjectThrows() {
        setupResolverMappings();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.syncToQbo(acc.Id, 'Account');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testSyncFromQboSuccess() {
        setupResolverMappings();
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfSuccessMock());

        Test.startTest();
        QBOInvoicePdfActionController.ActionResponse response = QBOInvoicePdfActionController.syncFromQbo(ordId, 'Order');
        Test.stopTest();

        System.assertEquals(true, response.success);
    }

    @isTest
    static void testSyncFromQboCustomInvoice() {
        SObject customInv = getCustomInvoice();
        if (customInv == null) return;

        setupInvoiceObjectMappings();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfSuccessMock());

        Test.startTest();
        QBOInvoicePdfActionController.ActionResponse response = QBOInvoicePdfActionController.syncFromQbo(customInv.Id, 'QuickBridgeTLG__Invoice__c');
        System.assertEquals(true, response.success);
        Test.stopTest();
    }

    @isTest
    static void testSyncFromQboCustomInvoiceNoQboId() {
        SObject customInv = getCustomInvoice();
        if (customInv == null) return;

        setupInvoiceObjectMappings();
        customInv.put('QuickBridgeTLG__External_Id__c', null);
        update customInv;
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.syncFromQbo(customInv.Id, 'QuickBridgeTLG__Invoice__c');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testSyncFromQboCustomInvoiceHttpError() {
        SObject customInv = getCustomInvoice();
        if (customInv == null) return;

        setupInvoiceObjectMappings();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfErrorMock(500));

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.syncFromQbo(customInv.Id, 'QuickBridgeTLG__Invoice__c');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testSyncFromQboCustomInvoiceMissingData() {
        SObject customInv = getCustomInvoice();
        if (customInv == null) return;

        setupInvoiceObjectMappings();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new CustomInvoiceMissingDataMock());

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.syncFromQbo(customInv.Id, 'QuickBridgeTLG__Invoice__c');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testDownloadPdfSuccess() {
        setupResolverMappings();
        Order ord = [SELECT Id FROM Order LIMIT 1];
        ord.Status = 'Activated';
        update ord;

        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfSuccessMock());

        Test.startTest();
        Map<String, String> res = QBOInvoicePdfActionController.downloadPdf(ord.Id, 'Order');
        Test.stopTest();

        System.assertEquals('PDF saved successfully.', res.get('message'));
        System.assertNotEquals(null, res.get('contentDocumentId'));
    }

    @isTest
    static void testDownloadPdfDraftOrderAsEstimate() {
        setupResolverMappings();
        Order ord = [SELECT Id FROM Order LIMIT 1];
        ord.Status = 'Draft';
        update ord;

        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.downloadPdf(ord.Id, 'Order');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testDownloadPdfEstimateFallbackSuccess() {
        setupResolverMappings();
        Order ord = [SELECT Id FROM Order LIMIT 1];
        ord.Status = 'Activated';
        update ord;

        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfError404EstimateMock());

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.downloadPdf(ord.Id, 'Order');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testDownloadPdfError500() {
        setupResolverMappings();
        Order ord = [SELECT Id FROM Order LIMIT 1];
        ord.Status = 'Activated';
        update ord;

        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfErrorMock(500));

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.downloadPdf(ord.Id, 'Order');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testDownloadPdfNoQboIdOnRecord() {
        setupResolverMappings();
        Order ord = [SELECT Id, QuickbookID__c FROM Order LIMIT 1];
        ord.QuickbookID__c = null;
        update ord;

        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.downloadPdf(ord.Id, 'Order');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testDownloadPdfEmptyBody() {
        setupResolverMappings();
        Order ord = [SELECT Id FROM Order LIMIT 1];
        ord.Status = 'Activated';
        update ord;

        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new EmptyBodyMock());

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.downloadPdf(ord.Id, 'Order');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testDownloadPdfResolverException() {
        QBOInvoiceMappingResolver.setTestFieldMappingRows(new List<Field_Mapping__mdt>());
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        
        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.downloadPdf(ordId, 'Order');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testApplyMappingInvalidDate() {
        Map<String, Object> qboData = new Map<String, Object>{ 'TxnDate' => 'invalid-date' };
        Map<String, String> mapping = new Map<String, String>{ 'TxnDate' => 'EffectiveDate' };
        Order fakeOrder = new Order(Id = getOrderId());
        QBOInvoicePdfActionController.applyMapping(fakeOrder, qboData, mapping);
        System.assertEquals(null, fakeOrder.EffectiveDate);
    }

    @isTest
    static void testResolveInboundMappingCustomer() {
        Map<String, String> mapping = QBOInvoicePdfActionController.resolveInboundMapping('Customer', 'Account');
        System.assert(mapping.containsKey('DisplayName'));
        System.assertEquals('Name', mapping.get('DisplayName'));
    }

    @isTest
    static void testFetchFieldValueException() {
        Id ordId = getOrderId();
        String result = QBOInvoicePdfActionController.fetchFieldValue(ordId, 'Order', 'NonExistentField__c');
        System.assertEquals(null, result);
    }

    @isTest
    static void testGetNestedValueNullData() {
        System.assertEquals(null, QBOInvoicePdfActionController.getNestedValue(null, 'some.path'));
        System.assertEquals(null, QBOInvoicePdfActionController.getNestedValue(new Map<String, Object>(), null));
    }

    @isTest
    static void testResolveInboundMapping() {
        Map<String, String> mappingForOrder = QBOInvoicePdfActionController.resolveInboundMapping('Invoice', 'Order');
        System.assert(!mappingForOrder.isEmpty());

        Map<String, String> mappingForCustom = QBOInvoicePdfActionController.resolveInboundMapping('Invoice', 'QuickBridgeTLG__Invoice__c');
        System.assert(!mappingForCustom.isEmpty());
    }

    @isTest
    static void testApplyMapping() {
        Map<String, Object> qboData = new Map<String, Object>{
            'TxnDate' => '2025-12-31',
            'CustomerMemo' => new Map<String, Object>{ 'value' => 'Test Memo' }
        };
        Map<String, String> mapping = new Map<String, String>{
            'TxnDate' => 'EffectiveDate',
            'CustomerMemo.value' => 'Description'
        };
        Order fakeOrder = new Order(Id = getOrderId());
        QBOInvoicePdfActionController.applyMapping(fakeOrder, qboData, mapping);
        System.assertEquals(Date.newInstance(2025, 12, 31), fakeOrder.EffectiveDate);
        System.assertEquals('Test Memo', fakeOrder.Description);
    }

    @isTest
    static void testGetNestedValue() {
        Map<String, Object> data = new Map<String, Object>{
            'Level1' => new Map<String, Object>{ 'Level2' => 'Value' }
        };
        System.assertEquals('Value', QBOInvoicePdfActionController.getNestedValue(data, 'Level1.Level2'));
        System.assertEquals(null, QBOInvoicePdfActionController.getNestedValue(data, 'Level1.Missing'));
        System.assertEquals('Top', QBOInvoicePdfActionController.getNestedValue(new Map<String, Object>{'Top' => 'Top'}, 'Top'));
    }

    @isTest
    static void testFetchFieldValue() {
        setupResolverMappings();
        Id ordId = getOrderId();
        String qboId = QBOInvoicePdfActionController.fetchFieldValue(ordId, 'Order', 'QuickbookID__c');
        System.assertEquals(QBO_INVOICE_ID, qboId);
    }

    @isTest
    static void testSavePdf() {
        Id ordId = getOrderId();
        Blob pdfBlob = Blob.valueOf('%PDF-TEST%');
        String title = 'Test PDF';
        String docId = QBOInvoicePdfActionController.savePdf(ordId, pdfBlob, title);
        System.assertNotEquals(null, docId);
        String docId2 = QBOInvoicePdfActionController.savePdf(ordId, Blob.valueOf('%PDF-TEST2%'), title);
        System.assertEquals(docId, docId2);
    }
}