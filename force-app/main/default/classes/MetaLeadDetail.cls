public class MetaLeadDetail {
    public String id;
    public String campaignId;
    public String adSetId;
    public String adId;
    public String formId;
    public String email;
    public String phone;
    public String firstName;
    public String lastName;
    public String fullName;
    public String rawPayload;

    public static MetaLeadDetail fromApiRow(Map<String, Object> row) {
        MetaLeadDetail detail = new MetaLeadDetail();
        if (row == null) {
            return detail;
        }
        detail.id = stringValue(row.get('id'));
        detail.campaignId = stringValue(row.get('campaign_id'));
        detail.adSetId = firstNonBlank(stringValue(row.get('adset_id')), stringValue(row.get('adgroup_id')));
        detail.adId = stringValue(row.get('ad_id'));
        detail.formId = stringValue(row.get('form_id'));
        detail.rawPayload = JSON.serialize(row);
        if (row.get('field_data') instanceof List<Object>) {
            for (Object fieldValue : (List<Object>) row.get('field_data')) {
                if (!(fieldValue instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> field = (Map<String, Object>) fieldValue;
                String name = stringValue(field.get('name'));
                String value = firstValue(field.get('values'));
                if (String.isBlank(name) || String.isBlank(value)) {
                    continue;
                }
                String normalized = name.toLowerCase();
                if (normalized == 'email') {
                    detail.email = value;
                } else if (normalized == 'phone' || normalized == 'phone_number') {
                    detail.phone = value;
                } else if (normalized == 'first_name' || normalized == 'firstname') {
                    detail.firstName = value;
                } else if (normalized == 'last_name' || normalized == 'lastname') {
                    detail.lastName = value;
                } else if (normalized == 'full_name' || normalized == 'name') {
                    detail.fullName = value;
                }
            }
        }
        if (String.isBlank(detail.lastName) && String.isNotBlank(detail.fullName)) {
            List<String> parts = detail.fullName.trim().split('\\s+');
            if (parts.size() > 1) {
                detail.firstName = String.isBlank(detail.firstName) ? parts[0] : detail.firstName;
                detail.lastName = parts[parts.size() - 1];
            } else {
                detail.lastName = detail.fullName;
            }
        }
        return detail;
    }

    private static String firstValue(Object values) {
        if (values instanceof List<Object>) {
            List<Object> rows = (List<Object>) values;
            return rows.isEmpty() ? null : stringValue(rows[0]);
        }
        return stringValue(values);
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isBlank(firstValue) ? secondValue : firstValue;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}