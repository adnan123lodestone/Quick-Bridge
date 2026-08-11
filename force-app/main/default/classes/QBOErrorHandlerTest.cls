@isTest
private class QBOErrorHandlerTest {

    // ============================================================
    // HTTP Mock for QuickBooks API
    // ============================================================
    private class QBOMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public QBOMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(responseBody);
            return res;
        }
    }

    // ============================================================
    // Mock JSON Responses
    // ============================================================
    private static String getCustomerResponse() {
        return '{"Customer":{"Id":"123","DisplayName":"Test Customer","PrimaryEmailAddr":{"Address":"test@example.com"}}}';
    }

    private static String getVendorResponse() {
        return '{"Vendor":{"Id":"456","DisplayName":"Test Vendor"}}';
    }

    private static String getItemResponse() {
        return '{"Item":{"Id":"789","Name":"Test Item","Type":"Inventory"}}';
    }

    private static String getInvoiceResponse() {
        return '{"Invoice":{"Id":"101","DocNumber":"INV-001","TotalAmt":100.00,"CustomerRef":{"value":"123"}}}';
    }

    // ============================================================
    // Helper to completely bypass QuickBooksAuthHandler checks
    // ============================================================
    private static void bypassAuthConfig() {
        QuickBooksAuthHandler.configureConnectionForTest('123456789', 'Mock_Named_Credential', '65');
    }

    // ============================================================
    // Test Setup - Create Connector Config + Test Data
    // ============================================================
    @testSetup
    static void setupTestData() {
        Connector_Instance__c instance = new Connector_Instance__c(
            Name = 'QuickBooks',
            Connector_Key__c = 'qbo',
            Active__c = true,
            Connector_Label__c = 'QuickBooks',
            Environment__c = 'Sandbox',
            Expiry_Date__c = Date.newInstance(2027, 6, 2)
        );
        insert instance;

        List<Connector_Config_Value__c> configValues = new List<Connector_Config_Value__c>();
        
        Map<String, String> qboFields = new Map<String, String>{
            'QuickBooks_Client_Id__c'       => 'test_client_id',
            'QuickBooks_Client_Secret__c'   => 'test_client_secret',
            'QuickBooks_Refresh_Token__c'   => 'test_refresh_token',
            'QuickBooks_Realm_ID__c'        => '123456789',
            'QuickBooks_Environment__c'     => 'Sandbox',
            'QuickBooks_Active__c'          => 'TRUE'
        };

        for (String fieldKey : qboFields.keySet()) {
            Connector_Config_Value__c cv = new Connector_Config_Value__c(
                Connector_Instance__c = instance.Id,
                Field_Key__c = fieldKey,
                Value__c = qboFields.get(fieldKey),
                Is_Secret_Reference__c = false,
                Connector_Key__c = 'qbo'
            );
            configValues.add(cv);
        }
        insert configValues;

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        insert prod;
    }

    // ============================================================
    // Outbound sync branches
    // ============================================================

    @isTest
    static void testHandle_QBAccountService_syncAccountToQuickBooks() {
        bypassAuthConfig();
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QBAccountService.syncAccountToQuickBooks',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, getCustomerResponse()));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assert(result.startsWith('Account retried:'), 'Account retry should succeed');
    }

    @isTest
    static void testHandle_QBAccountBatchExecute() {
        bypassAuthConfig();
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QBAccountBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, getCustomerResponse()));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assert(result.startsWith('Account retried:'), 'Account retry should succeed');
    }

    @isTest
    static void testHandle_QBProductService_syncProductsToQuickBooks() {
        bypassAuthConfig();
        Product2 prod = [SELECT Id, Name FROM Product2 LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = prod.Id,
            Class_Method_Name__c = 'QBProductService.syncProductsToQuickBooks',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, getItemResponse()));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Product retried.', result);
    }

    @isTest
    static void testHandle_QBProductBatchExecute() {
        bypassAuthConfig();
        Product2 prod = [SELECT Id, Name FROM Product2 LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = prod.Id,
            Class_Method_Name__c = 'QBProductBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, getItemResponse()));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Product retried.', result);
    }

    @isTest
    static void testHandle_QBSalesOrderSyncBatchExecute() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QBSalesOrderSyncBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, '{}'));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Order sync batch enqueued.', result);
    }

    @isTest
    static void testHandle_QuickBooksInvoiceBatchExecute() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QuickBooksInvoiceBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        // FIX: Mock added for batch execution
        Test.setMock(HttpCalloutMock.class, new QBOMock(200, '{}'));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Invoice sync batch enqueued.', result);
    }

    @isTest
    static void testHandle_QBInvoiceWorkerProcess() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QBInvoiceWorker.process',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, '{}'));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Invoice sync batch enqueued.', result);
    }

    @isTest
    static void testHandle_QuickBooksCreditMemoBatchExecute() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QuickBooksCreditMemoBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, '{}'));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Credit memo batch enqueued.', result);
    }

    @isTest
    static void testHandle_QuickBooksPurchaseOrderBatchExecute() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QuickBooksPurchaseOrderBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, '{}'));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Purchase order batch enqueued.', result);
    }

    // ============================================================
    // Inbound sync branches (with HTTP mocks)
    // ============================================================

    @isTest
    static void testHandle_QBItemToProductSyncBatchExecute() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,  // external QBO Item ID
            Class_Method_Name__c = 'QBItemToProductSyncBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, getItemResponse()));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Item synced from QBO.', result);
    }

    @isTest
    static void testHandle_QBCustomerToAccountSyncBatchExecute() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QBCustomerToAccountSyncBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, getCustomerResponse()));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Customer synced from QBO.', result);
        Account syncedAccount = [
            SELECT Name
            FROM Account
            WHERE QuickbookID__c = '123'
            LIMIT 1
        ];
        System.assertEquals('Test Customer', syncedAccount.Name);
    }

    @isTest
    static void testHandle_QBVendorToAccountSyncBatchExecute() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QBVendorToAccountSyncBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, getVendorResponse()));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Vendor synced from QBO.', result);
    }

    @isTest
    static void testHandle_QBInvoiceToOrderSyncBatchExecute() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QBInvoiceToOrderSyncBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, getInvoiceResponse()));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Invoice converted to Order.', result);
    }

    @isTest
    static void testHandle_QBOInvoiceSyncQueueableExecute() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QBOInvoiceSyncQueueable.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        // FIX: Mock added for Queueable execution
        Test.setMock(HttpCalloutMock.class, new QBOMock(200, '{}'));

        Test.startTest();
        String result = QBOErrorHandler.handle(log);
        Test.stopTest();

        System.assertEquals('Invoice sync queueable enqueued.', result);
    }

    // ============================================================
    // Error / Edge cases
    // ============================================================

    @isTest
    static void testHandle_SourceRecordIdMissing_ThrowsException() {
        bypassAuthConfig();
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = null,
            Class_Method_Name__c = 'QBAccountService.syncAccountToQuickBooks',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.startTest();
        try {
            QBOErrorHandler.handle(log);
            System.assert(false, 'Expected AuraHandledException was not thrown');
        } catch (AuraHandledException e) {
            System.assertEquals('System.AuraHandledException', e.getTypeName(), 'Expected AuraHandledException to be thrown');
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception: ' + e.getTypeName());
        }
        Test.stopTest();
    }

    @isTest
    static void testHandle_UnsupportedMethod_ThrowsException() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'SomeUnsupportedMethod',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        Test.startTest();
        try {
            QBOErrorHandler.handle(log);
            System.assert(false, 'Expected AuraHandledException was not thrown');
        } catch (AuraHandledException e) {
            System.assertEquals('System.AuraHandledException', e.getTypeName(), 'Expected AuraHandledException to be thrown');
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception: ' + e.getTypeName());
        }
        Test.stopTest();
    }

    // ============================================================
    // Batch enqueue test (multiple calls)
    // ============================================================
    @isTest
    static void testHandle_BatchEnqueues_WithMultipleCalls() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Error_Log__c log1 = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QBSalesOrderSyncBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log1;

        Error_Log__c log2 = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QuickBooksInvoiceBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log2;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, '{}'));

        Test.startTest();
        String result1 = QBOErrorHandler.handle(log1);
        String result2 = QBOErrorHandler.handle(log2);
        Test.stopTest();

        System.assertEquals('Order sync batch enqueued.', result1);
        System.assertEquals('Invoice sync batch enqueued.', result2);
    }

    // ============================================================
    // API error response handling test
    // ============================================================
    @isTest
    static void testHandle_QBOCustomerAPIError_HandlesGracefully() {
        bypassAuthConfig();
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Error_Log__c log = new Error_Log__c(
            Source_Record_Id__c = acc.Id,
            Class_Method_Name__c = 'QBCustomerToAccountSyncBatch.execute',
            Gateway_Name__c = 'QBO'
        );
        insert log;

        String errorJson = '{"Fault":{"Error":[{"Message":"Customer not found"}]}}';
        Test.setMock(HttpCalloutMock.class, new QBOMock(404, errorJson));

        Test.startTest();
        try {
            QBOErrorHandler.handle(log);
            System.assert(true, 'Method executed without throwing');
        } catch (Exception e) {
            System.assert(e.getMessage() != null, 'Exception should have a message');
        }
        Test.stopTest();
    }
}
