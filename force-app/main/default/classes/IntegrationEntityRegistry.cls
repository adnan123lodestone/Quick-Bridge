public with sharing class IntegrationEntityRegistry {
    private class EntityDefinition {
        String integrationKey;
        String salesforceObject;
        String externalEntity;
    }

    private static List<EntityDefinition> cachedDefinitions;

    public static String resolveExternalEntity(String integrationKey, String salesforceObject, String requestedExternalEntity, String defaultEntity) {
        String normalizedIntegration = normalizeIntegration(integrationKey);
        Set<String> validEntities = externalEntities(normalizedIntegration);
        if (String.isNotBlank(requestedExternalEntity) && validEntities.contains(requestedExternalEntity)) {
            return requestedExternalEntity;
        }

        String normalizedSalesforceObject = stripNamespace(salesforceObject);
        for (EntityDefinition definition : definitions()) {
            if (definition.integrationKey == normalizedIntegration && definition.salesforceObject == normalizedSalesforceObject) {
                return definition.externalEntity;
            }
        }
        return defaultEntity;
    }

    private static Set<String> externalEntities(String integrationKey) {
        Set<String> result = new Set<String>();
        for (EntityDefinition definition : definitions()) {
            if (definition.integrationKey == integrationKey) {
                result.add(definition.externalEntity);
            }
        }
        return result;
    }

    private static List<EntityDefinition> definitions() {
        if (cachedDefinitions != null) {
            return cachedDefinitions;
        }
        List<EntityDefinition> result = new List<EntityDefinition>();
        try {
            for (Integration_Object_Map__mdt row : [
                SELECT Connector_Key__c, Salesforce_Object__c, External_Object__c
                FROM Integration_Object_Map__mdt
                WHERE Active__c = true
            ]) {
                EntityDefinition definition = new EntityDefinition();
                definition.integrationKey = normalizeIntegration(row.Connector_Key__c);
                definition.salesforceObject = stripNamespace(row.Salesforce_Object__c);
                definition.externalEntity = row.External_Object__c;
                result.add(definition);
            }
        } catch (Exception ignored) {
        }
        try {
            for (Integration_Entity_Definition__c row : [
                SELECT Integration_Key__c, Salesforce_Object__c, External_Entity__c
                FROM Integration_Entity_Definition__c
                WHERE Active__c = true
            ]) {
                EntityDefinition definition = new EntityDefinition();
                definition.integrationKey = normalizeIntegration(row.Integration_Key__c);
                definition.salesforceObject = stripNamespace(row.Salesforce_Object__c);
                definition.externalEntity = row.External_Entity__c;
                result.add(definition);
            }
        } catch (Exception ignored) {
        }
        if (result.isEmpty()) {
            result.addAll(fallbackDefinitions());
        }
        cachedDefinitions = result;
        return cachedDefinitions;
    }

    private static List<EntityDefinition> fallbackDefinitions() {
        List<EntityDefinition> rows = new List<EntityDefinition>();
        add(rows, 'qbonline', 'Account', 'Customer');
        add(rows, 'qbonline', 'Contact', 'Customer');
        add(rows, 'qbonline', 'Product2', 'Item');
        add(rows, 'qbonline', 'Order', 'Invoice');
        add(rows, 'qbonline', 'Invoice__c', 'Invoice');
        add(rows, 'qbonline', 'Credit_Memo__c', 'CreditMemo');
        add(rows, 'qbonline', 'Purchase_Order__c', 'PurchaseOrder');
        add(rows, 'qbonline', 'Item_Sales_Tax__c', 'TaxCode');
        add(rows, 'shopify', 'Account', 'Customer');
        add(rows, 'shopify', 'Order', 'Order');
        add(rows, 'shopify', 'Product2', 'Product');
        add(rows, 'shopify', 'OrderItem', 'LineItem');
        return rows;
    }

    private static void add(List<EntityDefinition> rows, String integrationKey, String salesforceObject, String externalEntity) {
        EntityDefinition definition = new EntityDefinition();
        definition.integrationKey = normalizeIntegration(integrationKey);
        definition.salesforceObject = salesforceObject;
        definition.externalEntity = externalEntity;
        rows.add(definition);
    }

    private static String normalizeIntegration(String integrationKey) {
        String normalized = String.isBlank(integrationKey) ? '' : integrationKey.toLowerCase().replaceAll('[^a-z0-9]', '');
        if (normalized == 'quickbooks' || normalized == 'qbo') {
            return 'qbonline';
        }
        return normalized;
    }

    private static String stripNamespace(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return objectApiName;
        }
        if (objectApiName.endsWith('__c') && objectApiName.indexOf('__') != objectApiName.lastIndexOf('__')) {
            return objectApiName.substringAfter('__');
        }
        return objectApiName;
    }

    @TestVisible
    static void clearCache() {
        cachedDefinitions = null;
    }
}