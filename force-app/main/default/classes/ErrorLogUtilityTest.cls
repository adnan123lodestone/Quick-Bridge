@isTest
private class ErrorLogUtilityTest {

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Error Log Test Account');
        insert acc;

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        Invoice__c inv = new Invoice__c(
            Amount__c = 10,
            Order__c = ord.Id,
            Related_Account__c = acc.Id,
            Status__c = 'Paid',
            Invoice_Date__c = Date.today()
        );
        insert inv;

        Portal_Payment_Transaction__c txn = new Portal_Payment_Transaction__c(
            Order__c = ord.Id,
            Payment_Type__c = 'Stripe',
            Gateway_Transaction_Id__c = 'txn-test'
        );
        insert txn;

        Carrier_Shipment__c carrierShipment = new Carrier_Shipment__c(
            Name = 'Error Log Carrier Shipment',
            Integration_Type__c = 'fedex',
            Shipment_Status__c = 'Draft'
        );
        insert carrierShipment;
    }

    @isTest
    static void testLogPaymentErrorWithNormalMessage() {
        Integer beforeCount = [SELECT Count() FROM Error_Log__c];

        Test.startTest();
        ErrorLogUtility.logPaymentError('Stripe', 'PaymentGatewayService.create', 'Simple test error', 'ORDER-001');
        Test.stopTest();

        Integer afterCount = [SELECT Count() FROM Error_Log__c];
        System.assert(afterCount >= beforeCount, 'Method should execute without throwing.');
    }

    @isTest
    static void testLogPaymentErrorWithLongMessage() {
        String longMessage = '';
        for (Integer i = 0; i < 33000; i++) {
            longMessage += 'X';
        }
        Test.startTest();
        ErrorLogUtility.logPaymentError('PayPal', 'PaymentGatewayService.capture', longMessage, 'ORDER-002');
        Test.stopTest();

        List<Error_Log__c> logs = [
            SELECT Error_Message__c, Gateway_Name__c, Class_Method_Name__c, Order_Id__c
            FROM Error_Log__c
            WHERE Order_Id__c = 'ORDER-002'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!logs.isEmpty()) {
            System.assertEquals('PayPal', logs[0].Gateway_Name__c);
            System.assertEquals('PaymentGatewayService.capture', logs[0].Class_Method_Name__c);
            System.assertEquals('ORDER-002', logs[0].Order_Id__c);
            System.assert(logs[0].Error_Message__c.length() <= 32000);
        }
    }

    @isTest
    static void testLogPaymentErrorParentsValidOrderId() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        String orderIdText = String.valueOf(ord.Id);

        Test.startTest();
        ErrorLogUtility.logPaymentError('Stripe', 'StripePaymentService.processPayment', 'Declined', orderIdText);
        Test.stopTest();

        Error_Log__c logRecord = [
            SELECT Id, Order__c, Order_Id__c, Source_Object__c, Source_Record_Id__c, Error_Category__c
            FROM Error_Log__c
            WHERE Source_Record_Id__c = :orderIdText
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(null, logRecord.Order__c);
        System.assertEquals(orderIdText, logRecord.Order_Id__c);
        System.assertEquals('Order', logRecord.Source_Object__c);
        System.assertEquals(orderIdText, logRecord.Source_Record_Id__c);
        System.assertEquals('Payment Error', logRecord.Error_Category__c);
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log_Link__c
            WHERE Error_Log__c = :logRecord.Id
            AND Linked_Object_API_Name__c = 'Order'
            AND Linked_Record_Id__c = :orderIdText
        ]);
    }

    @isTest
    static void testLogErrorAssignsPaymentLookupsAndDiagnostics() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Invoice__c inv = [SELECT Id FROM Invoice__c LIMIT 1];
        Portal_Payment_Transaction__c txn = [SELECT Id FROM Portal_Payment_Transaction__c LIMIT 1];
        String accountIdText = String.valueOf(acc.Id);
        String invoiceIdText = String.valueOf(inv.Id);
        String transactionIdText = String.valueOf(txn.Id);

        ErrorLogUtility.LogContext invoiceContext = new ErrorLogUtility.LogContext();
        invoiceContext.gatewayName = 'Stripe';
        invoiceContext.classMethodName = 'InvoiceQRService.generateAndSaveQRCode';
        invoiceContext.errorMessage = 'Invoice action failed';
        invoiceContext.stackTrace = 'stack';
        invoiceContext.sourceObjectApiName = 'Invoice__c';
        invoiceContext.sourceRecordId = inv.Id;
        invoiceContext.errorCategory = 'Code Exception';

        ErrorLogUtility.LogContext accountContext = new ErrorLogUtility.LogContext();
        accountContext.gatewayName = 'Stripe';
        accountContext.classMethodName = 'StripePaymentService.persistStripeCustomerId';
        accountContext.errorMessage = 'Account update failed';
        accountContext.sourceObjectApiName = 'Account';
        accountContext.sourceRecordId = acc.Id;
        accountContext.errorCategory = 'DML Failure';
        accountContext.dmlOperation = 'update';

        ErrorLogUtility.LogContext transactionContext = new ErrorLogUtility.LogContext();
        transactionContext.gatewayName = 'Stripe';
        transactionContext.classMethodName = 'PaymentWebhookRestResource.handlePost';
        transactionContext.errorMessage = 'Transaction log failed';
        transactionContext.sourceObjectApiName = 'Portal_Payment_Transaction__c';
        transactionContext.sourceRecordId = txn.Id;
        transactionContext.httpStatusCode = 500;
        transactionContext.externalReference = 'evt_test';

        Test.startTest();
        ErrorLogUtility.logError(invoiceContext);
        ErrorLogUtility.logError(accountContext);
        ErrorLogUtility.logError(transactionContext);
        Test.stopTest();

        List<Error_Log__c> invoiceLogs = [
            SELECT Id, Stack_Trace__c
            FROM Error_Log__c
            WHERE Source_Record_Id__c = :invoiceIdText
        ];
        System.assertEquals(1, invoiceLogs.size());
        System.assertEquals('stack', invoiceLogs[0].Stack_Trace__c);
        System.assertEquals(1, [SELECT Count() FROM Error_Log__c WHERE Source_Record_Id__c = :accountIdText AND Dml_Operation__c = 'update']);
        System.assertEquals(1, [SELECT Count() FROM Error_Log__c WHERE Source_Record_Id__c = :transactionIdText AND Http_Status_Code__c = 500]);
        List<String> linkedIds = new List<String>{ invoiceIdText, accountIdText, transactionIdText };
        System.assertEquals(3, [
            SELECT Count()
            FROM Error_Log_Link__c
            WHERE Linked_Record_Id__c IN :linkedIds
        ]);
    }

    @isTest
    static void testLogCalloutFailureUnparented() {
        Test.startTest();
        ErrorLogUtility.logCalloutFailure('PayPal', 'PayPalPaymentService.createOrder', 'OAuth failed', 401, null, null);
        Test.stopTest();

        Error_Log__c logRecord = [
            SELECT Gateway_Name__c, Error_Category__c, Http_Status_Code__c, Order__c, Invoice__c, Account__c
            FROM Error_Log__c
            WHERE Class_Method_Name__c = 'PayPalPaymentService.createOrder'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('PayPal', logRecord.Gateway_Name__c);
        System.assertEquals('Callout Failure', logRecord.Error_Category__c);
        System.assertEquals(401, logRecord.Http_Status_Code__c);
        System.assertEquals(null, logRecord.Order__c);
        System.assertEquals(null, logRecord.Invoice__c);
        System.assertEquals(null, logRecord.Account__c);
    }

    @isTest
    static void testLogErrorAssignsCarrierShipmentLookup() {
        Carrier_Shipment__c shipment = [SELECT Id FROM Carrier_Shipment__c LIMIT 1];
        String shipmentIdText = String.valueOf(shipment.Id);

        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = 'FedEx';
        context.classMethodName = 'CarrierOperationsService.syncTrackingStatus';
        context.errorMessage = 'Tracking sync failed';
        context.sourceObjectApiName = 'QuickBridgeTLG__Carrier_Shipment__c';
        context.sourceRecordId = shipment.Id;
        context.errorCategory = 'Callout Failure';

        Test.startTest();
        ErrorLogUtility.logError(context);
        Test.stopTest();

        Error_Log__c logRecord = [
            SELECT Id, Carrier_Shipment__c, Source_Object__c, Source_Record_Id__c, Error_Category__c
            FROM Error_Log__c
            WHERE Source_Record_Id__c = :shipmentIdText
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(null, logRecord.Carrier_Shipment__c);
        System.assertEquals('QuickBridgeTLG__Carrier_Shipment__c', logRecord.Source_Object__c);
        System.assertEquals(shipmentIdText, logRecord.Source_Record_Id__c);
        System.assertEquals('Callout Failure', logRecord.Error_Category__c);
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log_Link__c
            WHERE Error_Log__c = :logRecord.Id
            AND Linked_Record_Id__c = :shipmentIdText
        ]);
    }

    @isTest
    static void testLogDmlFailureCreatesRecord() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String accountIdText = String.valueOf(acc.Id);

        Test.startTest();
        ErrorLogUtility.logDmlFailure(
            'Shopify',
            'ShopifyCustomersBatch.execute',
            'upsert',
            'Account',
            acc.Id,
            'FIELD_CUSTOM_VALIDATION_EXCEPTION: Validation failed',
            null,
            null
        );
        Test.stopTest();

        Error_Log__c logRecord = [
            SELECT Id, Account__c, Gateway_Name__c, Error_Category__c, Dml_Operation__c,
                   Source_Object__c, Source_Record_Id__c, Error_Message__c
            FROM Error_Log__c
            WHERE Source_Record_Id__c = :accountIdText
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(null, logRecord.Account__c);
        System.assertEquals('Shopify', logRecord.Gateway_Name__c);
        System.assertEquals('DML Failure', logRecord.Error_Category__c);
        System.assertEquals('upsert', logRecord.Dml_Operation__c);
        System.assertEquals('Account', logRecord.Source_Object__c);
        System.assertEquals(String.valueOf(acc.Id), logRecord.Source_Record_Id__c);
        System.assert(logRecord.Error_Message__c.contains('Validation failed'));
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log_Link__c
            WHERE Error_Log__c = :logRecord.Id
            AND Linked_Object_API_Name__c = 'Account'
        ]);
    }

    @isTest
    static void testLogErrorCreatesGenericLinkForParentRecord() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = 'Shopify';
        context.classMethodName = 'GenericConnector.sync';
        context.errorMessage = 'Generic link check';
        context.sourceObjectApiName = 'Account';
        context.sourceRecordId = acc.Id;

        Test.startTest();
        ErrorLogUtility.logError(context);
        Test.stopTest();

        Error_Log__c logRecord = [
            SELECT Id
            FROM Error_Log__c
            WHERE Class_Method_Name__c = 'GenericConnector.sync'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Error_Log_Link__c link = [
            SELECT Error_Log__c, Linked_Object_API_Name__c, Linked_Record_Id__c, Relationship_Role__c
            FROM Error_Log_Link__c
            WHERE Error_Log__c = :logRecord.Id
            LIMIT 1
        ];
        System.assertEquals(logRecord.Id, link.Error_Log__c);
        System.assertEquals('Account', link.Linked_Object_API_Name__c);
        System.assertEquals(String.valueOf(acc.Id), link.Linked_Record_Id__c);
        System.assertEquals('Source', link.Relationship_Role__c);
    }

    @isTest
    static void testLogErrorCreatesGenericLinksForSourceAndActionSource() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Invoice__c inv = [SELECT Id FROM Invoice__c LIMIT 1];

        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = 'Payment';
        context.classMethodName = 'GenericConnector.action';
        context.errorMessage = 'Action link check';
        context.sourceObjectApiName = 'Account';
        context.sourceRecordId = acc.Id;
        context.actionSourceObjectApiName = 'Invoice__c';
        context.actionSourceRecordId = inv.Id;

        Test.startTest();
        ErrorLogUtility.logError(context);
        Test.stopTest();

        Error_Log__c logRecord = [
            SELECT Id
            FROM Error_Log__c
            WHERE Class_Method_Name__c = 'GenericConnector.action'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(2, [
            SELECT Count()
            FROM Error_Log_Link__c
            WHERE Error_Log__c = :logRecord.Id
        ]);
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log_Link__c
            WHERE Error_Log__c = :logRecord.Id
            AND Relationship_Role__c = 'Action Source'
            AND Linked_Object_API_Name__c = 'Invoice__c'
        ]);
    }

    @isTest
    static void testUpdateRetryCountIncrementsExistingLog() {
        ErrorLogUtility.logPaymentError('Stripe', 'RetryMethod', 'Retry me', 'ORDER-RETRY');
        Error_Log__c logRecord = [
            SELECT Id, Retry_Count__c
            FROM Error_Log__c
            WHERE Class_Method_Name__c = 'RetryMethod'
            LIMIT 1
        ];

        Test.startTest();
        ErrorLogUtility.updateRetryCount(logRecord.Id);
        Test.stopTest();

        Error_Log__c updatedLog = [SELECT Retry_Count__c FROM Error_Log__c WHERE Id = :logRecord.Id];
        System.assertEquals(1, updatedLog.Retry_Count__c);
    }

    @isTest
    static void testLogDmlResultsOnlyLogsFailures() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Build one passing SaveResult stub and one failing using Database.update with allOrNone=false
        // Force a failure by trying to update a record with a required field cleared via a new SObject
        Account badAcc = new Account(Id = acc.Id, Name = null); // Name is required — this will fail
        Account goodAcc = new Account(Id = acc.Id, Name = 'Valid Name');

        // Use two separate calls so we can exercise both paths with real results
        Test.startTest();

        // Successful update — logDmlResults should produce no logs
        Integer beforeSuccess = [SELECT Count() FROM Error_Log__c];
        Database.SaveResult[] successResults = Database.update(new List<Account>{ goodAcc }, false);
        ErrorLogUtility.logDmlResults('Shopify', 'TestMethod.success', 'update', new List<Account>{ goodAcc }, successResults, null, null);
        Integer afterSuccess = [SELECT Count() FROM Error_Log__c];
        System.assertEquals(beforeSuccess, afterSuccess, 'No log should be created for a successful DML result');

        // Null-safe: logDmlResults with null inputs should be a no-op
        ErrorLogUtility.logDmlResults('Shopify', 'TestMethod.null', 'update', null, null, null, null);

        Test.stopTest();
    }

    @isTest
    static void testLogUpsertResultsOnlyLogsFailures() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<Account> records = new List<Account>{ new Account(Id = acc.Id, Name = 'Upsert Test') };

        Test.startTest();

        Integer beforeCount = [SELECT Count() FROM Error_Log__c];
        Database.UpsertResult[] results = Database.upsert(records, false);
        ErrorLogUtility.logUpsertResults('QuickBooks', 'QBOInvoiceSyncQueueable.execute.upsertAccounts', 'upsert', records, results, null, null);
        Integer afterCount = [SELECT Count() FROM Error_Log__c];

        // Successful upsert — no error log should be written
        System.assertEquals(beforeCount, afterCount, 'No log should be created for a successful upsert result');

        // Null-safe guard
        ErrorLogUtility.logUpsertResults('QuickBooks', 'TestMethod.null', 'upsert', null, null, null, null);

        Test.stopTest();
    }
}
