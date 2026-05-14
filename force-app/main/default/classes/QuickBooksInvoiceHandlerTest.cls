@isTest
private class QuickBooksInvoiceHandlerTest {

    private class QBInvoiceHandlerMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String method = req.getMethod();

            if (method == 'POST' && endpoint.contains('/invoice')) {
                res.setStatusCode(200);
                res.setBody('{"Invoice":{"Id":"QB-INV-1","Line":[{"Id":"1"}]}}');
                return res;
            }
            if (method == 'GET' && endpoint.contains('/invoice/')) {
                res.setStatusCode(200);
                res.setBody('{"Invoice":{"Id":"QB-INV-1","SyncToken":"0","Line":[]}}');
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Invoice Handler Account', QuickbookID__c = 'QB-CUST-10');
        insert acc;

        Product2 p = new Product2(Name = 'Invoice Handler Product', IsActive = true, QuickbookID__c = 'QB-ITEM-10');
        insert p;

        Id stdPbId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id = p.Id,
            UnitPrice = 50,
            IsActive = true
        );

        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPbId
        );
        insert ord;

        insert new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :p.Id AND Pricebook2Id = :stdPbId LIMIT 1].Id,
            Product2Id = p.Id,
            Quantity = 1,
            UnitPrice = 50
        );
    }

    @isTest
    static void testHandleOrderEventsUpdatePath() {
        Test.setMock(HttpCalloutMock.class, new QBInvoiceHandlerMock());
        Order ord = [SELECT Id, EffectiveDate, TotalAmount, QuickbookID__c FROM Order LIMIT 1];
        ord.QuickbookID__c = 'QB-INV-10';
        update ord;

        Order oldOrd = ord.clone(false, true, true, true);
        ord.EffectiveDate = Date.today().addDays(1);

        Test.startTest();
        QuickBooksInvoiceHandler.handleOrderEvents(new List<Order>{ ord }, new Map<Id, Order>{ ord.Id => oldOrd }, true);
        Test.stopTest();

        System.assertEquals(false, QuickBooksInvoiceHandler.isProcessing);
    }

    @isTest
    static void testHandleOrderItemEventsInsertUpdateAndDelete() {
        Test.setMock(HttpCalloutMock.class, new QBInvoiceHandlerMock());
        Order ord = [SELECT Id, QuickbookID__c FROM Order LIMIT 1];
        if (ord.QuickbookID__c == null) {
            ord.QuickbookID__c = 'QB-INV-11';
            update ord;
        }

        Product2 p = [SELECT Id FROM Product2 WHERE Name = 'Invoice Handler Product' LIMIT 1];
        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :p.Id AND Pricebook2Id = :stdPbId LIMIT 1];

        OrderItem oi = new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe.Id, Product2Id = p.Id, Quantity = 2, UnitPrice = 60);
        insert oi;

        OrderItem oldOi = [SELECT Id, Quantity, UnitPrice, QB_LineItemID__c, OrderId FROM OrderItem WHERE Id = :oi.Id];
        oi.Quantity = 3;
        update oi;

        Test.startTest();
        
        QuickBooksInvoiceHandler.handleOrderItemEvents(new List<OrderItem>{ oi }, new Map<Id, OrderItem>(), true, false);
        QuickBooksInvoiceHandler.handleOrderItemEvents(new List<OrderItem>{ oi }, new Map<Id, OrderItem>{ oi.Id => oldOi }, false, true);
        QuickBooksInvoiceHandler.handleOrderItemDeletion(new List<OrderItem>{ oi });

        QuickBooksInvoiceHandler.setBatchContext(true);
        QuickBooksInvoiceHandler.handleOrderItemDeletion(new List<OrderItem>{ oi });
        QuickBooksInvoiceHandler.setBatchContext(false);
        
        Test.stopTest();

        System.assertEquals(false, QuickBooksInvoiceHandler.isProcessing);
    }
}