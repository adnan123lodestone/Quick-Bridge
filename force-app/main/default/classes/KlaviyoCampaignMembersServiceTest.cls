@isTest
private class KlaviyoCampaignMembersServiceTest {

    // Mock HTTP callout
    private class KlaviyoProfileHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(JSON.serialize(new Map<String, Object>{
                'data' => new List<Object>{
                    new Map<String, Object>{ 'id' => 'klaviyo_001' },
                    new Map<String, Object>{ 'id' => 'klaviyo_002' }
                },
                'links' => new Map<String, Object>{ 'next' => null }
            }));

            return res;
        }
    }

    @isTest
    static void testAddCampaignMembers_Success() {
        // Create person account (Contact is auto-created)
        Account personAcc = new Account(
            FirstName = 'Test',
            LastName = 'User',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Person Account').getRecordTypeId(),
            Klaviyo_ID__c = 'klaviyo_001'
        );
        insert personAcc;

        // Re-query to get the auto-linked PersonContactId
        personAcc = [SELECT Id, PersonContactId FROM Account WHERE Id = :personAcc.Id];

        // Create Campaign
        Campaign camp = new Campaign(
            Name = 'Test Campaign',
            Profile_s_URL__c = 'https://mock.klaviyo.com/profiles'
        );
        insert camp;

        Test.setMock(HttpCalloutMock.class, new KlaviyoProfileHttpMock());

        Test.startTest();
        KlaviyoCampaignMembersService.Response res = KlaviyoCampaignMembersService.addCampaignMembers(camp.Id);
        Test.stopTest();

        System.assertEquals(200, res.code);
        System.assert(res.message.contains('Inserted'));
    }

    @isTest
    static void testAddCampaignMembers_NoProfileUrl() {
        Campaign camp = new Campaign(Name = 'No URL Campaign');
        insert camp;

        Test.startTest();
        KlaviyoCampaignMembersService.Response res = KlaviyoCampaignMembersService.addCampaignMembers(camp.Id);
        Test.stopTest();

        System.assertEquals(400, res.code);
        System.assert(res.message.contains('Profile_s_URL__c'));
    }

    @isTest
    static void testAddCampaignMembers_NoMatchingAccounts() {
        Campaign camp = new Campaign(
            Name = 'No Accounts',
            Profile_s_URL__c = 'https://mock.klaviyo.com/profiles'
        );
        insert camp;

        Test.setMock(HttpCalloutMock.class, new KlaviyoProfileHttpMock());

        Test.startTest();
        KlaviyoCampaignMembersService.Response res = KlaviyoCampaignMembersService.addCampaignMembers(camp.Id);
        Test.stopTest();

        System.assertEquals(204, res.code);
        System.assert(res.message.contains('No matching accounts'));
    }

    @isTest
    static void testAddCampaignMembers_AlreadyExistingMembers() {
        Account acc = new Account(
            FirstName = 'Already',
            LastName = 'Member',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Person Account').getRecordTypeId(),
            Klaviyo_ID__c = 'klaviyo_001'
        );
        insert acc;

        acc = [SELECT Id, PersonContactId FROM Account WHERE Id = :acc.Id];

        Campaign camp = new Campaign(
            Name = 'Dupes Campaign',
            Profile_s_URL__c = 'https://mock.klaviyo.com/profiles'
        );
        insert camp;

        insert new CampaignMember(CampaignId = camp.Id, ContactId = acc.PersonContactId);

        Test.setMock(HttpCalloutMock.class, new KlaviyoProfileHttpMock());

        Test.startTest();
        KlaviyoCampaignMembersService.Response res = KlaviyoCampaignMembersService.addCampaignMembers(camp.Id);
        Test.stopTest();

        System.assertEquals(204, res.code);
        System.assert(res.message.contains('already campaign members'));
    }

    @isTest
    static void testAddCampaignMembers_NoValidPersonContact() {
        Account acc = new Account(
            Name = 'No Contact',
            Klaviyo_ID__c = 'klaviyo_002' // No person account
        );
        insert acc;

        Campaign camp = new Campaign(
            Name = 'No PersonContact',
            Profile_s_URL__c = 'https://mock.klaviyo.com/profiles'
        );
        insert camp;

        Test.setMock(HttpCalloutMock.class, new KlaviyoProfileHttpMock());

        Test.startTest();
        KlaviyoCampaignMembersService.Response res = KlaviyoCampaignMembersService.addCampaignMembers(camp.Id);
        Test.stopTest();

        System.assertEquals(204, res.code);
        System.assert(res.message.contains('valid PersonContactId'));
    }
    
}