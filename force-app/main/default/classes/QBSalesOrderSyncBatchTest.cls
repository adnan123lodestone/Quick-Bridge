@isTest
private class QBSalesOrderSyncBatchTest {

    private static String lastBody;

    // Captures the outbound request body so we can assert the QBO JSON shape.
    private class CaptureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            lastBody = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            // Minimal QBO Estimate/Invoice response with one line so the batch can
            // read back Id / SyncToken / Line.Id.
            res.setBody(
                '{"Estimate":{"Id":"999","SyncToken":"0","Line":[' +
                '{"Id":"1","DetailType":"SalesItemLineDetail"}]},' +
                '"Invoice":{"Id":"999","SyncToken":"0","Line":[' +
                '{"Id":"1","DetailType":"SalesItemLineDetail"}]}}'
            );
            return res;
        }
    }

    @isTest
    static void testDottedLineMappingsProduceValidQboJson() {
        // Arrange: a Draft order with one line item and an account that has a QBO id.
        Account acc = new Account(Name = 'Acme', QuickbookID__c = '87');
        insert acc;

        Product2 prod = new Product2(Name = 'Widget', QuickbookID__c = '22');
        insert prod;

        Pricebook2 standardPb = new Pricebook2(Id = Test.getStandardPricebookId(), IsActive = true);
        update standardPb;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPb.Id, Product2Id = prod.Id,
            UnitPrice = 12, IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acc.Id, Status = 'Draft',
            EffectiveDate = Date.today(), Pricebook2Id = standardPb.Id
        );
        insert ord;

        insert new OrderItem(
            OrderId = ord.Id, PricebookEntryId = pbe.Id,
            Quantity = 12, UnitPrice = 12, Product2Id = prod.Id
        );

        Test.setMock(HttpCalloutMock.class, new CaptureMock());

        // Act
        Test.startTest();
        Database.executeBatch(new QBSalesOrderSyncBatch(new Set<Id>{ ord.Id }, false), 1);
        Test.stopTest();

        // Assert: the serialized payload must not contain any literal dotted property
        // names (the fault-2010 bug), regardless of how the line mappings are stored.
        String body = lastBody;
        System.assertNotEquals(null, body, 'A request body should have been sent to QBO.');
        System.assert(
            !body.contains('Line.SalesItemLineDetail'),
            'Payload must not contain literal dotted keys: ' + body
        );
        System.assert(!body.contains('"TotalAmt"'),
            'Read-only TotalAmt must not be sent: ' + body);
        // Quantity/UnitPrice should appear as real QBO leaf properties.
        System.assert(body.contains('"Qty"'), 'Expected a Qty property: ' + body);
        System.assert(body.contains('"UnitPrice"'), 'Expected a UnitPrice property: ' + body);
        System.assert(body.contains('"ItemRef"'), 'Expected an ItemRef from Product2: ' + body);

        // The order should have captured the QBO id returned by the mock.
        Order synced = [SELECT QuickbookID__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals('999', synced.QuickbookID__c, 'Order should store the QBO id.');
    }
}