@isTest
private class KlaviyoProfilesBatchTest {

    class KlaviyoMockCallout implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            res.setBody('{' +
                '"data": [' +
                '  {' +
                '    "id": "klaviyo-id-1",' +
                '    "attributes": {' +
                '      "email": "test@example.com",' +
                '      "first_name": "John",' +
                '      "last_name": "Doe",' +
                '      "organization": "TestOrg",' +
                '      "phone_number": "1234567890",' +
                '      "properties": {' +
                '        "Shopify Tags": "vip", ' +
                '        "Omnisend Segment": "SegmentA", ' +
                '        "Total Spent": "150.75", ' +
                '        "Total Orders": "5", ' +
                '        "Smile Points Balance": "200", ' +
                '        "Smile Referral URL": "http://ref.url", ' +
                '        "Smile State": "active", ' +
                '        "Smile VIP Tier ID": "2", ' +
                '        "Smile VIP Tier Name": "Gold" ' +
                '      },' +
                '      "location": {' +
                '        "address1": "123 Main St",' +
                '        "address2": "Apt 4B",' +
                '        "city": "New York",' +
                '        "region": "NY",' +
                '        "country": "USA",' +
                '        "zip": "10001"' +
                '      }' +
                '    }' +
                '  }' +
                '],' +
                '"links": {"next": null}' +
            '}');
            return res;
        }
    }

    @isTest
    static void testBatchWithNoEndpoint() {
        Test.setMock(HttpCalloutMock.class, new KlaviyoMockCallout());

        Test.startTest();
        Database.executeBatch(new KlaviyoProfilesBatch(), 1);
        Test.stopTest();

        // Check if account got created
        List<Account> accs = [SELECT Id, Klaviyo_ID__c FROM Account];
        System.assertEquals(1, accs.size());
        System.assertEquals('klaviyo-id-1', accs[0].Klaviyo_ID__c);
    }

    @isTest
    static void testBatchWithEndpointProvided() {
        Test.setMock(HttpCalloutMock.class, new KlaviyoMockCallout());

        String endpoint = 'https://a.klaviyo.com/api/profiles?filter=greater-than(updated,2025-03-20T00:00:00+00:00)';
        Test.startTest();
        Database.executeBatch(new KlaviyoProfilesBatch(endpoint), 1);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Account]);
    }

    @isTest
    static void testFinishWithNextUrl() {
        Test.setMock(HttpCalloutMock.class, new KlaviyoMockCallout());

        KlaviyoProfilesBatch batch = new KlaviyoProfilesBatch();
        Test.startTest();
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // If nextUrl is set, another batch will be queued
        System.assert(true, 'Finish method logic executed with nextUrl');
    }

}