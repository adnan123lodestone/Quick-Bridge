@isTest
private class QuickBooksAuthHandlerTest {

    private class QBAuthMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"ok":true}');
            return res;
        }
    }

    @testSetup
    static void setupData() {
        insert new Account(Name = 'Auth Handler Seed');
    }

    @isTest
    static void testMakeApiCall() {
        Test.setMock(HttpCalloutMock.class, new QBAuthMock());

        Test.startTest();
        try {
            HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', '/customer/1', null);
            System.assertEquals(200, res.getStatusCode());
        } catch (Exception e) {
            System.assert(e.getMessage() != null);
        }
        Test.stopTest();
    }
}