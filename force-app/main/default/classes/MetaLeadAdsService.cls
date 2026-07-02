public with sharing class MetaLeadAdsService {
    private static final String LEAD_FIELDS = 'id,created_time,ad_id,adset_id,campaign_id,form_id,field_data';

    public static void processLeadgenEvent(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        if (eventRecord == null) {
            throw new MetaLeadAdsServiceException('Meta leadgen event is required.');
        }
        if (!MetaConfigService.isEnabled('leadAdsEnabled')) {
            return;
        }
        MetaPayloadNormalizer.NormalizedEvent enriched = enrich(eventRecord);
        MetaLeadAdsProcessor.process(enriched);
    }

    private static MetaPayloadNormalizer.NormalizedEvent enrich(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        if (String.isBlank(eventRecord.leadgenId) || hasUsableLeadFields(eventRecord)) {
            return eventRecord;
        }
        Map<String, Object> detailRow = MetaApiClient.configured().getObject('/' + eventRecord.leadgenId, new Map<String, String>{ 'fields' => LEAD_FIELDS });
        MetaLeadDetail detail = MetaLeadDetail.fromApiRow(detailRow);
        eventRecord.campaignId = firstNonBlank(eventRecord.campaignId, detail.campaignId);
        eventRecord.adSetId = firstNonBlank(eventRecord.adSetId, detail.adSetId);
        eventRecord.adId = firstNonBlank(eventRecord.adId, detail.adId);
        eventRecord.formId = firstNonBlank(eventRecord.formId, detail.formId);
        eventRecord.email = firstNonBlank(eventRecord.email, detail.email);
        eventRecord.phone = firstNonBlank(eventRecord.phone, detail.phone);
        eventRecord.firstName = firstNonBlank(eventRecord.firstName, detail.firstName);
        eventRecord.lastName = firstNonBlank(eventRecord.lastName, detail.lastName);
        eventRecord.commenterName = firstNonBlank(eventRecord.commenterName, detail.fullName);
        eventRecord.rawPayload = firstNonBlank(detail.rawPayload, eventRecord.rawPayload);
        return eventRecord;
    }

    private static Boolean hasUsableLeadFields(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
        return eventRecord != null && (
            String.isNotBlank(eventRecord.email) ||
            String.isNotBlank(eventRecord.phone) ||
            String.isNotBlank(eventRecord.lastName) ||
            String.isNotBlank(eventRecord.commenterName)
        );
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isBlank(firstValue) ? secondValue : firstValue;
    }

    public class MetaLeadAdsServiceException extends Exception {}
}