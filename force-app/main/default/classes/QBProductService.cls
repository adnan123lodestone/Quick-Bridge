public class QBProductService {
    public static void syncProductsToQuickBooks(List<Product2> products, Boolean isInsert) {
        List<Product2> productsToUpdate = new List<Product2>();

        for (Product2 prod : products) {
            try {
                // Safe way to get QB ID
                String qbId = null;
                try { qbId = (String)prod.get('QuickbookID__c'); } catch(Exception e){}
                if(qbId == null) {
                    try { qbId = (String)prod.get('QuickBridgeTLG__QuickbookID__c'); } catch(Exception e){}
                }

                if (isInsert || qbId == null) {
                    // Create new item in QuickBooks
                    String qbItemId = createItemInQuickBooks(prod);

                    if (qbItemId != null) {
                        Product2 prodToUpdate = new Product2(Id = prod.Id);
                        try { prodToUpdate.put('QuickbookID__c', qbItemId); } catch(Exception e){}
                        try { prodToUpdate.put('QuickBridgeTLG__QuickbookID__c', qbItemId); } catch(Exception e){}
                        productsToUpdate.add(prodToUpdate);
                    }
                } else {
                    // Update existing item in QuickBooks
                    updateItemInQuickBooks(prod, qbId);
                }
            } catch (Exception e) {
                System.debug('Error syncing product ID ' + prod.Id + ': ' + e.getMessage());
                ErrorLogUtility.logException(
                    'QuickBooks',
                    'QBProductService.syncProductsToQuickBooks',
                    e,
                    'Product2',
                    prod == null ? null : prod.Id
                );
            }
        }

        if (!productsToUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(productsToUpdate, false);
            ErrorLogUtility.logDmlResults(
                'QuickBooks',
                'QBProductService.syncProductsToQuickBooks.updateProductIds',
                'update',
                productsToUpdate,
                updateResults,
                null,
                null
            );
        }
    }

    private static String createItemInQuickBooks(Product2 prod) {
        Map<String, Object> itemMap = new Map<String, Object>();
        Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();

        // DYNAMIC MAPPING LOGIC
        applyDynamicMappings(itemMap, prod, fieldMap);

        String requestBody = JSON.serialize(itemMap);
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/item?minorversion=65', requestBody);

        if (res != null && res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            Map<String, Object> itemResponse = (Map<String, Object>)responseMap.get('Item');
            return (String)itemResponse.get('Id');
        } else {
            System.debug('Create Error: ' + (res != null ? res.getBody() : 'Null Response'));
            ErrorLogUtility.logCalloutFailure(
                'QuickBooks',
                'QBProductService.createItemInQuickBooks',
                'QuickBooks item create failed: ' + (res != null ? res.getBody() : 'Null Response'),
                res == null ? null : res.getStatusCode(),
                'Product2',
                prod == null ? null : prod.Id
            );
            return null;
        }
    }

    private static void updateItemInQuickBooks(Product2 prod, String qbId) {
        HttpResponse queryRes = QuickBooksAuthHandler.makeApiCall('GET', '/item/' + qbId + '?minorversion=65', null);

        if (queryRes != null && queryRes.getStatusCode() == 200) {
            Map<String, Object> existingItem = (Map<String, Object>)JSON.deserializeUntyped(queryRes.getBody());
            Map<String, Object> itemMap = (Map<String, Object>)existingItem.get('Item');

            Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();

            // DYNAMIC MAPPING LOGIC
            applyDynamicMappings(itemMap, prod, fieldMap);

            itemMap.put('sparse', false);

            String requestBody = JSON.serialize(itemMap);
            HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/item?minorversion=65', requestBody);
            if(updateRes != null && updateRes.getStatusCode() != 200) {
                System.debug('Update Error: ' + updateRes.getBody());
                ErrorLogUtility.logCalloutFailure(
                    'QuickBooks',
                    'QBProductService.updateItemInQuickBooks',
                    'QuickBooks item update failed: ' + updateRes.getBody(),
                    updateRes.getStatusCode(),
                    'Product2',
                    prod == null ? null : prod.Id
                );
            }
        }
    }

    private static void applyDynamicMappings(Map<String, Object> requestBody, SObject record, Map<String, String> fieldMap) {
        if(fieldMap == null) return;
        for (String sfField : fieldMap.keySet()) {
            String qbField = fieldMap.get(sfField);
            Object value = null;
            try { value = record.get(sfField); } catch(Exception e) {}

            if (value != null) {
                if (qbField.contains('.')) {
                    List<String> path = qbField.split('\\.');
                    Map<String, Object> currentMap = requestBody;
                    for (Integer i = 0; i < path.size() - 1; i++) {
                        String part = path[i];
                        if (!currentMap.containsKey(part)) currentMap.put(part, new Map<String, Object>());
                        currentMap = (Map<String, Object>)currentMap.get(part);
                    }
                    currentMap.put(path[path.size() - 1], value);
                } else {
                    requestBody.put(qbField, value);
                }
            }
        }
    }
}
// public class QBProductService {
//     public static void syncProductsToQuickBooks(List<Product2> products, Boolean isInsert) {
//         List<Product2> productsToUpdate = new List<Product2>();

