public with sharing class MetaLeadAdsProcessor {
    public static void process(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        if (eventRecord == null) {
            throw new MetaLeadAdsProcessorException('Meta lead ad event is required.');
        }
        MetaAttributionService.AttributionResult attribution = MetaAttributionService.resolve(eventRecord);
        Lead leadRecord = MetaLeadService.upsertLead(eventRecord, attribution);
        Social_Interaction__c interactionRecord = MetaSocialInteractionService.upsertInteraction(eventRecord, attribution, leadRecord.Id);
        if (MetaConfigService.isEnabled('autoCreateCampaignMember') || String.isBlank(MetaConfigService.getValue('autoCreateCampaignMember'))) {
            MetaCampaignMemberService.ensureCampaignMember(attribution, leadRecord.Id, interactionRecord.Id, MetaConfigService.defaultCampaignMemberStatus());
        }
    }

    public class MetaLeadAdsProcessorException extends Exception {}
}