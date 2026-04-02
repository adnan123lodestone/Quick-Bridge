public class QBItemToProductSyncBatch implements Database.Batchable<String>, Database.AllowsCallouts {
    
    private String lastSyncDate;
    
public QBItemToProductSyncBatch() {
    // Set lastSyncDate to yesterday's date in 'YYYY-MM-DD' format
    Datetime yesterday = Datetime.now().addDays(-1);
    this.lastSyncDate = yesterday.format('YYYY-MM-dd');
}
    
public QBItemToProductSyncBatch(String syncDate) {
    this.lastSyncDate = syncDate;
}
    
public Iterable<String> start(Database.BatchableContext bc) {
    List<String> itemIdsList = new List<String>();
    
    try {
        // Construct the query
        String query = 'select * from Item Where Metadata.LastUpdatedTime > \'' + lastSyncDate + '\'';
        
        // URL encode the query and construct the full resource path
        String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
        String resourcePath = '/query?query=' + encodedQuery + '&minorversion=65';
        
        // Make the API call
        HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', resourcePath, null);
        // Process the response
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
            System.debug('Response body: ' + response.getBody());
        }
    } catch (Exception e) {
        System.debug('Error querying QuickBooks items: ' + e.getMessage());
        System.debug('Stack trace: ' + e.getStackTraceString());
    }
    
    return itemIdsList;
}
    
    public void execute(Database.BatchableContext bc, List<String> scope) {
        QBTriggerHandler.isProductProcessing = true;
        
        try {
              List<Product2> productsToUpsert = new List<Product2>();
        List<PricebookEntry> pricebookEntriesToUpsert = new List<PricebookEntry>();
            
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
                }
            }
            
            if (!productsToUpsert.isEmpty()) {
                Database.UpsertResult[] results = Database.upsert(productsToUpsert, Product2.QuickbookID__c, false);
                
               Id standardPricebookId;
            try {
                standardPricebookId = Test.isRunningTest() ? Test.getStandardPricebookId() : 
                    [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            } catch (Exception e) {
                System.debug('Error getting standard pricebook: ' + e.getMessage());
                return;
            }

            // First query existing pricebook entries to avoid duplicates
            Set<Id> productIds = new Set<Id>();
            for (Database.UpsertResult result : results) {
                if (result.isSuccess()) {
                    productIds.add(result.getId());
                }
            }
            
            Map<Id, PricebookEntry> existingEntries = new Map<Id, PricebookEntry>();
            for (PricebookEntry pbe : [
                SELECT Id, Product2Id, UnitPrice 
                FROM PricebookEntry 
                WHERE Product2Id IN :productIds 
                AND Pricebook2Id = :standardPricebookId
            ]) {
                existingEntries.put(pbe.Product2Id, pbe);
            }

            // Prepare pricebook entries for upsert
            List<PricebookEntry> pricebookEntries = new List<PricebookEntry>();
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    Product2 product = productsToUpsert[i];
                    Id productId = results[i].getId();
                    
                    // Skip if no price or product already has an entry
                    if (product.Unit_Price__c == null || existingEntries.containsKey(productId)) {
                        continue;
                    }
                    
                    PricebookEntry pbe = new PricebookEntry();
                    pbe.Product2Id = productId;
                    pbe.Pricebook2Id = standardPricebookId;
                    pbe.UnitPrice = product.Unit_Price__c;
                    pbe.IsActive = true;
                    pricebookEntries.add(pbe);
                }
            }
            
            // Insert new pricebook entries
            if (!pricebookEntries.isEmpty()) {
                try {
                    insert pricebookEntries;
                } catch (Exception e) {
                    System.debug('Error inserting pricebook entries: ' + e.getMessage());
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
        
        List<Product2> existingProducts = [SELECT Id, QuickbookID__c, Unit_Price__c 
                                          FROM Product2 
                                          WHERE QuickbookID__c = :qbId LIMIT 1];
        
        Product2 product;
        if (!existingProducts.isEmpty()) {
            product = existingProducts[0];
        } else {
            product = new Product2();
            product.QuickbookID__c = qbId;
        }
        
        // Handle standard fields
        product.Name = (String)itemData.get('Name');
        product.Description = (String)itemData.get('Description');
        product.ProductCode = (String)itemData.get('Sku');
        product.IsActive = (Boolean)itemData.get('Active');
        
        // Explicitly handle UnitPrice
        if (itemData.containsKey('UnitPrice')) {
            try {
                product.Unit_Price__c = Decimal.valueOf(String.valueOf(itemData.get('UnitPrice')));
            } catch (Exception e) {
                System.debug('Error parsing UnitPrice: ' + e.getMessage());
            }
        }
        
        // Handle quantity fields if needed
        if (itemData.containsKey('QtyOnHand')) {
            try {
                product.QtyOnHand__c = Decimal.valueOf(String.valueOf(itemData.get('QtyOnHand')));
            } catch (Exception e) {
                System.debug('Error parsing QtyOnHand: ' + e.getMessage());
            }
        }
        
        return product;
    }
    private Object getNestedValue(Map<String, Object> data, String fieldPath) {
    String[] fields = fieldPath.split('\\.');
    Object current = data;
    
    for (String field : fields) {
        if (current instanceof Map<String, Object>) {
            current = ((Map<String, Object>)current).get(field);
        } else {
            return null;
        }
    }
    return current;
}
}