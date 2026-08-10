public class QBItemToProductSyncBatch implements Database.Batchable<String>, Database.AllowsCallouts {
    
    private String lastSyncDate;
    
    public QBItemToProductSyncBatch() {
        Datetime yesterday = Datetime.now().addDays(-1);
        this.lastSyncDate = yesterday.format('YYYY-MM-dd');
    }
    
    public QBItemToProductSyncBatch(String syncDate) {
        this.lastSyncDate = syncDate;
    }
    
    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> itemPayloads = new List<String>();

        try {
            itemPayloads = QuickBooksBulkQueryService.serializeRecords(
                QuickBooksBulkQueryService.queryUpdatedSince('Item', lastSyncDate)
            );
        } catch (Exception e) {
            System.debug('Error querying QuickBooks items: ' + e.getMessage());
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBItemToProductSyncBatch.start',
                e,
                null,
                null
            );
        }
        
        return itemPayloads;
    }
    
    public void execute(Database.BatchableContext bc, List<String> scope) {
        IntegrationUsageService.assertCanConsumeTask('QuickBooks', scope == null ? 1 : scope.size());
        QBTriggerHandler.isProductProcessing = true;

        try {
            List<Product2> productsToUpsert = new List<Product2>();
            
            Set<String> qbIds = new Set<String>();
            List<Map<String, Object>> itemDataList = new List<Map<String, Object>>();

            for (String itemPayload : scope) {
                String itemId = getExternalIdFromPayload(itemPayload);
                try {
                    Map<String, Object> itemData = resolveItemData(itemPayload);
                    if (itemData != null) {
                        itemDataList.add(itemData);
                        if (itemData.containsKey('Id')) {
                            String qbId = asString(itemData.get('Id'));
                            if (String.isNotBlank(qbId)) {
                                qbIds.add(qbId);
                            }
                        }
                    }
                } catch (Exception e) {
                    System.debug('Error processing item ' + itemId + ': ' + e.getMessage());
                    ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
                    context.gatewayName = 'QuickBooks';
                    context.classMethodName = 'QBItemToProductSyncBatch.execute.processItem';
                    context.errorMessage = e.getTypeName() + ': ' + e.getMessage();
                    context.stackTrace = e.getStackTraceString();
                    context.sourceObjectApiName = 'Product2';
                    context.sourceRecordIdText = itemId;
                    context.errorCategory = 'Code Exception';
                    context.externalReference = itemId;
                    ErrorLogUtility.logError(context);
                }
            }

            Map<String, Product2> existingProductsByQbId = new Map<String, Product2>();
            if (!qbIds.isEmpty()) {
                String qry = 'SELECT Id, ' + getProductQbIdSelectFields() + ', Sale_Price__c FROM Product2 WHERE ' + getProductQbIdWhereClause();
                for (Product2 p : (List<Product2>)Database.query(qry)) {
                    String qbId = getProductQbIdValue(p);
                    if (String.isNotBlank(qbId)) {
                        existingProductsByQbId.put(qbId, p);
                    }
                }
            }

            Map<String, String> mapping = QBObjectMappings.getItemToProductMapping();

            for (Map<String, Object> itemData : itemDataList) {
                String qbId = asString(itemData.get('Id'));
                Product2 existingProd = String.isNotBlank(qbId) ? existingProductsByQbId.get(qbId) : null;
                Product2 productToSync = processItemData(itemData, existingProd, mapping);
                if (productToSync != null) {
                    productsToUpsert.add(productToSync);
                }
            }
            
            if (!productsToUpsert.isEmpty()) {
                Map<String, Decimal> qbIdToSalePrice = new Map<String, Decimal>();
                for (Product2 p : productsToUpsert) {
                    String qbId = getProductQbIdValue(p);
                    if (p != null && p.Sale_Price__c != null && String.isNotBlank(qbId)) {
                        qbIdToSalePrice.put(qbId, p.Sale_Price__c);
                    }
                }

                Database.UpsertResult[] results = Database.upsert(productsToUpsert, Product2.QuickbookID__c, false);
                ErrorLogUtility.logUpsertResults(
                    'QuickBooks',
                    'QBItemToProductSyncBatch.execute.upsertProducts',
                    'upsert',
                    productsToUpsert,
                    results,
                    null,
                    null
                );
                
                Id standardPricebookId;
                try {
                    if (Test.isRunningTest()) {
                        standardPricebookId = Test.getStandardPricebookId();
                    } else {
                        List<Pricebook2> pbs = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
                        standardPricebookId = pbs.isEmpty() ? null : pbs[0].Id;
                    }
                } catch (Exception e) {
                    if (Test.isRunningTest()) {
                        standardPricebookId = Test.getStandardPricebookId();
                    } else {
                        System.debug('Error getting standard pricebook: ' + e.getMessage());
                        ErrorLogUtility.logException(
                            'QuickBooks',
                            'QBItemToProductSyncBatch.execute.getStandardPricebook',
                            e,
                            null,
                            null
                        );
                        return;
                    }
                }

                Set<Id> productIds = new Set<Id>();
                for (Database.UpsertResult result : results) {
                    if (result.isSuccess()) {
                        productIds.add(result.getId());
                    }
                }
                IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', productIds.size());
                
                Map<Id, PricebookEntry> existingEntries = new Map<Id, PricebookEntry>();
                if (!productIds.isEmpty()) {
                    for (PricebookEntry pbe : [
                        SELECT Id, Product2Id, UnitPrice 
                        FROM PricebookEntry 
                        WHERE Product2Id IN :productIds AND Pricebook2Id = :standardPricebookId
                    ]) {
                        existingEntries.put(pbe.Product2Id, pbe);
                    }
                }

                List<PricebookEntry> pricebookEntries = new List<PricebookEntry>();
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        Product2 product = productsToUpsert[i];
                        Id productId = results[i].getId();
                        String qbId = getProductQbIdValue(product);
                        Decimal salePrice = product.Sale_Price__c != null ? product.Sale_Price__c : (String.isNotBlank(qbId) ? qbIdToSalePrice.get(qbId) : null);
                        
                        if (salePrice == null || existingEntries.containsKey(productId)) {
                            continue;
                        }
                        
                        PricebookEntry pbe = new PricebookEntry();
                        pbe.Product2Id = productId;
                        pbe.Pricebook2Id = standardPricebookId;
                        pbe.UnitPrice = salePrice;
                        pbe.IsActive = true;
                        pricebookEntries.add(pbe);
                    }
                }
                
                if (!pricebookEntries.isEmpty()) {
                    try {
                        Database.insert(pricebookEntries, false);
                    } catch (Exception e) {
                        System.debug('Error inserting pricebook entries: ' + e.getMessage());
                        ErrorLogUtility.logException(
                            'QuickBooks',
                            'QBItemToProductSyncBatch.execute.insertPricebookEntries',
                            e,
                            null,
                            null
                        );
                    }
                }
            }
            
        } finally {
            QBTriggerHandler.isProductProcessing = false;
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('QBItemToProductSyncBatch completed');
    }

    private Map<String, Object> resolveItemData(String itemPayload) {
        if (String.isBlank(itemPayload)) {
            return null;
        }

        try {
            Object parsed = JSON.deserializeUntyped(itemPayload);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>)parsed;
            }
        } catch (Exception e) {
            // Legacy payloads were raw QuickBooks ids; hydrate only those compatibility inputs.
        }

        return null;
    }

    private String getExternalIdFromPayload(String itemPayload) {
        Map<String, Object> itemData = resolveSerializedPayload(itemPayload);
        return itemData == null ? itemPayload : asString(itemData.get('Id'));
    }

    private Map<String, Object> resolveSerializedPayload(String payload) {
        if (String.isBlank(payload)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(payload);
            return parsed instanceof Map<String, Object> ? (Map<String, Object>)parsed : null;
        } catch (Exception e) {
            return null;
        }
    }
    
    private Product2 processItemData(Map<String, Object> itemData) {
        return processItemData(itemData, null, null);
    }

    private Product2 processItemData(Map<String, Object> itemData, Product2 existingProd, Map<String, String> mapping) {
        if (itemData == null) return null;
        String qbId = asString(itemData.get('Id'));
        
        Product2 product = existingProd;
        if (product == null && String.isNotBlank(qbId)) {
            Set<String> qbIds = new Set<String>{ qbId };
            String qry = 'SELECT Id, ' + getProductQbIdSelectFields() + ', Sale_Price__c FROM Product2 WHERE ' + getProductQbIdWhereClause() + ' LIMIT 1';
            List<Product2> existingProducts = Database.query(qry);
            if (!existingProducts.isEmpty()) {
                product = existingProducts[0];
            }
        }
        
        if (product == null) {
            product = new Product2();
            product.Is_Synced__c = true;
        }
        
        if (mapping == null) {
            mapping = QBObjectMappings.getItemToProductMapping();
        }

        for (String qbField : mapping.keySet()) {
            Object qbValue = getNestedValue(itemData, qbField);
            if (qbValue != null) {
                try {
                    putFieldValue(product, mapping.get(qbField), qbValue);
                } catch (Exception e) {}
            }
        }

        putFieldValue(product, 'QuickbookID__c', qbId);
        try { putFieldValue(product, 'QuickBridgeTLG__QuickbookID__c', qbId); } catch(Exception e){}

        if (String.isBlank(product.Name)) {
            if (itemData.containsKey('Name') && String.isNotBlank(asString(itemData.get('Name')))) {
                product.Name = asString(itemData.get('Name'));
            } else if (itemData.containsKey('FullyQualifiedName') && String.isNotBlank(asString(itemData.get('FullyQualifiedName')))) {
                product.Name = asString(itemData.get('FullyQualifiedName'));
            } else {
                product.Name = 'QBO Product ' + (String.isNotBlank(qbId) ? qbId : 'Unknown');
            }
        }
        if (product.Sale_Price__c == null && itemData.containsKey('UnitPrice') && itemData.get('UnitPrice') != null) {
            try {
                product.Sale_Price__c = Decimal.valueOf(String.valueOf(itemData.get('UnitPrice')));
            } catch (Exception e) {}
        }
        
        return product;
    }

    private static String getProductQbIdSelectFields() {
        Set<String> fieldNames = new Set<String>();
        Map<String, Schema.SObjectField> fMap = Schema.SObjectType.Product2.fields.getMap();
        for (String key : fMap.keySet()) {
            if (key.endsWith('quickbookid__c')) {
                fieldNames.add(fMap.get(key).getDescribe().getName());
            }
        }
        return fieldNames.isEmpty() ? 'Id' : String.join(new List<String>(fieldNames), ', ');
    }

    private static String getProductQbIdWhereClause() {
        Set<String> fieldNames = new Set<String>();
        Map<String, Schema.SObjectField> fMap = Schema.SObjectType.Product2.fields.getMap();
        for (String key : fMap.keySet()) {
            if (key.endsWith('quickbookid__c')) {
                fieldNames.add(fMap.get(key).getDescribe().getName());
            }
        }
        List<String> clauses = new List<String>();
        for (String fName : fieldNames) {
            clauses.add(fName + ' IN :qbIds');
        }
        return clauses.isEmpty() ? 'Id IN :qbIds' : String.join(clauses, ' OR ');
    }

    private static String getProductQbIdValue(Product2 p) {
        if (p == null) return null;
        try {
            String val = (String)p.get('QuickbookID__c');
            if (String.isNotBlank(val)) return val;
        } catch (Exception e) {}
        try {
            String val = (String)p.get('QuickBridgeTLG__QuickbookID__c');
            if (String.isNotBlank(val)) return val;
        } catch (Exception e) {}
        return null;
    }

    private static String asString(Object value) {
        if (value == null || value instanceof Map<String, Object> || value instanceof List<Object>) {
            return null;
        }
        return String.valueOf(value);
    }

    private Object getNestedValue(Map<String, Object> data, String path) {
        String[] pathParts = path.split('\\.');
        Object current = data;

        for (String part : pathParts) {
            if (current instanceof Map<String, Object>) {
                current = ((Map<String, Object>)current).get(part);
            } else {
                return null;
            }
        }
        return current;
    }

    private void putFieldValue(SObject record, String fieldName, Object value) {
        if (record == null || String.isBlank(fieldName) || fieldName.contains('.') || value == null) {
            return;
        }

        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        if (!fields.containsKey(fieldName)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();
        if (!fieldDescribe.isCreateable() && !fieldDescribe.isUpdateable()) {
            return;
        }

        Schema.DisplayType displayType = fieldDescribe.getType();
        record.put(fieldName, coerceValue(value, displayType));
    }

    private Object coerceValue(Object value, Schema.DisplayType displayType) {
        if (value == null) {
            return null;
        }

        try {
            if (
                displayType == Schema.DisplayType.Currency ||
                displayType == Schema.DisplayType.Double ||
                displayType == Schema.DisplayType.Percent
            ) {
                return Decimal.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.Integer) {
                return Integer.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.Boolean) {
                if (value instanceof Boolean) {
                    return value;
                }
                return String.valueOf(value).toLowerCase() == 'true';
            }
            if (displayType == Schema.DisplayType.Date) {
                if (value instanceof Date) {
                    return value;
                }
                return Date.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.DateTime) {
                if (value instanceof Datetime) {
                    return value;
                }
                return Datetime.valueOf(String.valueOf(value));
            }
        } catch (Exception e) {
            return value;
        }

        return value;
    }

    public void syncItemFromQBO(String itemId) {
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', '/item/' + itemId, null);
        if (res.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> item = (Map<String, Object>) data.get('Item');
            Product2 prod = processItemData(item);
            Database.upsert(prod, Product2.QuickbookID__c, false);
        } else {
            throw new CalloutException('Unable to fetch item from QBO: ' + res.getBody());
        }
    }
}