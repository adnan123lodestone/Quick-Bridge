public with sharing class MetaLeadService {
    public static Lead upsertLead(MetaPayloadNormalizer.NormalizedEvent eventRecord, MetaAttributionService.AttributionResult attribution) {
        if (eventRecord == null) {
            throw new MetaLeadException('Meta event is required.');
        }
        Lead leadRecord = findExistingLead(eventRecord);
        Boolean isNew = leadRecord == null;
        if (isNew) {
            leadRecord = new Lead();
        }
        leadRecord.LastName = String.isBlank(eventRecord.lastName)
            ? deriveLastName(eventRecord.commenterName)
            : eventRecord.lastName;
        leadRecord.FirstName = eventRecord.firstName;
        leadRecord.Company = String.isBlank(leadRecord.Company) ? 'Meta Lead' : leadRecord.Company;
        if (String.isNotBlank(eventRecord.email)) {
            leadRecord.Email = eventRecord.email;
        }
        if (String.isNotBlank(eventRecord.phone)) {
            leadRecord.Phone = eventRecord.phone;
        }
        applyLeadSource(leadRecord, MetaConfigService.defaultLeadSource());
        leadRecord.Social_Source__c = eventRecord.interactionType;
        leadRecord.Meta_Campaign_Id__c = eventRecord.campaignId;
        leadRecord.Meta_Ad_Set_Id__c = eventRecord.adSetId;
        leadRecord.Meta_Ad_Id__c = eventRecord.adId;
        leadRecord.Meta_Post_Id__c = eventRecord.postId;
        leadRecord.Meta_Comment_Id__c = eventRecord.commentId;
        leadRecord.Meta_Leadgen_Id__c = eventRecord.leadgenId;
        leadRecord.Primary_Campaign__c = attribution == null ? null : attribution.campaignId;
        leadRecord.Attribution_Status__c = attribution == null ? 'Unattributed' : attribution.status;
        leadRecord.UTM_Source__c = eventRecord.utmSource;
        leadRecord.UTM_Medium__c = eventRecord.utmMedium;
        leadRecord.UTM_Campaign__c = eventRecord.utmCampaign;
        leadRecord.UTM_Content__c = eventRecord.utmContent;
        leadRecord.UTM_Term__c = eventRecord.utmTerm;
        if (isNew) {
            insert leadRecord;
        } else {
            update leadRecord;
        }
        return leadRecord;
    }

    private static Lead findExistingLead(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        List<Lead> rows = new List<Lead>();
        if (String.isNotBlank(eventRecord.leadgenId)) {
            rows = [
                SELECT Id, Company
                FROM Lead
                WHERE Meta_Leadgen_Id__c = :eventRecord.leadgenId
                LIMIT 1
            ];
        }
        if (rows.isEmpty() && String.isNotBlank(eventRecord.email)) {
            rows = [
                SELECT Id, Company
                FROM Lead
                WHERE Email = :eventRecord.email
                LIMIT 1
            ];
        }
        if (rows.isEmpty() && String.isNotBlank(eventRecord.phone)) {
            rows = [
                SELECT Id, Company
                FROM Lead
                WHERE Phone = :eventRecord.phone
                LIMIT 1
            ];
        }
        return rows.isEmpty() ? null : rows[0];
    }

    private static String deriveLastName(String commenterName) {
        if (String.isBlank(commenterName)) {
            return 'Meta Lead';
        }
        List<String> parts = commenterName.trim().split('\\s+');
        return parts.isEmpty() ? 'Meta Lead' : parts[parts.size() - 1];
    }

    private static void applyLeadSource(Lead leadRecord, String configuredLeadSource) {
        if (String.isBlank(configuredLeadSource)) {
            return;
        }
        for (Schema.PicklistEntry entry : Lead.LeadSource.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == configuredLeadSource) {
                leadRecord.LeadSource = configuredLeadSource;
                return;
            }
        }
    }

    public class MetaLeadException extends Exception {}
}