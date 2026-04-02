public class KlaviyoCampaignMembersService {
    @AuraEnabled
    public static Response addCampaignMembers(Id campaignId) {
        Response response = new Response();
        try {
            // Query the campaign to retrieve its Profile_s_URL__c field.
            Campaign camp = [
                SELECT Id, Profile_s_URL__c 
                FROM Campaign
                WHERE Id = :campaignId 
                LIMIT 1
            ];
            
            if (String.isBlank(camp.Profile_s_URL__c)) {
                response.code = 400;
                response.message = 'Campaign does not have a Profile_s_URL__c value.';
                return response;
            }
            
            // Initialize endpoint and a set to accumulate profile IDs.
            String endpoint = camp.Profile_s_URL__c;
            Integration__mdt klaviyoCredential = getAccessToken();
            String accessToken = klaviyoCredential.Access_Token__c;
            Set<String> profileIds = new Set<String>();
            Http http = new Http();
            
            // Loop through pages while endpoint is not null.
            while (endpoint != null) {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(endpoint);
                req.setMethod('GET');
                req.setHeader('Authorization', 'Klaviyo-API-Key ' + accessToken);
                req.setHeader('revision', '2025-01-15');
                
                HttpResponse httpRes = http.send(req);
                if (httpRes.getStatusCode() == 200) {
                    Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());
                    List<Object> dataList = (List<Object>) jsonResponse.get('data');
                    
                    // Accumulate profile IDs from this page.
                    if (dataList != null) {
                        for (Object o : dataList) {
                            Map<String, Object> profile = (Map<String, Object>) o;
                            String profileId = (String) profile.get('id');
                            if (!String.isBlank(profileId)) {
                                profileIds.add(profileId);
                            }
                        }
                    }
                    
                    // Check for the "next" link to determine if another page exists.
                    Map<String, Object> links = (Map<String, Object>) jsonResponse.get('links');
                    if (links != null && links.containsKey('next')) {
                        String nextUrl = (String) links.get('next');
                        endpoint = String.isNotBlank(nextUrl) ? nextUrl : null;
                    } else {
                        endpoint = null;
                    }
                } else {
                    System.debug('HTTP callout failed. Status Code: ' + httpRes.getStatusCode());
                    endpoint = null;
                }
            } // End while loop
            
            if (profileIds.isEmpty()) {
                response.code = 204;
                response.message = 'No profile IDs found in the response.';
                return response;
            }
            
            // Query Accounts whose Klaviyo_ID__c is in the collected set.
            List<Account> accList = [
                SELECT Id, Klaviyo_ID__c, PersonContactId 
                FROM Account 
                WHERE Klaviyo_ID__c IN :profileIds
            ];
            
            // Prepare the list of CampaignMember records to insert.
            List<CampaignMember> membersToInsert = new List<CampaignMember>();
            for (Account a : accList) {
                // Only add if the account has a valid PersonContactId.
                if (a.PersonContactId != null) {
                    CampaignMember cm = new CampaignMember();
                    cm.CampaignId = campaignId;
                    cm.ContactId = a.PersonContactId;
                    membersToInsert.add(cm);
                }
            }
            
            // Remove duplicates by querying existing CampaignMember records for this campaign.
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
                
                // Filter out members that already exist.
                List<CampaignMember> newMembersToInsert = new List<CampaignMember>();
                for (CampaignMember cm : membersToInsert) {
                    if (!existingContactIds.contains(cm.ContactId)) {
                        newMembersToInsert.add(cm);
                    }
                }
                
                if (!newMembersToInsert.isEmpty()) {
                    insert newMembersToInsert;
                    response.code = 200;
                    response.message = 'Inserted ' + newMembersToInsert.size() + ' campaign members.';
                } else {
                    response.code = 204;
                    response.message = 'All matching accounts are already campaign members.';
                }
            } else {
                response.code = 204;
                response.message = 'No matching accounts found with a valid PersonContactId.';
            }
        } catch (Exception ex) {
            response.code = 500;
            response.message = 'Exception: ' + ex.getMessage();
            HandleCustomException.LogException(ex, 'KlaviyoCampaignMemberService');
        }
        return response;
    }
    
    private static Integration__mdt getAccessToken() {
        return [SELECT Access_Token__c, URL__c FROM Integration__mdt WHERE MasterLabel = 'Klaviyo' LIMIT 1];
    }
    
    public class Response {
         @AuraEnabled public Integer code { get; set; }
         @AuraEnabled public String message { get; set; }
    }
}