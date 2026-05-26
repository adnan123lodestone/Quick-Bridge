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
            
            for (String itemPayload : scope) {
                String itemId = getExternalIdFromPayload(itemPayload);
                try {
                    Map<String, Object> itemData = resolveItemData(itemPayload);
                    
                    if (itemData != null) {
                        Product2 productToSync = processItemData(itemData);
                        if (productToSync != null) {
                            productsToUpsert.add(productToSync);
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
            
            if (!productsToUpsert.isEmpty()) {
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
                    standardPricebookId = Test.isRunningTest() ? Test.getStandardPricebookId() : 
                        [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
                } catch (Exception e) {
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

                Set<Id> productIds = new Set<Id>();
                for (Database.UpsertResult result : results) {
                    if (result.isSuccess()) {
                        productIds.add(result.getId());
                    }
                }
                IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', productIds.size());
                
                Map<Id, PricebookEntry> existingEntries = new Map<Id, PricebookEntry>();
                for (PricebookEntry pbe : [
                    SELECT Id, Product2Id, UnitPrice 
                    FROM PricebookEntry 
                    WHERE Product2Id IN :productIds 
                    AND Pricebook2Id = :standardPricebookId
                ]) {
                    existingEntries.put(pbe.Product2Id, pbe);
                }

                List<PricebookEntry> pricebookEntries = new List<PricebookEntry>();
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        Product2 product = productsToUpsert[i];
                        Id productId = results[i].getId();
                        
                        if (product.Sale_Price__c == null || existingEntries.containsKey(productId)) {
                            continue;
                        }
                        
                        PricebookEntry pbe = new PricebookEntry();
                        pbe.Product2Id = productId;
                        pbe.Pricebook2Id = standardPricebookId;
                        pbe.UnitPrice = product.Sale_Price__c;
                        pbe.IsActive = true;
                        pricebookEntries.add(pbe);
                    }
                }
                
                if (!pricebookEntries.isEmpty()) {
                    try {
                        insert pricebookEntries;
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

        // Scheduled/batch execution must receive hydrated payloads from start().
        // Single-record hydration remains in syncItemFromQBO().
        return null;
    }

    private String getExternalIdFromPayload(String itemPayload) {
        Map<String, Object> itemData = resolveSerializedPayload(itemPayload);
        return itemData == null ? itemPayload : String.valueOf(itemData.get('Id'));
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
        String qbId = (String)itemData.get('Id');
        
        List<Product2> existingProducts = [SELECT Id, QuickbookID__c, Sale_Price__c 
                                          FROM Product2 
                                          WHERE QuickbookID__c = :qbId LIMIT 1];
        
        Product2 product;
        if (!existingProducts.isEmpty()) {
            product = existingProducts[0];
        } else {
            product = new Product2();
            product.Is_Synced__c = true;
        }
        
        Map<String, String> mapping = QBObjectMappings.getItemToProductMapping();
        for (String qbField : mapping.keySet()) {
            Object qbValue = getNestedValue(itemData, qbField);
            if (qbValue != null) {
                try {
                    putFieldValue(product, mapping.get(qbField), qbValue);
                } catch (Exception e) {}
            }
        }

        product.QuickbookID__c = qbId;
        
        return product;
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
        upsert prod Product2.QuickbookID__c;
    } else {
        throw new CalloutException('Unable to fetch item from QBO: ' + res.getBody());
    }
}
}