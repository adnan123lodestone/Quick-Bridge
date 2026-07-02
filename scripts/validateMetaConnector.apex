List<String> failures = new List<String>();

List<Integration_Product__c> products = [
    SELECT Id, Name, Product_Key__c, Connector_Key__c, Logo_URL__c, Status__c
    FROM Integration_Product__c
    WHERE Product_Key__c = 'meta'
];
if (products.size() != 1) {
    failures.add('Expected exactly one Integration_Product__c row for Product_Key__c = meta, found ' + products.size() + '.');
} else {
    Integration_Product__c product = products[0];
    if (product.Connector_Key__c != 'meta') failures.add('Meta product Connector_Key__c is not meta.');
    if (product.Logo_URL__c != '/resource/Meta_Logo') failures.add('Meta product Logo_URL__c is not /resource/Meta_Logo.');
}

List<Connector_Instance__c> instances = [
    SELECT Id, Active__c, Named_Credential__c
    FROM Connector_Instance__c
    WHERE Connector_Key__c = 'meta'
];
if (instances.size() != 1) {
    failures.add('Expected exactly one Connector_Instance__c row for Connector_Key__c = meta, found ' + instances.size() + '.');
}

Set<String> requiredFields = new Set<String>{
    'accessTokenRef',
    'appSecretRef',
    'webhookVerifyTokenRef',
    'adAccountId',
    'pageId',
    'instagramBusinessAccountId',
    'campaignSyncEnabled',
    'leadAdsEnabled',
    'commentAttributionEnabled',
    'insightsSyncEnabled',
    'defaultLeadSource',
    'defaultCampaignMemberStatus'
};
Set<String> foundFields = new Set<String>();
for (Connector_Config_Value__c valueRecord : [
    SELECT Field_Key__c, Value__c, Is_Secret_Reference__c
    FROM Connector_Config_Value__c
    WHERE Connector_Key__c = 'meta'
]) {
    foundFields.add(valueRecord.Field_Key__c);
    if (String.valueOf(valueRecord.Value__c).startsWith('REPLACE_WITH_')) {
        failures.add('Placeholder value remains for Meta config field ' + valueRecord.Field_Key__c + '.');
    }
    if (
        new Set<String>{ 'accessTokenRef', 'appSecretRef', 'webhookVerifyTokenRef' }.contains(valueRecord.Field_Key__c) &&
        valueRecord.Is_Secret_Reference__c != true
    ) {
        failures.add('Meta config field ' + valueRecord.Field_Key__c + ' is not marked as a secret reference.');
    }
}
Set<String> missingFields = new Set<String>(requiredFields);
missingFields.removeAll(foundFields);
if (!missingFields.isEmpty()) {
    failures.add('Missing Meta config fields: ' + String.join(new List<String>(missingFields), ', '));
}

List<PermissionSet> adminPermissionSets = [
    SELECT Id
    FROM PermissionSet
    WHERE Name = 'QuickBridge_Admin'
    LIMIT 1
];
if (adminPermissionSets.isEmpty()) {
    failures.add('QuickBridge_Admin permission set was not found.');
}

if (!failures.isEmpty()) {
    System.debug(LoggingLevel.ERROR, 'Meta connector validation failed: ' + String.join(failures, ' | '));
    System.assert(false, 'Meta connector validation failed: ' + String.join(failures, ' | '));
}

System.debug('Meta connector validation passed.');
