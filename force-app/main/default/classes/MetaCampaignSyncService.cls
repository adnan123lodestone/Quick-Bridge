public with sharing class MetaCampaignSyncService {
    private static final String CAMPAIGN_FIELDS = 'id,name,account_id,objective,status,effective_status,daily_budget,lifetime_budget';
    private static final String AD_SET_FIELDS = 'id,name,campaign_id,status,effective_status,optimization_goal,daily_budget,lifetime_budget';
    private static final String AD_FIELDS = 'id,name,campaign_id,adset_id,status,effective_status,creative,preview_shareable_link';

    public static MetaCampaignSyncModels.SyncSummary syncCampaignHierarchy() {
        if (!MetaConfigService.isEnabled('campaignSyncEnabled')) {
            return new MetaCampaignSyncModels.SyncSummary();
        }
        MetaApiClient client = MetaApiClient.configured();
        String adAccountId = MetaConfigService.adAccountId();

        List<Map<String, Object>> campaignRows = client.getAll('/' + adAccountId + '/campaigns', new Map<String, String>{ 'fields' => CAMPAIGN_FIELDS });
        List<Map<String, Object>> adSetRows = client.getAll('/' + adAccountId + '/adsets', new Map<String, String>{ 'fields' => AD_SET_FIELDS });
        List<Map<String, Object>> adRows = client.getAll('/' + adAccountId + '/ads', new Map<String, String>{ 'fields' => AD_FIELDS });

        upsertCampaigns(campaignRows);
        Map<String, Id> campaignIdsByMetaId = campaignIdsByMetaId(extractIds(campaignRows, 'id'));

        upsertAdSets(adSetRows, campaignIdsByMetaId);
        Map<String, Id> adSetIdsByMetaId = adSetIdsByMetaId(extractIds(adSetRows, 'id'));

        upsertAds(adRows, campaignIdsByMetaId, adSetIdsByMetaId);

        MetaCampaignSyncModels.SyncSummary summary = new MetaCampaignSyncModels.SyncSummary();
        summary.campaignsProcessed = campaignRows.size();
        summary.adSetsProcessed = adSetRows.size();
        summary.adsProcessed = adRows.size();
        return summary;
    }

    private static void upsertCampaigns(List<Map<String, Object>> rows) {
        List<Campaign> records = new List<Campaign>();
        for (Map<String, Object> row : rows) {
            String metaId = stringValue(row.get('id'));
            if (String.isBlank(metaId)) {
                continue;
            }
            Campaign record = new Campaign();
            record.Meta_Campaign_Id__c = metaId;
            record.Name = firstNonBlank(stringValue(row.get('name')), 'Meta Campaign ' + metaId);
            record.IsActive = true;
            record.Meta_Ad_Account_Id__c = firstNonBlank(stringValue(row.get('account_id')), MetaConfigService.adAccountId());
            record.Meta_Objective__c = stringValue(row.get('objective'));
            record.Meta_Status__c = firstNonBlank(stringValue(row.get('effective_status')), stringValue(row.get('status')));
            record.Daily_Budget__c = parseMinorCurrency(row.get('daily_budget'));
            record.Lifetime_Budget__c = parseMinorCurrency(row.get('lifetime_budget'));
            record.Platform__c = 'Meta';
            record.Campaign_Source__c = 'Meta Ads';
            record.Last_Meta_Sync_At__c = System.now();
            records.add(record);
        }
        if (!records.isEmpty()) {
            Database.UpsertResult[] results = Database.upsert(records, Campaign.Meta_Campaign_Id__c, false);
            List<SObject> loggedRecords = new List<SObject>();
            loggedRecords.addAll(records);
            ErrorLogUtility.logUpsertResults('Meta', 'MetaCampaignSyncService.upsertCampaigns', 'upsert', loggedRecords, results, null, null);
        }
    }

    private static void upsertAdSets(List<Map<String, Object>> rows, Map<String, Id> campaignIdsByMetaId) {
        List<Meta_Ad_Set__c> records = new List<Meta_Ad_Set__c>();
        for (Map<String, Object> row : rows) {
            String metaId = stringValue(row.get('id'));
            if (String.isBlank(metaId)) {
                continue;
            }
            String campaignMetaId = stringValue(row.get('campaign_id'));
            Meta_Ad_Set__c record = new Meta_Ad_Set__c();
            record.Meta_Ad_Set_Id__c = metaId;
            record.Name = firstNonBlank(stringValue(row.get('name')), 'Meta Ad Set ' + metaId);
            record.Meta_Campaign_Id__c = campaignMetaId;
            record.Campaign__c = campaignIdsByMetaId.get(campaignMetaId);
            record.Status__c = firstNonBlank(stringValue(row.get('effective_status')), stringValue(row.get('status')));
            record.Optimization_Goal__c = stringValue(row.get('optimization_goal'));
            record.Daily_Budget__c = parseMinorCurrency(row.get('daily_budget'));
            record.Lifetime_Budget__c = parseMinorCurrency(row.get('lifetime_budget'));
            record.Raw_Payload__c = JSON.serialize(row);
            record.Last_Meta_Sync_At__c = System.now();
            records.add(record);
        }
        if (!records.isEmpty()) {
            Database.UpsertResult[] results = Database.upsert(records, Meta_Ad_Set__c.Meta_Ad_Set_Id__c, false);
            List<SObject> loggedRecords = new List<SObject>();
            loggedRecords.addAll(records);
            ErrorLogUtility.logUpsertResults('Meta', 'MetaCampaignSyncService.upsertAdSets', 'upsert', loggedRecords, results, null, null);
        }
    }

    private static void upsertAds(List<Map<String, Object>> rows, Map<String, Id> campaignIdsByMetaId, Map<String, Id> adSetIdsByMetaId) {
        List<Meta_Ad__c> records = new List<Meta_Ad__c>();
        for (Map<String, Object> row : rows) {
            String metaId = stringValue(row.get('id'));
            if (String.isBlank(metaId)) {
                continue;
            }
            String campaignMetaId = stringValue(row.get('campaign_id'));
            String adSetMetaId = stringValue(row.get('adset_id'));
            Meta_Ad__c record = new Meta_Ad__c();
            record.Meta_Ad_Id__c = metaId;
            record.Name = firstNonBlank(stringValue(row.get('name')), 'Meta Ad ' + metaId);
            record.Meta_Campaign_Id__c = campaignMetaId;
            record.Meta_Ad_Set_Id__c = adSetMetaId;
            record.Campaign__c = campaignIdsByMetaId.get(campaignMetaId);
            record.Meta_Ad_Set__c = adSetIdsByMetaId.get(adSetMetaId);
            record.Status__c = firstNonBlank(stringValue(row.get('effective_status')), stringValue(row.get('status')));
            record.Creative_Id__c = creativeId(row.get('creative'));
            record.Preview_URL__c = stringValue(row.get('preview_shareable_link'));
            record.Raw_Payload__c = JSON.serialize(row);
            record.Last_Meta_Sync_At__c = System.now();
            records.add(record);
        }
        if (!records.isEmpty()) {
            Database.UpsertResult[] results = Database.upsert(records, Meta_Ad__c.Meta_Ad_Id__c, false);
            List<SObject> loggedRecords = new List<SObject>();
            loggedRecords.addAll(records);
            ErrorLogUtility.logUpsertResults('Meta', 'MetaCampaignSyncService.upsertAds', 'upsert', loggedRecords, results, null, null);
        }
    }

    private static Set<String> extractIds(List<Map<String, Object>> rows, String key) {
        Set<String> ids = new Set<String>();
        for (Map<String, Object> row : rows) {
            String value = stringValue(row.get(key));
            if (String.isNotBlank(value)) {
                ids.add(value);
            }
        }
        return ids;
    }

    private static Map<String, Id> campaignIdsByMetaId(Set<String> metaIds) {
        Map<String, Id> result = new Map<String, Id>();
        if (metaIds.isEmpty()) {
            return result;
        }
        for (Campaign record : [
            SELECT Id, Meta_Campaign_Id__c
            FROM Campaign
            WHERE Meta_Campaign_Id__c IN :metaIds
        ]) {
            result.put(record.Meta_Campaign_Id__c, record.Id);
        }
        return result;
    }

    private static Map<String, Id> adSetIdsByMetaId(Set<String> metaIds) {
        Map<String, Id> result = new Map<String, Id>();
        if (metaIds.isEmpty()) {
            return result;
        }
        for (Meta_Ad_Set__c record : [
            SELECT Id, Meta_Ad_Set_Id__c
            FROM Meta_Ad_Set__c
            WHERE Meta_Ad_Set_Id__c IN :metaIds
        ]) {
            result.put(record.Meta_Ad_Set_Id__c, record.Id);
        }
        return result;
    }

    private static String creativeId(Object value) {
        if (value instanceof Map<String, Object>) {
            return stringValue(((Map<String, Object>) value).get('id'));
        }
        return stringValue(value);
    }

    private static Decimal parseMinorCurrency(Object value) {
        Decimal parsed = parseDecimal(value);
        return parsed == null ? null : (parsed / Decimal.valueOf(100)).setScale(2);
    }

    private static Decimal parseDecimal(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isBlank(firstValue) ? secondValue : firstValue;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}