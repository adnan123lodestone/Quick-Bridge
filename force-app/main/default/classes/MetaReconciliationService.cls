public with sharing class MetaReconciliationService {
    private static final Set<String> REPAIRABLE_STATUSES = new Set<String>{ 'Unattributed', 'Needs Review', 'Failed' };

    public static Integer reconcile() {
        Integer repaired = reconcileInteractions();
        repaired += reconcileLeadsWithoutInteractions();
        return repaired;
    }

    private static Integer reconcileInteractions() {
        List<Social_Interaction__c> interactions = [
            SELECT Id, Lead__c, Campaign__c, Meta_Ad_Set__c, Meta_Ad__c, Attribution_Status__c,
                Platform__c, Interaction_Type__c, Meta_Campaign_Id__c, Meta_Ad_Set_Id__c,
                Meta_Ad_Id__c, Meta_Post_Id__c, Instagram_Media_Id__c, Meta_Comment_Id__c,
                Meta_Leadgen_Id__c, Comment_Text__c, Commenter_Name__c, Commenter_Profile_Id__c
            FROM Social_Interaction__c
            WHERE Attribution_Status__c IN :REPAIRABLE_STATUSES
            LIMIT 200
        ];
        if (interactions.isEmpty()) {
            return 0;
        }

        Map<Id, Lead> leadsById = new Map<Id, Lead>();
        Set<Id> leadIds = new Set<Id>();
        for (Social_Interaction__c interaction : interactions) {
            if (interaction.Lead__c != null) {
                leadIds.add(interaction.Lead__c);
            }
        }
        if (!leadIds.isEmpty()) {
            leadsById = new Map<Id, Lead>([
                SELECT Id, Primary_Campaign__c, Attribution_Status__c, Meta_Campaign_Id__c,
                    Meta_Ad_Set_Id__c, Meta_Ad_Id__c, Meta_Post_Id__c, Meta_Comment_Id__c,
                    Meta_Leadgen_Id__c, Social_Source__c
                FROM Lead
                WHERE Id IN :leadIds
            ]);
        }

        List<Social_Interaction__c> interactionUpdates = new List<Social_Interaction__c>();
        List<Lead> leadUpdates = new List<Lead>();
        Integer repaired = 0;
        for (Social_Interaction__c interaction : interactions) {
            MetaPayloadNormalizer.NormalizedEvent eventRecord = eventFromInteraction(interaction);
            MetaAttributionService.AttributionResult attribution = MetaAttributionService.resolve(eventRecord);
            if (attribution == null || attribution.status != 'Attributed') {
                continue;
            }
            interaction.Campaign__c = attribution.campaignId;
            interaction.Meta_Ad_Set__c = attribution.adSetId;
            interaction.Meta_Ad__c = attribution.adId;
            interaction.Attribution_Status__c = attribution.status;
            interactionUpdates.add(interaction);

            Lead leadRecord = leadsById.get(interaction.Lead__c);
            if (leadRecord != null) {
                leadRecord.Primary_Campaign__c = attribution.campaignId;
                leadRecord.Attribution_Status__c = attribution.status;
                leadUpdates.add(leadRecord);
                MetaCampaignMemberService.ensureCampaignMember(
                    attribution,
                    leadRecord.Id,
                    interaction.Id,
                    MetaConfigService.defaultCampaignMemberStatus()
                );
            }
            repaired++;
        }
        if (!interactionUpdates.isEmpty()) {
            Database.update(interactionUpdates, false);
        }
        if (!leadUpdates.isEmpty()) {
            Database.update(leadUpdates, false);
        }
        return repaired;
    }

    private static Integer reconcileLeadsWithoutInteractions() {
        List<Lead> leads = [
            SELECT Id, Primary_Campaign__c, Attribution_Status__c, Meta_Campaign_Id__c,
                Meta_Ad_Set_Id__c, Meta_Ad_Id__c, Meta_Post_Id__c, Meta_Comment_Id__c,
                Meta_Leadgen_Id__c, Social_Source__c
            FROM Lead
            WHERE Attribution_Status__c IN :REPAIRABLE_STATUSES
            LIMIT 200
        ];
        List<Lead> updates = new List<Lead>();
        Integer repaired = 0;
        for (Lead leadRecord : leads) {
            MetaPayloadNormalizer.NormalizedEvent eventRecord = eventFromLead(leadRecord);
            MetaAttributionService.AttributionResult attribution = MetaAttributionService.resolve(eventRecord);
            if (attribution == null || attribution.status != 'Attributed') {
                continue;
            }
            leadRecord.Primary_Campaign__c = attribution.campaignId;
            leadRecord.Attribution_Status__c = attribution.status;
            updates.add(leadRecord);
            MetaCampaignMemberService.ensureCampaignMember(
                attribution,
                leadRecord.Id,
                null,
                MetaConfigService.defaultCampaignMemberStatus()
            );
            repaired++;
        }
        if (!updates.isEmpty()) {
            Database.update(updates, false);
        }
        return repaired;
    }

    private static MetaPayloadNormalizer.NormalizedEvent eventFromInteraction(Social_Interaction__c interaction) {
        MetaPayloadNormalizer.NormalizedEvent eventRecord = new MetaPayloadNormalizer.NormalizedEvent();
        eventRecord.platform = interaction.Platform__c;
        eventRecord.interactionType = interaction.Interaction_Type__c;
        eventRecord.campaignId = interaction.Meta_Campaign_Id__c;
        eventRecord.adSetId = interaction.Meta_Ad_Set_Id__c;
        eventRecord.adId = interaction.Meta_Ad_Id__c;
        eventRecord.postId = interaction.Meta_Post_Id__c;
        eventRecord.instagramMediaId = interaction.Instagram_Media_Id__c;
        eventRecord.commentId = interaction.Meta_Comment_Id__c;
        eventRecord.leadgenId = interaction.Meta_Leadgen_Id__c;
        eventRecord.commentText = interaction.Comment_Text__c;
        eventRecord.commenterName = interaction.Commenter_Name__c;
        eventRecord.commenterProfileId = interaction.Commenter_Profile_Id__c;
        return eventRecord;
    }

    private static MetaPayloadNormalizer.NormalizedEvent eventFromLead(Lead leadRecord) {
        MetaPayloadNormalizer.NormalizedEvent eventRecord = new MetaPayloadNormalizer.NormalizedEvent();
        eventRecord.platform = 'Meta';
        eventRecord.interactionType = leadRecord.Social_Source__c;
        eventRecord.campaignId = leadRecord.Meta_Campaign_Id__c;
        eventRecord.adSetId = leadRecord.Meta_Ad_Set_Id__c;
        eventRecord.adId = leadRecord.Meta_Ad_Id__c;
        eventRecord.postId = leadRecord.Meta_Post_Id__c;
        eventRecord.commentId = leadRecord.Meta_Comment_Id__c;
        eventRecord.leadgenId = leadRecord.Meta_Leadgen_Id__c;
        return eventRecord;
    }
}