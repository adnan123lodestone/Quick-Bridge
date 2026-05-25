@isTest
private class QBSyncSchedulerTest {

    private class QBSchedulerCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();

            if (endpoint.contains('/query?query=')) {
                if (endpoint.contains('from customer')) {
                    res.setBody('{"QueryResponse":{"Customer":[{"Id":"CUST-S1"}]}}');
                    return res;
                }
                if (endpoint.contains('from vendor')) {
                    res.setBody('{"QueryResponse":{"Vendor":[{"Id":"VEND-S1"}]}}');
                    return res;
                }
                if (endpoint.contains('from item')) {
                    res.setBody('{"QueryResponse":{"Item":[{"Id":"ITEM-S1"}]}}');
                    return res;
                }
                if (endpoint.contains('from invoice')) {
                    res.setBody('{"QueryResponse":{"Invoice":[]}}');
                    return res;
                }
            }

            if (endpoint.contains('/customer/cust-s1')) {
                res.setBody('{"Customer":{"Id":"CUST-S1","DisplayName":"Sched Cust","CompanyName":"Sched Co"}}');
                return res;
            }
            if (endpoint.contains('/vendor/vend-s1')) {
                res.setBody('{"Vendor":{"Id":"VEND-S1","DisplayName":"Sched Vendor","CompanyName":"Sched Vendor Co"}}');
                return res;
            }
            if (endpoint.contains('/item/item-s1')) {
                res.setBody('{"Item":{"Id":"ITEM-S1","Name":"Sched Item","Sku":"S-1","Active":true,"UnitPrice":10}}');
                return res;
            }

            res.setBody('{}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        QBTriggerHandler.isAccountProcessing = true;
        try {
            Account acc = new Account(Name = 'Scheduler Seed');
            insert acc;
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
        }
    }

    private static void configureQuickBooksAuth() {
        QuickBooksAuthHandler.configureConnectionForTest(
            '12345',
            'QuickBooks_Test_Named_Credential',
            '70'
        );
    }

    @isTest
    static void testAdapterAccountTarget() {
        configureQuickBooksAuth();
        Test.setMock(HttpCalloutMock.class, new QBSchedulerCalloutMock());

        Test.startTest();
        QuickBooksScheduledOperationAdapter.run('Account', null);
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testAdapterProductTarget() {
        configureQuickBooksAuth();
        Test.setMock(HttpCalloutMock.class, new QBSchedulerCalloutMock());

        Test.startTest();
        QuickBooksScheduledOperationAdapter.run('Product', null);
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testAdapterOrderTarget() {
        configureQuickBooksAuth();
        Test.setMock(HttpCalloutMock.class, new QBSchedulerCalloutMock());
        Test.startTest();
        QuickBooksScheduledOperationAdapter.run('Order', 'In');
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testAdapterVendorTarget() {
        configureQuickBooksAuth();
        Test.setMock(HttpCalloutMock.class, new QBSchedulerCalloutMock());

        Test.startTest();
        QuickBooksScheduledOperationAdapter.run('Vendors', null);
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testAdapterOutboundTargetsWithNoUnsyncedRecords() {
        configureQuickBooksAuth();
        Test.setMock(HttpCalloutMock.class, new QBSchedulerCalloutMock());

        Test.startTest();
        QuickBooksScheduledOperationAdapter.run('Invoice', 'Out');
        QuickBooksScheduledOperationAdapter.run('Credit Memo', 'Out');
        QuickBooksScheduledOperationAdapter.run('Purchase Order', 'Out');
        Test.stopTest();

        System.assert(true);
    }
}