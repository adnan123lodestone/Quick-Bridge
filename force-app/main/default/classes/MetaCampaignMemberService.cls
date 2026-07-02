public with sharing class MetaCampaignMemberService {
    public static CampaignMember ensureCampaignMember(
        MetaAttributionService.AttributionResult attribution,
        Id leadId,
        Id socialInteractionId,
        String configuredStatus
    ) {
        if (attribution == null || attribution.campaignId == null || leadId == null) {
            return null;
        }
        List<CampaignMember> existing = [
            SELECT Id, CampaignId, LeadId
            FROM CampaignMember
            WHERE CampaignId = :attribution.campaignId AND LeadId = :leadId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        CampaignMember member = new CampaignMember(
            CampaignId = attribution.campaignId,
            LeadId = leadId,
            Status = String.isBlank(configuredStatus) ? MetaConfigService.defaultCampaignMemberStatus() : configuredStatus,
            Meta_Campaign_Id__c = metaCampaignId(attribution.campaignId),
            Meta_Ad_Set_Id__c = metaAdSetId(attribution.adSetId),
            Meta_Ad_Id__c = metaAdId(attribution.adId),
            Meta_Interaction_Type__c = socialInteractionType(socialInteractionId),
            Social_Interaction__c = socialInteractionId
        );
        insert member;
        return member;
    }

    private static String metaCampaignId(Id campaignId) {
        if (campaignId == null) {
            return null;
        }
        List<Campaign> rows = [
            SELECT Meta_Campaign_Id__c
            FROM Campaign
            WHERE Id = :campaignId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Meta_Campaign_Id__c;
    }

    private static String metaAdSetId(Id adSetId) {
        if (adSetId == null) {
            return null;
        }
        List<Meta_Ad_Set__c> rows = [
            SELECT Meta_Ad_Set_Id__c
            FROM Meta_Ad_Set__c
            WHERE Id = :adSetId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Meta_Ad_Set_Id__c;
    }

    private static String metaAdId(Id adId) {
        if (adId == null) {
            return null;
        }
        List<Meta_Ad__c> rows = [
            SELECT Meta_Ad_Id__c
            FROM Meta_Ad__c
            WHERE Id = :adId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Meta_Ad_Id__c;
    }

    private static String socialInteractionType(Id socialInteractionId) {
        if (socialInteractionId == null) {
            return null;
        }
        List<Social_Interaction__c> rows = [
            SELECT Interaction_Type__c
            FROM Social_Interaction__c
            WHERE Id = :socialInteractionId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Interaction_Type__c;
    }
}