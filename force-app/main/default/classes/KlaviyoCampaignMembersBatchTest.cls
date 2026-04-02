@isTest
private class KlaviyoCampaignMembersBatchTest {

    private class MockHttpResponseGenerator implements HttpCalloutMock {
        private Boolean hasNext;
        
        public MockHttpResponseGenerator(Boolean hasNext) {
            this.hasNext = hasNext;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            Map<String, Object> responseMap = new Map<String, Object>();
            
            // Add fake data
            List<Object> dataList = new List<Object>();
            for (Integer i = 0; i < 2; i++) {
                Map<String, Object> profile = new Map<String, Object>{
                    'id' => 'profile_1234'  // Ensure matching ID for testing
                };
                dataList.add(profile);
            }
            responseMap.put('data', dataList);
            
            // Add pagination if needed
            Map<String, Object> linksMap = new Map<String, Object>();
            if (hasNext) {
                linksMap.put('next', 'https://fake-next-link.com/page2');
            }
            responseMap.put('links', linksMap);
            
            res.setBody(JSON.serialize(responseMap));
            return res;
        }
    }
    
    @isTest
    static void testKlaviyoCampaignMembersBatch_WithProfiles() {
        // Set mock response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(false));
        
        // Get Person Account RecordTypeId
        Id personAccountRTId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        
        // Insert a Campaign
        Campaign camp = new Campaign(
            Name = 'Test Campaign',
            Profile_s_URL__c = 'https://dummy-endpoint.com/profiles'
        );
        insert camp;
        
        // Insert Person Account with matching Klaviyo_ID__c
        Account acc = new Account(
            RecordTypeId = personAccountRTId,
            FirstName = 'Test',
            LastName = 'Account',
            Klaviyo_ID__c = 'profile_1234'
        );
        insert acc;
        
        // Confirm PersonContactId is populated (just to be safe in test)
        // System.assertNotEquals(null, acc.PersonContactId, 'PersonContactId should not be null.');

        Test.startTest();
        KlaviyoCampaignMembersBatch batch = new KlaviyoCampaignMembersBatch(camp.Id);
        Database.executeBatch(batch, 1);
        Test.stopTest();
        
        // Validate CampaignMembers are inserted
        List<CampaignMember> members = [
            SELECT Id, CampaignId, ContactId
            FROM CampaignMember
            WHERE CampaignId = :camp.Id
        ];
        System.assert(members.size() > 0, 'Should have inserted campaign members.');
    }
}