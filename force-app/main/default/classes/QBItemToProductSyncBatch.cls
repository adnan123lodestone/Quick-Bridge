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
        List<String> itemIdsList = new List<String>();
        
        try {
            String query = 'select * from Item Where Metadata.LastUpdatedTime > \'' + lastSyncDate + '\'';
            String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
            String resourcePath = '/query?query=' + encodedQuery + '&minorversion=65';
            
            HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', resourcePath, null);
            if (response != null && response.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                
                if (responseMap != null && responseMap.containsKey('QueryResponse')) {
                    Map<String, Object> queryResponse = (Map<String, Object>)responseMap.get('QueryResponse');
                    
                    if (queryResponse != null && queryResponse.containsKey('Item')) {
                        List<Object> items = (List<Object>)queryResponse.get('Item');
                        if (items != null) {
                            for (Object itemObj : items) {
                                if (itemObj != null) {
                                    Map<String, Object> item = (Map<String, Object>)itemObj;
                                    if (item.containsKey('Id')) {
                                        itemIdsList.add((String)item.get('Id'));
                                    }
                                }
                            }
                        }
                    }
                }
            } else if (response != null) {
                System.debug('QuickBooks API returned status code: ' + response.getStatusCode());
                ErrorLogUtility.logCalloutFailure(
                    'QuickBooks',
                    'QBItemToProductSyncBatch.start',
                    'QuickBooks item query returned HTTP ' + response.getStatusCode() + ': ' + response.getBody(),
                    response.getStatusCode(),
                    null,
                    null
                );
            }
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
        
        return itemIdsList;
    }
    
    public void execute(Database.BatchableContext bc, List<String> scope) {
        IntegrationUsageService.assertCanConsumeTask('QuickBooks', scope == null ? 1 : scope.size());
        QBTriggerHandler.isProductProcessing = true;

        try {
            List<Product2> productsToUpsert = new List<Product2>();
            
            for (String itemId : scope) {
                try {
                    HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', '/item/' + itemId, null);
                    
                    if (response.getStatusCode() == 200) {
                        Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                        Map<String, Object> itemData = (Map<String, Object>)responseMap.get('Item');
                        
                        if (itemData != null) {
                            Product2 productToSync = processItemData(itemData);
                            if (productToSync != null) {
                                productsToUpsert.add(productToSync);
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
}