global class KlaviyoCampaignMembersBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    private Id campaignId;
    private String endpoint;
    private String accessToken;
    private String nextUrl;

    public KlaviyoCampaignMembersBatch(Id campaignId) {
        this.campaignId = campaignId;
        Integration__mdt klaviyoCredential = getAccessToken();
        this.accessToken = klaviyoCredential.Access_Token__c;
        
        Campaign camp = [
            SELECT Id, Profile_s_URL__c
            FROM Campaign
            WHERE Id = :campaignId
            LIMIT 1
        ];
        this.endpoint = camp.Profile_s_URL__c;
    }

    public KlaviyoCampaignMembersBatch(Id campaignId, String nextUrl) {
        this.campaignId = campaignId;
        this.nextUrl = nextUrl;
        Integration__mdt klaviyoCredential = getAccessToken();
        this.accessToken = klaviyoCredential.Access_Token__c;
    }

    global Iterable<SObject> start(Database.BatchableContext BC) {
        return new List<SObject>{ new Campaign(Id = campaignId) };
    }

    global void execute(Database.BatchableContext BC, List<SObject> scope) {
        try {
            Http http = new Http();
            String workingEndpoint = (String.isNotBlank(this.nextUrl)) ? this.nextUrl : this.endpoint;
            
            if (String.isBlank(workingEndpoint)) {
                System.debug('No endpoint to process.');
                return;
            }
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(workingEndpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Klaviyo-API-Key ' + accessToken);
            req.setHeader('revision', '2025-01-15');

            HttpResponse httpRes = http.send(req);
            if (httpRes.getStatusCode() == 200) {
                Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());
                List<Object> dataList = (List<Object>) jsonResponse.get('data');

                Set<String> profileIds = new Set<String>();

                if (dataList != null) {
                    for (Object o : dataList) {
                        Map<String, Object> profile = (Map<String, Object>) o;
                        String profileId = (String) profile.get('id');
                        if (String.isNotBlank(profileId)) {
                            profileIds.add(profileId);
                        }
                    }
                }

                if (!profileIds.isEmpty()) {
                    createCampaignMembers(profileIds);
                }

                Map<String, Object> links = (Map<String, Object>) jsonResponse.get('links');
                if (links != null && links.containsKey('next')) {
                    String nextLink = (String) links.get('next');
                    this.nextUrl = String.isNotBlank(nextLink) ? nextLink : null;
                } else {
                    this.nextUrl = null;
                }

            } else {
                System.debug('HTTP callout failed with status code: ' + httpRes.getStatusCode());
                this.nextUrl = null;
            }
        } catch (Exception ex) {
            HandleCustomException.LogException(ex, 'KlaviyoCampaignMembersBatch');
        }
    }

    global void finish(Database.BatchableContext BC) {
        if (String.isNotBlank(this.nextUrl)) {
            // ➡️ Continue fetching next page immediately with a fresh batch
            Database.executeBatch(new KlaviyoCampaignMembersBatch(this.campaignId, this.nextUrl), 1);
        } else {
            System.debug('All pages processed successfully.');
        }
    }

    private void createCampaignMembers(Set<String> profileIds) {
        try {
            List<Account> accList = [
                SELECT Id, Klaviyo_ID__c, PersonContactId 
                FROM Account
                WHERE Klaviyo_ID__c IN :profileIds
            ];

            List<CampaignMember> membersToInsert = new List<CampaignMember>();
            for (Account acc : accList) {
                if (acc.PersonContactId != null) {
                    CampaignMember cm = new CampaignMember();
                    cm.CampaignId = campaignId;
                    cm.ContactId = acc.PersonContactId;
                    membersToInsert.add(cm);
                }
            }

            if (!membersToInsert.isEmpty()) {
                Set<Id> contactIds = new Set<Id>();
                for (CampaignMember cm : membersToInsert) {
                    contactIds.add(cm.ContactId);
                }

                List<CampaignMember> existingMembers = [
                    SELECT ContactId
                    FROM CampaignMember
                    WHERE CampaignId = :campaignId AND ContactId IN :contactIds
                ];

                Set<Id> existingContactIds = new Set<Id>();
                for (CampaignMember cm : existingMembers) {
                    existingContactIds.add(cm.ContactId);
                }

                List<CampaignMember> newMembersToInsert = new List<CampaignMember>();
                for (CampaignMember cm : membersToInsert) {
                    if (!existingContactIds.contains(cm.ContactId)) {
                        newMembersToInsert.add(cm);
                    }
                }

                if (!newMembersToInsert.isEmpty()) {
                    insert newMembersToInsert;
                    System.debug('Inserted ' + newMembersToInsert.size() + ' new CampaignMembers.');
                } else {
                    System.debug('All contacts were already campaign members.');
                }
            } else {
                System.debug('No matching Accounts with PersonContactId.');
            }
        } catch (Exception ex) {
            HandleCustomException.LogException(ex, 'KlaviyoCampaignMembersBatch_createCampaignMembers');
        }
    }

    private static Integration__mdt getAccessToken() {
        return [SELECT Access_Token__c, URL__c FROM Integration__mdt WHERE MasterLabel = 'Klaviyo' LIMIT 1];
    }
}