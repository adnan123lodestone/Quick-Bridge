public with sharing class MetaInsightsSyncService {
    private static final String INSIGHT_FIELDS = 'campaign_id,adset_id,ad_id,spend,impressions,clicks,reach,actions';

    public static MetaCampaignSyncModels.InsightSummary syncInsights() {
        if (!MetaConfigService.isEnabled('insightsSyncEnabled')) {
            return new MetaCampaignSyncModels.InsightSummary();
        }
        MetaApiClient client = MetaApiClient.configured();
        String adAccountId = MetaConfigService.adAccountId();
        MetaCampaignSyncModels.InsightSummary summary = new MetaCampaignSyncModels.InsightSummary();
        List<Map<String, Object>> campaignRows = client.getAll('/' + adAccountId + '/insights', paramsForLevel('campaign'));
        List<Map<String, Object>> adSetRows = client.getAll('/' + adAccountId + '/insights', paramsForLevel('adset'));
        List<Map<String, Object>> adRows = client.getAll('/' + adAccountId + '/insights', paramsForLevel('ad'));
        summary.campaignsUpdated = updateCampaignInsights(campaignRows);
        summary.adSetsUpdated = updateAdSetInsights(adSetRows);
        summary.adsUpdated = updateAdInsights(adRows);
        return summary;
    }

    private static Map<String, String> paramsForLevel(String level) {
        return new Map<String, String>{
            'level' => level,
            'fields' => INSIGHT_FIELDS,
            'date_preset' => 'maximum'
        };
    }

    private static Integer updateCampaignInsights(List<Map<String, Object>> rows) {
        Map<String, Map<String, Object>> rowsByMetaId = rowsById(rows, 'campaign_id');
        if (rowsByMetaId.isEmpty()) {
            return 0;
        }
        List<Campaign> updates = new List<Campaign>();
        for (Campaign record : [
            SELECT Id, Meta_Campaign_Id__c
            FROM Campaign
            WHERE Meta_Campaign_Id__c IN :rowsByMetaId.keySet()
        ]) {
            Map<String, Object> row = rowsByMetaId.get(record.Meta_Campaign_Id__c);
            record.Spend_To_Date__c = parseDecimal(row.get('spend'));
            record.Impressions__c = parseDecimal(row.get('impressions'));
            record.Clicks__c = parseDecimal(row.get('clicks'));
            record.Reach__c = parseDecimal(row.get('reach'));
            Decimal leads = leadCount(row);
            record.Leads_From_Meta__c = leads;
            record.Last_Meta_Sync_At__c = System.now();
            updates.add(record);
        }
        if (!updates.isEmpty()) {
            Database.SaveResult[] results = Database.update(updates, false);
            List<SObject> loggedRecords = new List<SObject>();
            loggedRecords.addAll(updates);
            ErrorLogUtility.logDmlResults('Meta', 'MetaInsightsSyncService.updateCampaignInsights', 'update', loggedRecords, results, null, null);
        }
        logMissing('Campaign', rowsByMetaId.keySet(), extractCampaignIds(updates));
        return updates.size();
    }

    private static Integer updateAdSetInsights(List<Map<String, Object>> rows) {
        Map<String, Map<String, Object>> rowsByMetaId = rowsById(rows, 'adset_id');
        if (rowsByMetaId.isEmpty()) {
            return 0;
        }
        List<Meta_Ad_Set__c> updates = new List<Meta_Ad_Set__c>();
        for (Meta_Ad_Set__c record : [
            SELECT Id, Meta_Ad_Set_Id__c
            FROM Meta_Ad_Set__c
            WHERE Meta_Ad_Set_Id__c IN :rowsByMetaId.keySet()
        ]) {
            Map<String, Object> row = rowsByMetaId.get(record.Meta_Ad_Set_Id__c);
            record.Spend__c = parseDecimal(row.get('spend'));
            record.Impressions__c = parseDecimal(row.get('impressions'));
            record.Clicks__c = parseDecimal(row.get('clicks'));
            Decimal leads = leadCount(row);
            record.Leads__c = leads;
            record.Last_Meta_Sync_At__c = System.now();
            updates.add(record);
        }
        if (!updates.isEmpty()) {
            Database.SaveResult[] results = Database.update(updates, false);
            List<SObject> loggedRecords = new List<SObject>();
            loggedRecords.addAll(updates);
            ErrorLogUtility.logDmlResults('Meta', 'MetaInsightsSyncService.updateAdSetInsights', 'update', loggedRecords, results, null, null);
        }
        logMissing('Meta_Ad_Set__c', rowsByMetaId.keySet(), extractAdSetIds(updates));
        return updates.size();
    }

    private static Integer updateAdInsights(List<Map<String, Object>> rows) {
        Map<String, Map<String, Object>> rowsByMetaId = rowsById(rows, 'ad_id');
        if (rowsByMetaId.isEmpty()) {
            return 0;
        }
        List<Meta_Ad__c> updates = new List<Meta_Ad__c>();
        for (Meta_Ad__c record : [
            SELECT Id, Meta_Ad_Id__c
            FROM Meta_Ad__c
            WHERE Meta_Ad_Id__c IN :rowsByMetaId.keySet()
        ]) {
            Map<String, Object> row = rowsByMetaId.get(record.Meta_Ad_Id__c);
            record.Spend__c = parseDecimal(row.get('spend'));
            record.Impressions__c = parseDecimal(row.get('impressions'));
            record.Clicks__c = parseDecimal(row.get('clicks'));
            Decimal leads = leadCount(row);
            record.Leads__c = leads;
            record.Last_Meta_Sync_At__c = System.now();
            updates.add(record);
        }
        if (!updates.isEmpty()) {
            Database.SaveResult[] results = Database.update(updates, false);
            List<SObject> loggedRecords = new List<SObject>();
            loggedRecords.addAll(updates);
            ErrorLogUtility.logDmlResults('Meta', 'MetaInsightsSyncService.updateAdInsights', 'update', loggedRecords, results, null, null);
        }
        logMissing('Meta_Ad__c', rowsByMetaId.keySet(), extractAdIds(updates));
        return updates.size();
    }

    private static Map<String, Map<String, Object>> rowsById(List<Map<String, Object>> rows, String key) {
        Map<String, Map<String, Object>> result = new Map<String, Map<String, Object>>();
        for (Map<String, Object> row : rows) {
            String idValue = stringValue(row.get(key));
            if (String.isNotBlank(idValue)) {
                result.put(idValue, row);
            }
        }
        return result;
    }

    private static Decimal leadCount(Map<String, Object> row) {
        Decimal direct = parseDecimal(row == null ? null : row.get('leads'));
        if (direct != null) {
            return direct;
        }
        Object actionsValue = row == null ? null : row.get('actions');
        if (!(actionsValue instanceof List<Object>)) {
            return null;
        }
        for (Object actionValue : (List<Object>) actionsValue) {
            if (!(actionValue instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> action = (Map<String, Object>) actionValue;
            String actionType = stringValue(action.get('action_type'));
            if (actionType == 'lead' || actionType == 'onsite_conversion.lead_grouped') {
                return parseDecimal(action.get('value'));
            }
        }
        return null;
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

    private static void logMissing(String objectApiName, Set<String> requestedIds, Set<String> foundIds) {
        Set<String> missing = new Set<String>(requestedIds);
        missing.removeAll(foundIds);
        for (String externalId : missing) {
            ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
            context.gatewayName = 'Meta';
            context.classMethodName = 'MetaInsightsSyncService.logMissing';
            context.errorMessage = 'Meta insights row skipped because no ' + objectApiName + ' record exists for external ID ' + externalId + '.';
            context.errorCategory = 'Sync Gap';
            context.sourceObjectApiName = objectApiName;
            context.sourceRecordIdText = externalId;
            ErrorLogUtility.logError(context);
        }
    }

    private static Set<String> extractCampaignIds(List<Campaign> records) {
        Set<String> ids = new Set<String>();
        for (Campaign record : records) ids.add(record.Meta_Campaign_Id__c);
        return ids;
    }

    private static Set<String> extractAdSetIds(List<Meta_Ad_Set__c> records) {
        Set<String> ids = new Set<String>();
        for (Meta_Ad_Set__c record : records) ids.add(record.Meta_Ad_Set_Id__c);
        return ids;
    }

    private static Set<String> extractAdIds(List<Meta_Ad__c> records) {
        Set<String> ids = new Set<String>();
        for (Meta_Ad__c record : records) ids.add(record.Meta_Ad_Id__c);
        return ids;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}