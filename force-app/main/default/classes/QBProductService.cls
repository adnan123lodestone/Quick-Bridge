public class QBProductService {
    public static void syncProductsToQuickBooks(List<Product2> products, Boolean isInsert) {
        List<Product2> productsToUpdate = new List<Product2>();
        
        for (Product2 prod : products) {
            try {
                if (isInsert || prod.QuickbookID__c == null) {
                    // Create new item in QuickBooks
                    String qbItemId = createItemInQuickBooks(prod);
                    productsToUpdate.add(new Product2(
                        Id = prod.Id,
                        QuickbookID__c = qbItemId
                    ));
                } else {
                    // Update existing item in QuickBooks
                    updateItemInQuickBooks(prod);
                }
            } catch (Exception e) {
                System.debug('Error syncing product ID ' + prod.Id + ': ' + e.getMessage());
                System.debug(e.getStackTraceString());
            }
        }
        
        if (!productsToUpdate.isEmpty()) {
            Database.update(productsToUpdate, false);
        }
    }
    
    private static String createItemInQuickBooks(Product2 prod) {
        Map<String, Object> itemMap = new Map<String, Object>();
        Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();
        
        // Map standard fields
        for (String sfField : fieldMap.keySet()) {
            String qbField = fieldMap.get(sfField);
            Object value = prod.get(sfField);
            
            if (value != null) {
                itemMap.put(qbField, value);
            }
        }
        
        // Add hardcoded account references
        Map<String, Object> incomeAccount = new Map<String, Object>();
        incomeAccount.put('name', 'Sales of Product Income');
        incomeAccount.put('value', '79');
        itemMap.put('IncomeAccountRef', incomeAccount);
        
        Map<String, Object> assetAccount = new Map<String, Object>();
        assetAccount.put('name', 'Inventory Asset');
        assetAccount.put('value', '81');
        itemMap.put('AssetAccountRef', assetAccount);
        
        Map<String, Object> expenseAccount = new Map<String, Object>();
        expenseAccount.put('name', 'Cost of Goods Sold');
        expenseAccount.put('value', '80');
        itemMap.put('ExpenseAccountRef', expenseAccount);
        
        // Set default type to Inventory
        itemMap.put('Type', 'Inventory');
        
        String requestBody = JSON.serialize(itemMap);
        System.debug('Creating item in QuickBooks: ' + requestBody);
        
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/item', requestBody);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            Map<String, Object> itemResponse = (Map<String, Object>)responseMap.get('Item');
            return (String)itemResponse.get('Id');
        } else {
            throw new QBIntegrationException('Error creating item in QuickBooks: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }
    
    private static void updateItemInQuickBooks(Product2 prod) {
        // First query the item to get SyncToken
        HttpResponse queryRes = QuickBooksAuthHandler.makeApiCall('GET', '/item/' + prod.QuickbookID__c, null);
        
        if (queryRes.getStatusCode() != 200) {
            throw new QBIntegrationException('Error querying item in QuickBooks: ' + queryRes.getStatusCode() + ' ' + queryRes.getBody());
        }
        
        Map<String, Object> existingItem = (Map<String, Object>)JSON.deserializeUntyped(queryRes.getBody());
        Map<String, Object> itemMap = (Map<String, Object>)existingItem.get('Item');
        
        // Update fields from Salesforce
        Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();
        
        for (String sfField : fieldMap.keySet()) {
            String qbField = fieldMap.get(sfField);
            Object value = prod.get(sfField);
            
            if (value != null) {
                itemMap.put(qbField, value);
            }
        }
        
        // Ensure sparse is set to false for full updates
        itemMap.put('sparse', false);
        
        String requestBody = JSON.serialize(itemMap);
        System.debug('Updating item in QuickBooks: ' + requestBody);
        
        HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/item', requestBody);
        
        if (updateRes.getStatusCode() != 200) {
            throw new QBIntegrationException('Error updating item in QuickBooks: ' + updateRes.getStatusCode() + ' ' + updateRes.getBody());
        }
    }
}