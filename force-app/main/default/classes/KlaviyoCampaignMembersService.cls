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

            response.jobId = System.enqueueJob(new KlaviyoCampaignMembersAsync(campaignId));
            response.code = 202;
            response.message = 'Campaign member import queued.';
        } catch (Exception ex) {
            response.code = 500;
            response.message = 'Exception: ' + ex.getMessage();
            HandleCustomException.LogException(ex, 'KlaviyoCampaignMemberService');
        }
        return response;
    }
    
    public class Response {
         @AuraEnabled public Integer code { get; set; }
         @AuraEnabled public String message { get; set; }
         @AuraEnabled public String jobId { get; set; }
    }
}