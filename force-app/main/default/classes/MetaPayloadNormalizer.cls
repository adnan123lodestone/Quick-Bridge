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
        public String messageId;
        public String senderProfileId;
        public String recipientPageId;
        public String messageText;
        public Datetime messageTimestamp;
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
                if (!isSupportedWebhookField(objectType, getString(change, 'field'))) {
                    continue;
                }
                NormalizedEvent eventRecord = normalizeChange(objectType, entry, change, value);
                if (eventRecord == null) {
                    continue;
                }
                eventRecord.rawPayload = JSON.serialize(value);
                events.add(eventRecord);
            }
            if (objectType == 'page') {
                for (Object messagingValue : getList(entry, 'messaging')) {
                    if (!(messagingValue instanceof Map<String, Object>)) {
                        continue;
                    }
                    NormalizedEvent eventRecord = normalizeMessagingEvent((Map<String, Object>) messagingValue);
                    if (eventRecord == null) {
                        continue;
                    }
                    eventRecord.rawPayload = JSON.serialize(messagingValue);
                    events.add(eventRecord);
                }
            }
        }
        return events;
    }

    public static Boolean isProcessableEvent(NormalizedEvent eventRecord) {
        if (eventRecord == null) {
            return false;
        }
        if (eventRecord.interactionType == 'Meta Lead Ad') {
            return String.isNotBlank(eventRecord.leadgenId);
        }
        if (eventRecord.interactionType == 'Comment') {
            return String.isNotBlank(eventRecord.commentId);
        }
        if (eventRecord.interactionType == 'Messenger Message') {
            return String.isNotBlank(eventRecord.messageId);
        }
        return false;
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
            return isProcessableEvent(eventRecord) ? eventRecord : null;
        }

        if (!isCommentChange(objectType, fieldName, value)) {
            return null;
        }
        eventRecord.interactionType = 'Comment';
        eventRecord.commentId = getString(value, 'comment_id');
        if (String.isBlank(eventRecord.commentId)) {
            eventRecord.commentId = getString(value, 'id');
        }
        if (String.isBlank(eventRecord.commentId)) {
            return null;
        }
        eventRecord.postId = firstNonBlank(getString(value, 'post_id'), getString(value, 'parent_id'));
        eventRecord.instagramMediaId = getString(value, 'media_id');
        eventRecord.commentText = firstNonBlank(getString(value, 'message'), getString(value, 'text'));
        Map<String, Object> fromValue = getMap(value, 'from');
        eventRecord.commenterProfileId = getString(fromValue, 'id');
        eventRecord.commenterName = firstNonBlank(getString(fromValue, 'name'), getString(fromValue, 'username'));
        return eventRecord;
    }

    private static Boolean isCommentChange(String objectType, String fieldName, Map<String, Object> value) {
        if (objectType == 'instagram') {
            return fieldName == 'comments';
        }
        if (objectType != 'page') {
            return false;
        }
        if (fieldName == 'comments') {
            return true;
        }
        if (fieldName != 'feed') {
            return false;
        }
        return getString(value, 'item') == 'comment' || String.isNotBlank(getString(value, 'comment_id'));
    }

    private static NormalizedEvent normalizeMessagingEvent(Map<String, Object> messagingValue) {
        Map<String, Object> message = getMap(messagingValue, 'message');
        if (message == null || message.containsKey('attachments') || message.containsKey('quick_reply')) {
            return null;
        }
        if (parseBoolean(message.get('is_echo'))) {
            return null;
        }
        String messageId = getString(message, 'mid');
        String text = getString(message, 'text');
        if (String.isBlank(messageId) || String.isBlank(text)) {
            return null;
        }

        NormalizedEvent eventRecord = new NormalizedEvent();
        eventRecord.platform = 'Facebook';
        eventRecord.interactionType = 'Messenger Message';
        eventRecord.messageId = messageId;
        eventRecord.messageText = text;
        eventRecord.commentText = text;
        Map<String, Object> sender = getMap(messagingValue, 'sender');
        Map<String, Object> recipient = getMap(messagingValue, 'recipient');
        eventRecord.senderProfileId = getString(sender, 'id');
        eventRecord.commenterProfileId = eventRecord.senderProfileId;
        eventRecord.recipientPageId = getString(recipient, 'id');
        eventRecord.pageId = eventRecord.recipientPageId;
        eventRecord.messageTimestamp = datetimeFromMillis(messagingValue.get('timestamp'));
        return eventRecord;
    }

    private static Boolean isSupportedWebhookField(String objectType, String fieldName) {
        if (fieldName == 'leadgen') {
            return true;
        }
        if (objectType == 'instagram') {
            return fieldName == 'comments';
        }
        if (objectType == 'page') {
            return fieldName == 'comments' || fieldName == 'feed';
        }
        return false;
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

    private static Boolean parseBoolean(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return String.valueOf(value).equalsIgnoreCase('true');
    }

    private static Datetime datetimeFromMillis(Object value) {
        if (value == null) {
            return null;
        }
        try {
            Decimal milliseconds = Decimal.valueOf(String.valueOf(value));
            Integer seconds = Integer.valueOf(String.valueOf((milliseconds / 1000).setScale(0, System.RoundingMode.DOWN)));
            return Datetime.newInstanceGmt(1970, 1, 1, 0, 0, 0).addSeconds(seconds);
        } catch (Exception ignored) {
            return null;
        }
    }
}