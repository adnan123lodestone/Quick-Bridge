public class QBProductService {
    public static void syncProductsToQuickBooks(List<Product2> products, Boolean isInsert) {
        List<Product2> productsToUpdate = new List<Product2>();
        Map<Id, Product2> hydratedProductsById = hydrateProducts(products);

        for (Product2 prod : products) {
            Product2 sourceProd = prod != null && prod.Id != null && hydratedProductsById.containsKey(prod.Id)
                ? hydratedProductsById.get(prod.Id)
                : prod;
            try {
                // Safe way to get QB ID
                String qbId = null;
                try { qbId = (String)sourceProd.get('QuickbookID__c'); } catch(Exception e){}
                if(qbId == null) {
                    try { qbId = (String)sourceProd.get('QuickBridgeTLG__QuickbookID__c'); } catch(Exception e){}
                }

                if (isInsert || qbId == null) {
                    // Create new item in QuickBooks
                    String qbItemId = createItemInQuickBooks(sourceProd);

                    if (qbItemId != null) {
                        Product2 prodToUpdate = new Product2(Id = sourceProd.Id);
                        try { prodToUpdate.put('QuickbookID__c', qbItemId); } catch(Exception e){}
                        try { prodToUpdate.put('QuickBridgeTLG__QuickbookID__c', qbItemId); } catch(Exception e){}
                        productsToUpdate.add(prodToUpdate);
                    }
                } else {
                    // Update existing item in QuickBooks
                    updateItemInQuickBooks(sourceProd, qbId);
                }
            } catch (Exception e) {
                System.debug('Error syncing product ID ' + (sourceProd == null ? null : sourceProd.Id) + ': ' + e.getMessage());
                ErrorLogUtility.logException(
                    'QuickBooks',
                    'QBProductService.syncProductsToQuickBooks',
                    e,
                    'Product2',
                    sourceProd == null ? null : sourceProd.Id
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
        ensureRequiredItemFields(itemMap, prod);

        String requestBody = JSON.serialize(itemMap);
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/item', requestBody);

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
        HttpResponse queryRes = QuickBooksAuthHandler.makeApiCall('GET', '/item/' + qbId, null);

        if (queryRes != null && queryRes.getStatusCode() == 200) {
            Map<String, Object> existingItem = (Map<String, Object>)JSON.deserializeUntyped(queryRes.getBody());
            Map<String, Object> itemMap = (Map<String, Object>)existingItem.get('Item');

            Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();

            // DYNAMIC MAPPING LOGIC
            applyDynamicMappings(itemMap, prod, fieldMap);
            ensureRequiredItemFields(itemMap, prod);

            itemMap.put('sparse', false);

            String requestBody = JSON.serialize(itemMap);
            HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/item', requestBody);
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

    private static Map<Id, Product2> hydrateProducts(List<Product2> products) {
        Map<Id, Product2> hydratedById = new Map<Id, Product2>();
        if (products == null || products.isEmpty()) {
            return hydratedById;
        }

        Set<Id> productIds = new Set<Id>();
        for (Product2 prod : products) {
            if (prod != null && prod.Id != null) {
                productIds.add(prod.Id);
            }
        }

        if (productIds.isEmpty()) {
            return hydratedById;
        }

        Set<String> fieldsToQuery = new Set<String>{
            'Id', 'Name', 'IsActive', 'QuickbookID__c',
            'Income_Account__c', 'Expense_Account__c',
            'COGS_Account_Ref__c', 'Asset_Account_Ref__c',
            'Quantity_On_Hand__c', 'Cost_Price__c'
        };

        Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();
        if (fieldMap != null) {
            fieldsToQuery.addAll(fieldMap.keySet());
        }

        String query = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ')
            + ' FROM Product2 WHERE Id IN :productIds';

        for (Product2 prod : Database.query(query)) {
            hydratedById.put(prod.Id, prod);
        }

        return hydratedById;
    }

    private static void ensureRequiredItemFields(Map<String, Object> itemMap, Product2 prod) {
        if (itemMap == null) {
            return;
        }

        if (String.isBlank(asString(itemMap.get('Type')))) {
            itemMap.put('Type', inferItemType(prod));
        }

        ensureAccountRef(itemMap, 'IncomeAccountRef', getIncomeAccountValue(prod), 'Sales of Product Income', '79');

        String itemType = asString(itemMap.get('Type'));
        if (itemType == 'Inventory') {
            ensureAccountRef(itemMap, 'ExpenseAccountRef', getExpenseAccountValue(prod), 'Cost of Goods Sold', '80');
            ensureAccountRef(itemMap, 'AssetAccountRef', getStringFieldValue(prod, 'Asset_Account_Ref__c'), 'Inventory Asset', '81');
        } else if (getAccountRefValue(itemMap, 'IncomeAccountRef') == null && getAccountRefValue(itemMap, 'ExpenseAccountRef') == null) {
            ensureAccountRef(itemMap, 'ExpenseAccountRef', getExpenseAccountValue(prod), 'Cost of Goods Sold', '80');
        }
    }

    private static void ensureAccountRef(
        Map<String, Object> itemMap,
        String refKey,
        String rawValue,
        String defaultName,
        String defaultValue
    ) {
        if (itemMap == null || String.isBlank(refKey)) {
            return;
        }

        Map<String, Object> accountRef = asMap(itemMap.get(refKey));
        if (accountRef == null) {
            accountRef = new Map<String, Object>();
        }

        if (String.isNotBlank(asString(accountRef.get('value')))) {
            itemMap.put(refKey, accountRef);
            return;
        }

        if (String.isBlank(rawValue)) {
            rawValue = defaultValue;
        }

        if (String.isBlank(asString(accountRef.get('name'))) && String.isNotBlank(defaultName)) {
            accountRef.put('name', defaultName);
        }

        if (String.isNotBlank(rawValue)) {
            if (looksLikeQuickBooksReferenceId(rawValue)) {
                accountRef.put('value', rawValue);
            } else if (String.isNotBlank(defaultValue)) {
                accountRef.put('value', defaultValue);
                accountRef.put('name', rawValue);
            }
        }

        if (String.isBlank(asString(accountRef.get('value'))) && String.isNotBlank(defaultValue)) {
            accountRef.put('value', defaultValue);
        }

        itemMap.put(refKey, accountRef);
    }

    private static String getIncomeAccountValue(Product2 prod) {
        return getStringFieldValue(prod, 'Income_Account__c');
    }

    private static String getExpenseAccountValue(Product2 prod) {
        String explicitExpense = getStringFieldValue(prod, 'Expense_Account__c');
        if (looksLikeQuickBooksReferenceId(explicitExpense)) {
            return explicitExpense;
        }

        String cogsExpense = getStringFieldValue(prod, 'COGS_Account_Ref__c');
        if (String.isNotBlank(cogsExpense)) {
            return cogsExpense;
        }

        return explicitExpense;
    }

    private static String inferItemType(Product2 prod) {
        if (String.isNotBlank(getStringFieldValue(prod, 'Asset_Account_Ref__c')) ||
            String.isNotBlank(getStringFieldValue(prod, 'COGS_Account_Ref__c')) ||
            getDecimalFieldValue(prod, 'Quantity_On_Hand__c') != null ||
            getDecimalFieldValue(prod, 'Cost_Price__c') != null) {
            return 'Inventory';
        }
        return 'NonInventory';
    }

    private static String getAccountRefValue(Map<String, Object> itemMap, String refKey) {
        Map<String, Object> accountRef = itemMap == null ? null : asMap(itemMap.get(refKey));
        if (accountRef == null) {
            return null;
        }
        return asString(accountRef.get('value'));
    }

    private static String getStringFieldValue(SObject record, String fieldName) {
        try {
            Object value = record.get(fieldName);
            return value == null ? null : String.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal getDecimalFieldValue(SObject record, String fieldName) {
        try {
            Object value = record.get(fieldName);
            return value instanceof Decimal ? (Decimal)value : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Map<String, Object> asMap(Object value) {
        try {
            return (Map<String, Object>)value;
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean looksLikeQuickBooksReferenceId(String value) {
        return String.isNotBlank(value) && Pattern.matches('^[0-9]+$', value.trim());
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