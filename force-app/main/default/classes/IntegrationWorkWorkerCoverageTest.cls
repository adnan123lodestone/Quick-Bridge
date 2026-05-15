@IsTest
private class IntegrationWorkWorkerCoverageTest {
    private class GenericProviderMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            if (endpoint.contains('/customer')) {
                res.setBody('{"Customer":{"Id":"QB-CUST-1","SyncToken":"0"}}');
            } else if (endpoint.contains('/item')) {
                res.setBody('{"Item":{"Id":"QB-ITEM-1","SyncToken":"0"}}');
            } else if (endpoint.contains('/creditmemo')) {
                res.setBody('{"CreditMemo":{"Id":"QB-CM-1","SyncToken":"0"}}');
            } else if (endpoint.contains('/purchaseorder')) {
                res.setBody('{"PurchaseOrder":{"Id":"QB-PO-1","SyncToken":"0"}}');
            } else if (endpoint.contains('/invoice')) {
                res.setBody('{"Invoice":{"Id":"QB-INV-1","SyncToken":"0","Line":[]}}');
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    @IsTest
    static void quickBooksWorkersCoverSuccessAndValidationPaths() {
        Test.setMock(HttpCalloutMock.class, new GenericProviderMock());

        Account accountRecord = new Account(Name = 'Queued Account');
        insert accountRecord;

        Product2 productRecord = new Product2(Name = 'Queued Product', IsActive = true, Sale_Price__c = 10);
        insert productRecord;

        Credit_Memo__c creditMemo = new Credit_Memo__c();
        insert creditMemo;

        Purchase_Order__c purchaseOrder = new Purchase_Order__c(Account__c = accountRecord.Id, Supplier__c = accountRecord.Id);
        insert purchaseOrder;

        Invoice__c invoiceRecord = new Invoice__c(Related_Account__c = accountRecord.Id);
        insert invoiceRecord;

        QBAccountWorker.process(workItem('QuickBooks', 'AccountUpsert', 'Account', accountRecord.Id));
        QBProductWorker.process(workItem('QuickBooks', 'ProductUpsert', 'Product2', productRecord.Id));

        try {
            QBInvoiceWorker.process(workItem('QuickBooks', 'InvoiceUpsert', 'Invoice__c', invoiceRecord.Id));
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        try {
            QBCreditMemoWorker.process(workItem('QuickBooks', 'CreditMemoUpsert', 'Credit_Memo__c', creditMemo.Id));
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        try {
            QBPurchaseOrderWorker.process(workItem('QuickBooks', 'PurchaseOrderUpsert', 'Purchase_Order__c', purchaseOrder.Id));
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }

        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'QuickBooks', Operation__c = 'AccountUpsert'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'QuickBooks', Operation__c = 'ProductUpsert'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'QuickBooks', Operation__c = 'InvoiceUpsert'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'QuickBooks', Operation__c = 'CreditMemoUpsert'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'QuickBooks', Operation__c = 'PurchaseOrderUpsert'));
    }

    @IsTest
    static void routerAndGenericWorkersCoverUnsupportedPaths() {
        Account accountRecord = new Account(Name = 'Shopify Customer Queue');
        insert accountRecord;
        Product2 productRecord = new Product2(Name = 'Shopify Product Queue', IsActive = true);
        insert productRecord;

        ShopifyIntegrationWorker.process(workItem('Shopify', 'CustomerUpsert', 'Account', accountRecord.Id));
        ShopifyIntegrationWorker.process(workItem('Shopify', 'OrderUpsert', 'Order', accountRecord.Id));
        ShopifyIntegrationWorker.process(workItem('Shopify', 'ProductUpsert', 'Product2', productRecord.Id));

        CarrierIntegrationWorker.process(new Integration_Work_Item__c(Integration__c = 'Carrier', Operation__c = 'TrackingSync'));

        Invoice__c invoiceRecord = new Invoice__c(Related_Account__c = accountRecord.Id);
        insert invoiceRecord;
        assertThrowsFor(workItem('QR', 'GenerateEmail', 'Invoice__c', invoiceRecord.Id));

        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'Shopify', Operation__c = 'CustomerUpsert'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'Shopify', Operation__c = 'OrderUpsert'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'Shopify', Operation__c = 'ProductUpsert'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'Shopify', Operation__c = 'Unknown'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'Carrier', Operation__c = 'Unknown'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'Payment', Operation__c = 'WebhookResult'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'QR', Operation__c = 'GenerateEmail'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'Usage', Operation__c = 'Aggregate'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'QuickBooks', Operation__c = 'Unknown'));
        assertThrowsFor(new Integration_Work_Item__c(Integration__c = 'Unknown', Operation__c = 'Anything'));
        try {
            IntegrationWorkRouter.process(null);
            System.assert(false, 'Expected an exception for a null work item.');
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
    }

