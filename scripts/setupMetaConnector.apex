String connectorKey = 'meta';

List<Connector_Instance__c> existingInstances = [
    SELECT Id
    FROM Connector_Instance__c
    WHERE Connector_Key__c = :connectorKey
    LIMIT 1
];

Connector_Instance__c instanceRecord = existingInstances.isEmpty()
    ? new Connector_Instance__c()
    : existingInstances[0];
instanceRecord.Name = 'Meta';
instanceRecord.Connector_Key__c = connectorKey;
instanceRecord.Connector_Label__c = 'Meta';
instanceRecord.Active__c = true;
instanceRecord.Health_Status__c = 'Unknown';
instanceRecord.Entitlement_Status__c = 'Active';
instanceRecord.Environment__c = 'Production';
if (instanceRecord.Id == null) {
    insert instanceRecord;
} else {
    update instanceRecord;
}

Map<String, Connector_Config_Value__c> existingValuesByField = new Map<String, Connector_Config_Value__c>();
for (Connector_Config_Value__c row : [
    SELECT Id, Field_Key__c
    FROM Connector_Config_Value__c
    WHERE Connector_Instance__c = :instanceRecord.Id
]) {
    existingValuesByField.put(row.Field_Key__c, row);
}

Map<String, String> valuesByField = new Map<String, String>{
    'appId' => 'REPLACE_WITH_META_APP_ID',
    'appSecretRef' => 'REPLACE_WITH_META_APP_SECRET_REFERENCE',
    'accessTokenRef' => 'REPLACE_WITH_META_ACCESS_TOKEN_REFERENCE',
    'webhookVerifyTokenRef' => 'REPLACE_WITH_META_WEBHOOK_VERIFY_TOKEN_REFERENCE',
    'adAccountId' => 'REPLACE_WITH_META_AD_ACCOUNT_ID',
    'pageId' => 'REPLACE_WITH_FACEBOOK_PAGE_ID',
    'instagramBusinessAccountId' => 'REPLACE_WITH_INSTAGRAM_BUSINESS_ACCOUNT_ID',
    'graphApiVersion' => 'v21.0',
    'campaignSyncEnabled' => 'true',
    'leadAdsEnabled' => 'true',
    'commentAttributionEnabled' => 'true',
    'defaultLeadSource' => 'Meta Lead Ad',
    'defaultCampaignMemberStatus' => 'Responded',
    'autoCreateCampaignMember' => 'true',
    'leadCreationMode' => 'Manual Review',
    'keywordRulesJson' => '[]',
    'insightsSyncEnabled' => 'true',
    'syncFrequency' => 'Hourly',
    'attributionWindowDays' => '30',
    'createMissingCampaigns' => 'false',
    'updateCampaignMetrics' => 'true',
    'utmMappingMode' => 'Standard',
    'defaultFallbackCampaignId' => ''
};

Set<String> secretReferenceFields = new Set<String>{
    'appSecretRef',
    'accessTokenRef',
    'webhookVerifyTokenRef'
};

List<Connector_Config_Value__c> upserts = new List<Connector_Config_Value__c>();
for (String fieldKey : valuesByField.keySet()) {
    Connector_Config_Value__c valueRecord = existingValuesByField.containsKey(fieldKey)
        ? existingValuesByField.get(fieldKey)
        : new Connector_Config_Value__c();
    valueRecord.Name = connectorKey + ':' + fieldKey;
    valueRecord.Connector_Instance__c = instanceRecord.Id;
    valueRecord.Connector_Key__c = connectorKey;
    valueRecord.Field_Key__c = fieldKey;
    valueRecord.Value__c = valuesByField.get(fieldKey);
    valueRecord.Is_Secret_Reference__c = secretReferenceFields.contains(fieldKey);
    upserts.add(valueRecord);
}

upsert upserts;
System.debug('Seeded Meta connector instance and ' + upserts.size() + ' config value records. Replace placeholder values before enabling live traffic.');
