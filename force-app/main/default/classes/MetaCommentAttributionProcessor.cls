public with sharing class MetaCommentAttributionProcessor {
    public static void process(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        if (eventRecord == null) {
            throw new MetaCommentAttributionProcessorException('Meta comment event is required.');
        }
        MetaAttributionService.AttributionResult attribution = MetaAttributionService.resolve(eventRecord);
        Boolean shouldCreateLead = shouldCreateLeadForComment(eventRecord);
        Lead leadRecord;
        if (shouldCreateLead) {
            leadRecord = MetaLeadService.upsertLead(eventRecord, attribution);
        }
        Social_Interaction__c interactionRecord = MetaSocialInteractionService.upsertInteraction(
            eventRecord,
            attribution,
            leadRecord == null ? null : leadRecord.Id
        );
        if (leadRecord != null && (MetaConfigService.isEnabled('autoCreateCampaignMember') || String.isBlank(MetaConfigService.getValue('autoCreateCampaignMember')))) {
            MetaCampaignMemberService.ensureCampaignMember(attribution, leadRecord.Id, interactionRecord.Id, MetaConfigService.defaultCampaignMemberStatus());
        }
    }

    private static Boolean shouldCreateLeadForComment(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        String mode = MetaConfigService.getValue('leadCreationMode');
        if (String.isBlank(mode) || mode == 'Always') {
            return true;
        }
        if (mode == 'Manual Review') {
            return false;
        }
        if (mode != 'Keyword Match') {
            return false;
        }
        String rules = MetaConfigService.getValue('keywordRulesJson');
        if (String.isBlank(rules) || String.isBlank(eventRecord.commentText)) {
            return false;
        }
        String lowerText = eventRecord.commentText.toLowerCase();
        for (String token : rules.replace('[', '').replace(']', '').replace('"', '').split(',')) {
            if (String.isNotBlank(token) && lowerText.contains(token.trim().toLowerCase())) {
                return true;
            }
        }
        return false;
    }

    public class MetaCommentAttributionProcessorException extends Exception {}
}