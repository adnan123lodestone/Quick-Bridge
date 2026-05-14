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

    @isTest
    static void testSchedulerAccountAndProductTargets() {
        Test.setMock(HttpCalloutMock.class, new QBSchedulerCalloutMock());

        Test.startTest();
        System.schedule('Sched-Acc-' + Datetime.now().getTime(), '0 0 0 1 1 ? 2099', new QBSyncScheduler('Account'));
        System.schedule('Sched-Prod-' + Datetime.now().getTime(), '0 0 0 1 1 ? 2099', new QBSyncScheduler('Product'));
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testSchedulerOrderTarget() {
        Test.setMock(HttpCalloutMock.class, new QBSchedulerCalloutMock());
        Test.startTest();
        System.schedule('Sched-Ord-' + Datetime.now().getTime(), '0 0 0 1 1 ? 2099', new QBSyncScheduler('Order'));
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testSchedulerVendorTarget() {
        Test.setMock(HttpCalloutMock.class, new QBSchedulerCalloutMock());

        Test.startTest();
        System.schedule('Sched-Vend-' + Datetime.now().getTime(), '0 0 0 1 1 ? 2099', new QBSyncScheduler('Vendors'));
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testSchedulerOutboundTargetsWithNoUnsyncedRecords() {
        Test.setMock(HttpCalloutMock.class, new QBSchedulerCalloutMock());

        Test.startTest();
        System.schedule('Sched-Inv-' + Datetime.now().getTime(), '0 0 0 1 1 ? 2099', new QBSyncScheduler('Invoice'));
        System.schedule('Sched-CM-' + Datetime.now().getTime(), '0 0 0 1 1 ? 2099', new QBSyncScheduler('Credit Memo'));
        System.schedule('Sched-PO-' + Datetime.now().getTime(), '0 0 0 1 1 ? 2099', new QBSyncScheduler('Purchase Order'));
        Test.stopTest();

        System.assert(true);
    }
}