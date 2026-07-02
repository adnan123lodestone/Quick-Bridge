public with sharing class MetaAttributionService {
    public class AttributionResult {
        public Id campaignId;
        public Id adSetId;
        public Id adId;
        public String status;
        public String reason;
    }

    public static AttributionResult resolve(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        AttributionResult result = new AttributionResult();
        result.status = 'Unattributed';
        result.reason = 'No matching Meta campaign, ad set, or ad was found.';
        if (eventRecord == null) {
            return result;
        }

        Meta_Ad__c adRecord = findAd(eventRecord);
        if (adRecord != null) {
            result.adId = adRecord.Id;
            result.adSetId = adRecord.Meta_Ad_Set__c;
            result.campaignId = adRecord.Campaign__c;
            result.status = result.campaignId == null ? 'Needs Review' : 'Attributed';
            result.reason = 'Matched Meta ad.';
            return result;
        }

        Meta_Ad_Set__c adSetRecord = findAdSet(eventRecord);
        if (adSetRecord != null) {
            result.adSetId = adSetRecord.Id;
            result.campaignId = adSetRecord.Campaign__c;
            result.status = result.campaignId == null ? 'Needs Review' : 'Attributed';
            result.reason = 'Matched Meta ad set.';
            return result;
        }

        Campaign campaignRecord = findCampaign(eventRecord);
        if (campaignRecord != null) {
            result.campaignId = campaignRecord.Id;
            result.status = 'Attributed';
            result.reason = 'Matched Meta campaign.';
            return result;
        }
        result.status = 'Needs Review';
        return result;
    }

    private static Meta_Ad__c findAd(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        List<Meta_Ad__c> rows = new List<Meta_Ad__c>();
        if (String.isNotBlank(eventRecord.adId)) {
            rows = [
                SELECT Id, Meta_Ad_Set__c, Campaign__c
                FROM Meta_Ad__c
                WHERE Meta_Ad_Id__c = :eventRecord.adId
                LIMIT 1
            ];
        }
        if (rows.isEmpty() && String.isNotBlank(eventRecord.postId)) {
            rows = [
                SELECT Id, Meta_Ad_Set__c, Campaign__c
                FROM Meta_Ad__c
                WHERE Post_Id__c = :eventRecord.postId
                LIMIT 1
            ];
        }
        if (rows.isEmpty() && String.isNotBlank(eventRecord.instagramMediaId)) {
            rows = [
                SELECT Id, Meta_Ad_Set__c, Campaign__c
                FROM Meta_Ad__c
                WHERE Instagram_Media_Id__c = :eventRecord.instagramMediaId
                LIMIT 1
            ];
        }
        return rows.isEmpty() ? null : rows[0];
    }

    private static Meta_Ad_Set__c findAdSet(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        if (String.isBlank(eventRecord.adSetId)) {
            return null;
        }
        List<Meta_Ad_Set__c> rows = [
            SELECT Id, Campaign__c
            FROM Meta_Ad_Set__c
            WHERE Meta_Ad_Set_Id__c = :eventRecord.adSetId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Campaign findCampaign(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        if (String.isBlank(eventRecord.campaignId)) {
            return null;
        }
        List<Campaign> rows = [
            SELECT Id
            FROM Campaign
            WHERE Meta_Campaign_Id__c = :eventRecord.campaignId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
}