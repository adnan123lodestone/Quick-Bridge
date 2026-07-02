public with sharing class MetaPayloadNormalizer {
    public class NormalizedEvent {
        public String platform;
        public String interactionType;
        public String pageId;
        public String instagramBusinessAccountId;
        public String postId;
        public String instagramMediaId;
        public String commentId;
        public String leadgenId;
        public String formId;
        public String adId;
        public String adSetId;
        public String campaignId;
        public String commenterName;
        public String commenterProfileId;
        public String commentText;
        public String email;
        public String phone;
        public String firstName;
        public String lastName;
        public String utmSource;
        public String utmMedium;
        public String utmCampaign;
        public String utmContent;
        public String utmTerm;
        public String rawPayload;
    }

    public static NormalizedEvent firstEvent(String payloadJson) {
        List<NormalizedEvent> events = fromWebhookPayload(payloadJson);
        return events.isEmpty() ? null : events[0];
    }

    public static NormalizedEvent fromJson(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            return null;
        }
        return (NormalizedEvent) JSON.deserialize(payloadJson, NormalizedEvent.class);
    }

    public static List<NormalizedEvent> fromWebhookPayload(String payloadJson) {
        List<NormalizedEvent> events = new List<NormalizedEvent>();
        if (String.isBlank(payloadJson)) {
            return events;
        }
        Object parsed = JSON.deserializeUntyped(payloadJson);
        if (!(parsed instanceof Map<String, Object>)) {
            return events;
        }
        Map<String, Object> root = (Map<String, Object>) parsed;
        String objectType = getString(root, 'object');
        List<Object> entries = getList(root, 'entry');
        for (Object entryValue : entries) {
            if (!(entryValue instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> entry = (Map<String, Object>) entryValue;
            for (Object changeValue : getList(entry, 'changes')) {
                if (!(changeValue instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> change = (Map<String, Object>) changeValue;
                Map<String, Object> value = getMap(change, 'value');
                if (value == null) {
                    continue;
                }
                NormalizedEvent eventRecord = normalizeChange(objectType, entry, change, value);
                eventRecord.rawPayload = JSON.serialize(value);
                events.add(eventRecord);
            }
        }
        return events;
    }

    private static NormalizedEvent normalizeChange(String objectType, Map<String, Object> entry, Map<String, Object> change, Map<String, Object> value) {
        NormalizedEvent eventRecord = new NormalizedEvent();
        String fieldName = getString(change, 'field');
        eventRecord.platform = objectType == 'instagram' ? 'Instagram' : (objectType == 'page' ? 'Facebook' : 'Meta');
        eventRecord.pageId = firstNonBlank(getString(value, 'page_id'), getString(entry, 'id'));

        if (fieldName == 'leadgen') {
            eventRecord.platform = 'Meta';
            eventRecord.interactionType = 'Meta Lead Ad';
            eventRecord.leadgenId = getString(value, 'leadgen_id');
            eventRecord.formId = getString(value, 'form_id');
            eventRecord.adId = getString(value, 'ad_id');
            eventRecord.adSetId = firstNonBlank(getString(value, 'adset_id'), getString(value, 'adgroup_id'));
            eventRecord.campaignId = getString(value, 'campaign_id');
            eventRecord.email = getString(value, 'email');
            eventRecord.phone = firstNonBlank(getString(value, 'phone'), getString(value, 'phone_number'));
            eventRecord.firstName = getString(value, 'first_name');
            eventRecord.lastName = getString(value, 'last_name');
            eventRecord.commenterName = firstNonBlank(getString(value, 'full_name'), getString(value, 'name'));
            return eventRecord;
        }

        eventRecord.interactionType = 'Comment';
        eventRecord.commentId = getString(value, 'comment_id');
        if (String.isBlank(eventRecord.commentId)) {
            eventRecord.commentId = getString(value, 'id');
        }
        eventRecord.postId = firstNonBlank(getString(value, 'post_id'), getString(value, 'parent_id'));
        eventRecord.instagramMediaId = getString(value, 'media_id');
        eventRecord.commentText = firstNonBlank(getString(value, 'message'), getString(value, 'text'));
        Map<String, Object> fromValue = getMap(value, 'from');
        eventRecord.commenterProfileId = getString(fromValue, 'id');
        eventRecord.commenterName = firstNonBlank(getString(fromValue, 'name'), getString(fromValue, 'username'));
        return eventRecord;
    }

    private static Map<String, Object> getMap(Map<String, Object> source, String key) {
        if (source == null || !source.containsKey(key) || !(source.get(key) instanceof Map<String, Object>)) {
            return null;
        }
        return (Map<String, Object>) source.get(key);
    }

    private static List<Object> getList(Map<String, Object> source, String key) {
        if (source == null || !source.containsKey(key) || !(source.get(key) instanceof List<Object>)) {
            return new List<Object>();
        }
        return (List<Object>) source.get(key);
    }

    private static String getString(Map<String, Object> source, String key) {
        if (source == null || String.isBlank(key) || !source.containsKey(key) || source.get(key) == null) {
            return null;
        }
        return String.valueOf(source.get(key));
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isBlank(firstValue) ? secondValue : firstValue;
    }
}