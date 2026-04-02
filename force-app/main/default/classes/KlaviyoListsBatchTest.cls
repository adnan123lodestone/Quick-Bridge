@isTest
private class KlaviyoListsBatchTest {

    // Mock HTTP response for a valid API call
    private class KlaviyoHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(JSON.serialize(new Map<String, Object>{
                'data' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'list_001',
                        'attributes' => new Map<String, Object>{
                            'name' => 'My Test List'
                        },
                        'relationships' => new Map<String, Object>{
                            'profiles' => new Map<String, Object>{
                                'links' => new Map<String, Object>{
                                    'self' => 'https://api.mock/profiles/list_001'
                                }
                            }
                        }
                    }
                },
                'links' => new Map<String, Object>{ 'next' => null }
            }));

            return res;
        }
    }

    // Mock with next URL to trigger recursive batch
    private class KlaviyoHttpMockWithNext implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(JSON.serialize(new Map<String, Object>{
                'data' => new List<Object>{},
                'links' => new Map<String, Object>{ 'next' => 'https://api.mock/nextPage' }
            }));

            return res;
        }
    }

    // Mock with invalid JSON to force exception
    private class KlaviyoBadJsonMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{invalid_json_response}');
            return res;
        }
    }

    @isTest
    static void testExecuteBatch_Successful() {
        Test.setMock(HttpCalloutMock.class, new KlaviyoHttpMock());

        Test.startTest();
        Database.executeBatch(new KlaviyoListsBatch(), 1);
        Test.stopTest();

        // Assert Campaign created
        List<Campaign> results = [
            SELECT Id, Name, Klaviyo_ID__c, Profile_s_URL__c 
            FROM Campaign 
            WHERE Klaviyo_ID__c = 'list_001'
        ];
        System.assertEquals(1, results.size());
        System.assertEquals('My Test List', results[0].Name);
    }

    @isTest
    static void testExecuteBatch_WithEndpoint() {
        Test.setMock(HttpCalloutMock.class, new KlaviyoHttpMock());

        Test.startTest();
        Database.executeBatch(new KlaviyoListsBatch('https://api.mock/lists'), 1);
        Test.stopTest();
    }

    @isTest
    static void testFinishWithNextUrl() {
        Test.setMock(HttpCalloutMock.class, new KlaviyoHttpMockWithNext());

        Test.startTest();
        Database.executeBatch(new KlaviyoListsBatch(), 1);
        Test.stopTest();
    }

    @isTest
    static void testExecuteBatch_ExceptionHandling() {
        Test.setMock(HttpCalloutMock.class, new KlaviyoBadJsonMock());

        Test.startTest();
        Database.executeBatch(new KlaviyoListsBatch(), 1);
        Test.stopTest();

        // No assertion needed – this just ensures no unhandled exceptions
    }
}