@isTest
private class QBOInvoicePdfActionControllerTest {

    private static final String QBO_INVOICE_ID = 'QB-INV-123';
    private static Id orderId;
    private static Id invoiceId;

    @testSetup
    static void setupData() {
        // Connector config, entity definitions, and test data (unchanged)
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

        Account acc = new Account(Name = 'PDF Test Account');
        insert acc;

        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            QuickbookID__c = QBO_INVOICE_ID
        );
        insert ord;
        
        Schema.SObjectType invType = Schema.getGlobalDescribe().get('QuickBridgeTLG__Invoice__c');
        if (invType != null) {
            SObject testInv = invType.newSObject();
            testInv.put('QuickBridgeTLG__External_Id__c', QBO_INVOICE_ID);
            testInv.put('QuickBridgeTLG__Related_Account__c', acc.Id);
            insert testInv;
            invoiceId = testInv.Id;
        }
    }

    private static Id getOrderId() {
        if (orderId == null) {
            orderId = [SELECT Id FROM Order LIMIT 1].Id;
        }
        return orderId;
    }
    
    private static Id getInvoiceId() {
        return invoiceId;
    }

    private static void setupResolverMappings() {
        List<Field_Mapping__mdt> mappings = new List<Field_Mapping__mdt>();
        mappings.add(new Field_Mapping__mdt(
            DeveloperName = 'Test_QBO_Id',
            MasterLabel = 'Test QBO Id',
            Integration__c = 'qbonline',
            SF_Object__c = 'Order',
            SF_Field__c = 'QuickbookID__c',
            External_Field__c = 'Id',
            Sync_Direction__c = 'Two-Way',
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

    // ----------------------------------------------------------------------
    // MOCK CLASSES
    // ----------------------------------------------------------------------
    private class PdfSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().contains('/pdf')) {
                res.setHeader('Content-Type', 'application/pdf');
                res.setBodyAsBlob(Blob.valueOf('%PDF-FAKECONTENT'));
            } else {
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"Invoice":{"Id":"' + QBO_INVOICE_ID + '","TxnDate":"2025-01-15","CustomerMemo":{"value":"Synced"}}}');
            }
            return res;
        }
    }

    private class PdfErrorMock implements HttpCalloutMock {
        private Integer statusCode;
        PdfErrorMock(Integer statusCode) { this.statusCode = statusCode; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('/pdf')) {
                res.setStatusCode(statusCode);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"Fault":{"Error":[{"Message":"Unauthorized"}]}}');
            } else {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"Invoice":{"Id":"' + QBO_INVOICE_ID + '"}}');
            }
            return res;
        }
    }

    private class EmptyBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().contains('/pdf')) {
                res.setHeader('Content-Type', 'application/pdf');
                res.setBodyAsBlob(Blob.valueOf(''));
            } else {
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"Invoice":{"Id":"' + QBO_INVOICE_ID + '"}}');
            }
            return res;
        }
    }
    
    private class CalloutErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated network error');
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
        System.assert(String.isBlank(data.message));
    }

    @isTest
    static void testGetPanelDataWrongObjectType() {
        setupResolverMappings();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        Test.startTest();
        QBOInvoicePdfActionController.PanelData data = QBOInvoicePdfActionController.getPanelData(acc.Id, 'Account');
        Test.stopTest();

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

        Test.startTest();
        QBOInvoicePdfActionController.ActionResponse response = QBOInvoicePdfActionController.syncToQbo(ordId, 'Order');
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assert(response.message.contains('queued'));
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
    static void testSyncFromQboForOrderUsesQueueable() {
        setupResolverMappings();
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfSuccessMock());

        Test.startTest();
        QBOInvoicePdfActionController.ActionResponse response = QBOInvoicePdfActionController.syncFromQbo(ordId, 'Order');
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assert(response.message.contains('synced from QBO'));
    }

    @isTest
    static void testSyncFromQboNoQboIdThrows() {
        setupResolverMappings();
        Order ord = [SELECT Id, QuickbookID__c FROM Order LIMIT 1];
        ord.QuickbookID__c = null;
        update ord;
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.syncFromQbo(ord.Id, 'Order');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testSyncFromQboWrongObjectThrows() {
        setupResolverMappings();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.syncFromQbo(acc.Id, 'Account');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testDownloadPdfSuccess() {
        setupResolverMappings();
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfSuccessMock());

        Test.startTest();
        Map<String, String> result = QBOInvoicePdfActionController.downloadPdf(ordId, 'Order');
        Test.stopTest();

        System.assertNotEquals(null, result.get('contentDocumentId'));
        System.assertEquals('PDF saved successfully.', result.get('message'));
    }

    @isTest
    static void testDownloadPdfNoQboIdThrows() {
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
    static void testDownloadPdfCalloutFails() {
        setupResolverMappings();
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfErrorMock(401));

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
    static void testDownloadPdfEmptyResponse() {
        setupResolverMappings();
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new EmptyBodyMock());

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
    static void testGetPanelDataResolverException() {
        QBOInvoiceMappingResolver.setTestFieldMappingRows(new List<Field_Mapping__mdt>());
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');

        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.getPanelData(ordId, 'Order');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // Additional coverage tests (optional)
    @isTest
    static void testSyncFromQboForInvoiceObject() {
        if (getInvoiceId() == null) return;
        setupInvoiceObjectMappings();
        Id invId = getInvoiceId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new PdfSuccessMock());
        
        Test.startTest();
        QBOInvoicePdfActionController.ActionResponse response = QBOInvoicePdfActionController.syncFromQbo(invId, 'QuickBridgeTLG__Invoice__c');
        Test.stopTest();
        
        System.assertEquals(true, response.success);
        System.assert(response.message.contains('synced from QBO'));
    }

    @isTest
    static void testSyncFromQboInvoiceCalloutError() {
        if (getInvoiceId() == null) return;
        setupInvoiceObjectMappings();
        Id invId = getInvoiceId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new CalloutErrorMock());
        
        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.syncFromQbo(invId, 'QuickBridgeTLG__Invoice__c');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testSyncToQboResolverException() {
        QBOInvoiceMappingResolver.setTestFieldMappingRows(new List<Field_Mapping__mdt>());
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        
        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.syncToQbo(ordId, 'Order');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testSyncFromQboGenericException() {
        setupResolverMappings();
        Id ordId = getOrderId();
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        
        Boolean threw = false;
        Test.startTest();
        try {
            QBOInvoicePdfActionController.syncFromQbo(ordId, 'InvalidObject__x');
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
        System.assert(mappingForOrder.containsKey('CustomerMemo.value'));
        System.assertEquals('Description', mappingForOrder.get('CustomerMemo.value'));
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

    @isTest
    static void testMakeBinaryApiCall() {
        Test.setMock(HttpCalloutMock.class, new PdfSuccessMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthHandler.makeBinaryApiCall('/invoice/' + QBO_INVOICE_ID + '/pdf');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
    }
}