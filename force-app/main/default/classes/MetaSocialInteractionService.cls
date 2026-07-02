public with sharing class MetaSocialInteractionService {
    public static Social_Interaction__c upsertInteraction(
        MetaPayloadNormalizer.NormalizedEvent eventRecord,
        MetaAttributionService.AttributionResult attribution,
        Id leadId
    ) {
        if (eventRecord == null) {
            throw new MetaSocialInteractionException('Meta event is required.');
        }
        String externalKey = interactionExternalKey(eventRecord);
        List<Social_Interaction__c> existing = String.isBlank(externalKey)
            ? new List<Social_Interaction__c>()
            : [
                SELECT Id
                FROM Social_Interaction__c
                WHERE External_Key__c = :externalKey
                LIMIT 1
            ];
        Social_Interaction__c row = existing.isEmpty() ? new Social_Interaction__c() : existing[0];
        row.Name = String.isBlank(eventRecord.commentId)
            ? (String.isBlank(eventRecord.leadgenId) ? 'Meta Interaction' : eventRecord.leadgenId)
            : eventRecord.commentId;
        row.External_Key__c = externalKey;
        row.Platform__c = eventRecord.platform;
        row.Interaction_Type__c = eventRecord.interactionType;
        row.Meta_Campaign_Id__c = eventRecord.campaignId;
        row.Meta_Ad_Set_Id__c = eventRecord.adSetId;
        row.Meta_Ad_Id__c = eventRecord.adId;
        row.Meta_Post_Id__c = eventRecord.postId;
        row.Instagram_Media_Id__c = eventRecord.instagramMediaId;
        row.Meta_Comment_Id__c = eventRecord.commentId;
        row.Meta_Leadgen_Id__c = eventRecord.leadgenId;
        row.Comment_Text__c = eventRecord.commentText;
        row.Commenter_Name__c = eventRecord.commenterName;
        row.Commenter_Profile_Id__c = eventRecord.commenterProfileId;
        row.Lead__c = leadId;
        row.Campaign__c = attribution == null ? null : attribution.campaignId;
        row.Meta_Ad_Set__c = attribution == null ? null : attribution.adSetId;
        row.Meta_Ad__c = attribution == null ? null : attribution.adId;
        row.Processing_Status__c = 'Processed';
        row.Attribution_Status__c = attribution == null ? 'Unattributed' : attribution.status;
        row.Raw_Payload__c = eventRecord.rawPayload;
        upsert row External_Key__c;
        return row;
    }

    public static String interactionExternalKey(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        if (eventRecord == null) {
            return null;
        }
        if (String.isNotBlank(eventRecord.leadgenId)) {
            return safePart(eventRecord.platform) + '|leadgen|' + eventRecord.leadgenId;
        }
        if (String.isNotBlank(eventRecord.commentId)) {
            return safePart(eventRecord.platform) + '|comment|' + eventRecord.commentId;
        }
        return null;
    }

    private static String safePart(String value) {
        return String.isBlank(value) ? 'Meta' : value.trim();
    }

    public class MetaSocialInteractionException extends Exception {}
}