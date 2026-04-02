@isTest
private class KlaviyoEventsBatchTest {

    class MockHttp implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"data":[{"id":"evt_123","attributes":{"event_properties":{"Subject":"Test Subject","$extra":{"line_items":[{"title":"Title","sku":"12345","price":"99.99","vendor":"TestVendor","quantity":1,"variant_title":"Variant","product_id":"P123","presentment_title":"Present Title","presentment_variant_title":"Variant Title","product":{"body_html":"<p>Some HTML</p>"},"properties":[{"name":"Size","value":"Large"}] }]}}},"relationships":{"profile":{"data":{"id":"prof_abc"}}}}],"links":{"next":null}}');
            return res;
        }
    }

    @testSetup
    static void setup() {
        // Insert Account to match the profile ID in mock response
        insert new Account(Name = 'Test Account', Klaviyo_ID__c = 'prof_abc');
    }

    @isTest
    static void testBatchExecution() {
        // Register callout mock
        Test.setMock(HttpCalloutMock.class, new MockHttp());

        // Execute the batch
        Test.startTest();
        Database.executeBatch(new KlaviyoEventsBatch(), 1);
        Test.stopTest();

        // Assert: Event created
        List<Event> events = [SELECT Id, Subject, WhatId, Klaviyo_Event_Id__c FROM Event];
        System.assertEquals(1, events.size(), 'One event should be created');
        System.assertEquals('Test Subject', events[0].Subject);
        System.assertEquals('evt_123', events[0].Klaviyo_Event_Id__c);
    }

    @isTest
    static void testBatchExecutionWithoutEvents() {
        // Return empty data
        Test.setMock(HttpCalloutMock.class, new EmptyMock());

        Test.startTest();
        Database.executeBatch(new KlaviyoEventsBatch(), 1);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Event], 'No event should be created');
    }

    class EmptyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"data":[],"links":{"next":null}}');
            return res;
        }
    }
}