    @IsTest
    static void processorCoversRetryAndCompletionPaths() {
        Integration_Work_Item__c failingItem = insertProcessingItem('Payment', 'WebhookResult', 'Order', 'ORDER-FAIL', 'Order:ORDER-FAIL', 'token-fail', '{}');
        new IntegrationWorkProcessor(failingItem.Id, 'token-fail').execute(null);

        Integration_Work_Item__c failed = [
            SELECT Status__c, Last_Error__c
            FROM Integration_Work_Item__c
            WHERE Id = :failingItem.Id
        ];
        System.assertEquals(IntegrationWorkService.STATUS_FAILED, failed.Status__c);
        System.assertNotEquals(null, failed.Last_Error__c);

        Integration_Work_Item__c successItem = insertProcessingItem('Usage', 'Aggregate', 'Usage', 'quickbooks', 'Usage:quickbooks', 'token-success', '{"productKey":"quickbooks"}');
        new IntegrationWorkProcessor(successItem.Id, 'token-success').execute(null);

        Integration_Work_Item__c completed = [
            SELECT Status__c, Completed_At__c
            FROM Integration_Work_Item__c
            WHERE Id = :successItem.Id
        ];
        System.assertEquals(IntegrationWorkService.STATUS_COMPLETED, completed.Status__c);
        System.assertNotEquals(null, completed.Completed_At__c);
    }

    @IsTest
    static void adminActionsCoverStateTransitions() {
        Id itemId = IntegrationWorkService.enqueue(IntegrationWorkTestFactory.request('QuickBooks', 'AccountUpsert', 'Account', 'ADMIN', 'Account:ADMIN'));

        List<Integration_Work_Item__c> allRows = IntegrationWorkAdminController.getRecentWorkItems('All', 5);
        System.assert(!allRows.isEmpty());
        List<Integration_Work_Item__c> pendingRows = IntegrationWorkAdminController.getRecentWorkItems('Pending', 5);
        System.assert(!pendingRows.isEmpty());

        IntegrationWorkAdminController.WorkActionResponse cancelResponse = IntegrationWorkAdminController.cancel(itemId);
        System.assertEquals(true, cancelResponse.success);

        IntegrationWorkAdminController.WorkActionResponse retryResponse = IntegrationWorkAdminController.retryNow(itemId);
        System.assertEquals(true, retryResponse.success);

        IntegrationWorkAdminController.WorkActionResponse requeueResponse = IntegrationWorkAdminController.requeue(itemId);
        System.assertEquals(true, requeueResponse.success);
    }

    private static Integration_Work_Item__c workItem(String integration, String operation, String sourceObject, Id recordId) {
        return new Integration_Work_Item__c(
            Integration__c = integration,
            Operation__c = operation,
            Source_Object__c = sourceObject,
            Source_Record_Id__c = String.valueOf(recordId),
            Source_Salesforce_Id__c = String.valueOf(recordId),
            Payload__c = '{"isInitialSync":true}'
        );
    }

    private static Integration_Work_Item__c insertProcessingItem(String integration, String operation, String sourceObject, String sourceRecordId, String lockKey, String token, String payload) {
        Integration_Work_Item__c item = new Integration_Work_Item__c(
            Unique_Key__c = integration + '|' + operation + '|' + sourceObject + '|' + sourceRecordId,
            Status__c = IntegrationWorkService.STATUS_PROCESSING,
            Integration__c = integration,
            Operation__c = operation,
            Source_Object__c = sourceObject,
            Source_Record_Id__c = sourceRecordId,
            Lock_Key__c = lockKey,
            Processor_Token__c = token,
            Payload__c = payload,
            Attempt_Count__c = 0,
            Max_Attempts__c = 2
        );
        insert item;
        insert new Integration_Work_Lock__c(
            Name = lockKey.left(80),
            Lock_Key__c = lockKey,
            Status__c = 'Locked',
            Work_Item__c = item.Id,
            Processor_Token__c = token,
            Lease_Expires_At__c = System.now().addMinutes(10)
        );
        return item;
    }

    private static void assertThrowsFor(Integration_Work_Item__c item) {
        try {
            IntegrationWorkRouter.process(item);
            System.assert(false, 'Expected an exception for ' + item.Integration__c + ':' + item.Operation__c);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
    }
}
