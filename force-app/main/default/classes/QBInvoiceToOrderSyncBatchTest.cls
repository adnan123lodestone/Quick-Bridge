@isTest
private class QBInvoiceToOrderSyncBatchTest {

    private class QBInvoiceToOrderMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                res.setStatusCode(200);
                res.setBody('{"QueryResponse":{"Invoice":[{"Id":"INV-1","TxnDate":"2025-01-15","CustomerMemo":{"value":"Invoice memo"},"CustomerRef":{"value":"QB-CUST-1","name":"Sync Customer"},"Line":[{"Id":"1","DetailType":"SalesItemLineDetail","Description":"Line 1","SalesItemLineDetail":{"Qty":2,"UnitPrice":10,"ItemRef":{"value":"QB-ITEM-1","name":"Sync Product"}}}],"BillAddr":{"Line1":"B1","City":"C1","CountrySubDivisionCode":"S1","PostalCode":"111","Country":"US"}}]}}');
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        insert new Account(Name = 'Invoice Sync Seed');
    }

    @isTest
    static void testBatchStartExecuteFinish() {
        Test.setMock(HttpCalloutMock.class, new QBInvoiceToOrderMock());

        Test.startTest();
        Database.executeBatch(new QBInvoiceToOrderSyncBatch('2025-01-01'), 1);
        Test.stopTest();

        System.assertEquals(false, QBInvoiceToOrderSyncBatch.isProcessing);

        Account syncedAccount = [
            SELECT Id, Name, QuickbookID__c
            FROM Account
            WHERE QuickbookID__c = 'QB-CUST-1'
            LIMIT 1
        ];
        Product2 syncedProduct = [
            SELECT Id, Name, QuickbookID__c
            FROM Product2
            WHERE QuickbookID__c = 'QB-ITEM-1'
            LIMIT 1
        ];
        Order syncedOrder = [
            SELECT Id, QuickbookID__c, AccountId, EffectiveDate, Description
            FROM Order
            WHERE QuickbookID__c = 'INV-1'
            LIMIT 1
        ];
        OrderItem syncedItem = [
            SELECT Id, OrderId, Product2Id, Quantity, UnitPrice, Description, QB_LineItemID__c
            FROM OrderItem
            WHERE OrderId = :syncedOrder.Id
            LIMIT 1
        ];

        System.assertEquals('QB-CUST-1', syncedAccount.QuickbookID__c);
        System.assertEquals('QB-ITEM-1', syncedProduct.QuickbookID__c);
        System.assertEquals('INV-1', syncedOrder.QuickbookID__c);
        System.assertEquals(syncedAccount.Id, syncedOrder.AccountId);
        System.assertEquals(Date.newInstance(2025, 1, 15), syncedOrder.EffectiveDate);
        System.assertEquals('Invoice memo', syncedOrder.Description);
        System.assertEquals(syncedProduct.Id, syncedItem.Product2Id);
        System.assertEquals(2, syncedItem.Quantity);
        System.assertEquals(10, syncedItem.UnitPrice);
        System.assertEquals('Line 1', syncedItem.Description);
        System.assertEquals('INV-1:1', syncedItem.QB_LineItemID__c);
    }
}