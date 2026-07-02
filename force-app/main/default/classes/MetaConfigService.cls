public with sharing class MetaConfigService {
    public static final String CONNECTOR_KEY = 'meta';
    public static final String INTEGRATION_NAME = 'Meta';
    public static final String DEFAULT_GRAPH_API_VERSION = 'v21.0';

    public static Boolean isActive() {
        try {
            return ConnectorConfigService.isActive(CONNECTOR_KEY);
        } catch (Exception e) {
            return false;
        }
    }

    public static Boolean isEnabled(String fieldKey) {
        String value = getValue(fieldKey);
        if (String.isBlank(value)) {
            return false;
        }
        return value.equalsIgnoreCase('true') || value.equalsIgnoreCase('yes') || value == '1';
    }

    public static String getValue(String fieldKey) {
        if (String.isBlank(fieldKey)) {
            return null;
        }
        return ConnectorConfigService.getConfigValue(CONNECTOR_KEY, fieldKey);
    }

    public static String namedCredential() {
        try {
            ConnectorConfigService.ConnectorConfig config = ConnectorConfigService.getConfig(CONNECTOR_KEY);
            if (config != null && String.isNotBlank(config.namedCredential)) {
                return config.namedCredential;
            }
        } catch (Exception e) {
            return null;
        }
        return null;
    }

    public static String graphApiVersion() {
        String configured = getValue('graphApiVersion');
        return String.isBlank(configured) ? DEFAULT_GRAPH_API_VERSION : configured.trim();
    }

    public static String adAccountId() {
        return getValue('adAccountId');
    }

    public static String pageId() {
        return getValue('pageId');
    }

    public static String instagramBusinessAccountId() {
        return getValue('instagramBusinessAccountId');
    }

    public static String defaultLeadSource() {
        String configured = getValue('defaultLeadSource');
        return String.isBlank(configured) ? 'Meta Lead Ad' : configured;
    }

    public static String defaultCampaignMemberStatus() {
        String configured = getValue('defaultCampaignMemberStatus');
        return String.isBlank(configured) ? 'Responded' : configured;
    }

    public static Integer attributionWindowDays() {
        String configured = getValue('attributionWindowDays');
        if (String.isBlank(configured)) {
            return 30;
        }
        try {
            Integer parsed = Integer.valueOf(configured);
            return parsed <= 0 ? 30 : parsed;
        } catch (Exception e) {
            return 30;
        }
    }

    public static void requireConfiguredForWebhook() {
        if (String.isBlank(getValue('webhookVerifyTokenRef'))) {
            throw new MetaConfigException('Meta webhook verify token is not configured.');
        }
        if (String.isBlank(getValue('appSecretRef'))) {
            throw new MetaConfigException('Meta app secret reference is not configured.');
        }
    }

    public static void requireConfiguredForApiSync() {
        if (!isActive()) {
            throw new MetaConfigException('Meta connector is inactive.');
        }
        if (String.isBlank(namedCredential())) {
            throw new MetaConfigException('Meta named credential is not configured.');
        }
        if (String.isBlank(getValue('accessTokenRef'))) {
            throw new MetaConfigException('Meta access token reference is not configured.');
        }
        if (String.isBlank(adAccountId())) {
            throw new MetaConfigException('Meta ad account ID is not configured.');
        }
    }

    public class MetaConfigException extends Exception {}
}