//         for (Product2 prod : products) {
//             try {
//                 if (isInsert || prod.QuickbookID__c == null) {
//                     // Create new item in QuickBooks
//                     String qbItemId = createItemInQuickBooks(prod);
//                     productsToUpdate.add(new Product2(
//                         Id = prod.Id,
//                         QuickbookID__c = qbItemId
//                     ));
//                 } else {
//                     // Update existing item in QuickBooks
//                     updateItemInQuickBooks(prod);
//                 }
//             } catch (Exception e) {
//                 System.debug('Error syncing product ID ' + prod.Id + ': ' + e.getMessage());
//                 System.debug(e.getStackTraceString());
//             }
//         }

//         if (!productsToUpdate.isEmpty()) {
//             Database.update(productsToUpdate, false);
//         }
//     }

//     private static String createItemInQuickBooks(Product2 prod) {
//         Map<String, Object> itemMap = new Map<String, Object>();
//         Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();

//         // Map standard fields
//         for (String sfField : fieldMap.keySet()) {
//             String qbField = fieldMap.get(sfField);
//             Object value = prod.get(sfField);

//             if (value != null) {
//                 itemMap.put(qbField, value);
//             }
//         }

//         // Add hardcoded account references
//         Map<String, Object> incomeAccount = new Map<String, Object>();
//         incomeAccount.put('name', 'Sales of Product Income');
//         incomeAccount.put('value', '79');
//         itemMap.put('IncomeAccountRef', incomeAccount);

//         Map<String, Object> assetAccount = new Map<String, Object>();
//         assetAccount.put('name', 'Inventory Asset');
//         assetAccount.put('value', '81');
//         itemMap.put('AssetAccountRef', assetAccount);

//         Map<String, Object> expenseAccount = new Map<String, Object>();
//         expenseAccount.put('name', 'Cost of Goods Sold');
//         expenseAccount.put('value', '80');
//         itemMap.put('ExpenseAccountRef', expenseAccount);

//         // Set default type to Inventory
//         itemMap.put('Type', 'Inventory');

//         String requestBody = JSON.serialize(itemMap);
//         System.debug('Creating item in QuickBooks: ' + requestBody);

//         HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/item', requestBody);

//         if (res.getStatusCode() == 200) {
//             Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
//             Map<String, Object> itemResponse = (Map<String, Object>)responseMap.get('Item');
//             return (String)itemResponse.get('Id');
//         } else {
//             throw new QBIntegrationException('Error creating item in QuickBooks: ' + res.getStatusCode() + ' ' + res.getBody());
//         }
//     }

//     private static void updateItemInQuickBooks(Product2 prod) {
//         // First query the item to get SyncToken
//         HttpResponse queryRes = QuickBooksAuthHandler.makeApiCall('GET', '/item/' + prod.QuickbookID__c, null);

//         if (queryRes.getStatusCode() != 200) {
//             throw new QBIntegrationException('Error querying item in QuickBooks: ' + queryRes.getStatusCode() + ' ' + queryRes.getBody());
//         }

//         Map<String, Object> existingItem = (Map<String, Object>)JSON.deserializeUntyped(queryRes.getBody());
//         Map<String, Object> itemMap = (Map<String, Object>)existingItem.get('Item');

//         // Update fields from Salesforce
//         Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();

//         for (String sfField : fieldMap.keySet()) {
//             String qbField = fieldMap.get(sfField);
//             Object value = prod.get(sfField);

//             if (value != null) {
//                 itemMap.put(qbField, value);
//             }
//         }

//         // Ensure sparse is set to false for full updates
//         itemMap.put('sparse', false);

//         String requestBody = JSON.serialize(itemMap);
//         System.debug('Updating item in QuickBooks: ' + requestBody);

//         HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/item', requestBody);

//         if (updateRes.getStatusCode() != 200) {
//             throw new QBIntegrationException('Error updating item in QuickBooks: ' + updateRes.getStatusCode() + ' ' + updateRes.getBody());
//         }
//     }
// }