public class QBProductService {
    private class QBProductServiceException extends Exception {}

    public static void syncProductsToQuickBooks(List<Product2> products, Boolean isInsert) {
        syncProductsToQuickBooksShared(products, isInsert);
    }

    public static ConnectorExecutionResult syncProductsToQuickBooksShared(List<Product2> products, Boolean isInsert) {
        ConnectorExecutionResult result = ConnectorExecutionResult.success();
        result.processedCount = products == null ? 0 : products.size();
        List<Product2> productsToUpdate = new List<Product2>();
        Map<Id, Id> sourceIdByPendingUpdateId = new Map<Id, Id>();
        Map<Id, Product2> hydratedProductsById = hydrateProducts(products);
        Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();

        for (Product2 prod : products) {
            Product2 sourceProd = prod != null && prod.Id != null && hydratedProductsById.containsKey(prod.Id)
                ? hydratedProductsById.get(prod.Id)
                : prod;
            try {
                String qbId = getProductQbIdValue(sourceProd);

                if (isInsert || qbId == null) {
                    // Create new item in QuickBooks
                    String qbItemId = createItemInQuickBooks(sourceProd, fieldMap);

                    if (qbItemId != null) {
                        Product2 prodToUpdate = new Product2(Id = sourceProd.Id);
                        setProductQbIdValue(prodToUpdate, qbItemId);
                        productsToUpdate.add(prodToUpdate);
                        sourceIdByPendingUpdateId.put(prodToUpdate.Id, sourceProd.Id);
                    }
                } else {
                    // Update existing item in QuickBooks
                    updateItemInQuickBooks(sourceProd, qbId, fieldMap);
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
                recordSharedFailure(result, sourceProd == null ? null : sourceProd.Id, e);
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
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (updateResults[i].isSuccess()) {
                    result.successfulCount++;
                } else {
                    Database.Error firstError = updateResults[i].getErrors()[0];
                    recordSharedFailure(
                        result,
                        sourceIdByPendingUpdateId.get(productsToUpdate[i].Id),
                        new QBProductServiceException(firstError.getStatusCode() + ': ' + firstError.getMessage())
                    );
                }
            }
        }
        result.successfulCount += result.processedCount - result.failedCount - result.successfulCount;
        return result;
    }

    private static void recordSharedFailure(
        ConnectorExecutionResult result,
        Id recordId,
        Exception exceptionValue
    ) {
        result.failedCount++;
        result.addError(exceptionValue == null ? null : exceptionValue.getMessage());
        if (IntegrationRetryPolicy.isRetryable(exceptionValue)) {
            result.retryable = true;
            result.retryDelaySeconds = 60;
            if (recordId != null) {
                result.retryRecordIds.add(recordId);
            }
        }
    }

    private static String createItemInQuickBooks(Product2 prod) {
        return createItemInQuickBooks(prod, QBObjectMappings.getProductToItemMapping());
    }

    private static String createItemInQuickBooks(Product2 prod, Map<String, String> fieldMap) {
        Map<String, Object> itemMap = new Map<String, Object>();
        if (fieldMap == null) {
            fieldMap = QBObjectMappings.getProductToItemMapping();
        }

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
            throw IntegrationRetryPolicy.exceptionForStatus(
                res == null ? null : res.getStatusCode(),
                'QuickBooks item create failed: ' + (res != null ? res.getBody() : 'Null Response')
            );
        }
    }

    private static void updateItemInQuickBooks(Product2 prod, String qbId) {
        updateItemInQuickBooks(prod, qbId, QBObjectMappings.getProductToItemMapping());
    }

    private static void updateItemInQuickBooks(Product2 prod, String qbId, Map<String, String> fieldMap) {
        HttpResponse queryRes = QuickBooksAuthHandler.makeApiCall('GET', '/item/' + qbId, null);

        if (queryRes != null && queryRes.getStatusCode() == 200) {
            Map<String, Object> existingItem = (Map<String, Object>)JSON.deserializeUntyped(queryRes.getBody());
            Map<String, Object> itemMap = (Map<String, Object>)existingItem.get('Item');

            if (fieldMap == null) {
                fieldMap = QBObjectMappings.getProductToItemMapping();
            }

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
                throw IntegrationRetryPolicy.exceptionForStatus(
                    updateRes.getStatusCode(),
                    'QuickBooks item update failed: ' + updateRes.getBody()
                );
            }
        } else {
            throw IntegrationRetryPolicy.exceptionForStatus(
                queryRes == null ? null : queryRes.getStatusCode(),
                'QuickBooks item query failed: ' + (queryRes == null ? 'Null Response' : queryRes.getBody())
            );
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
            'Id', 'Name', 'IsActive',
            'Income_Account__c', 'Expense_Account__c',
            'COGS_Account_Ref__c', 'Asset_Account_Ref__c',
            'Quantity_On_Hand__c', 'Cost_Price__c'
        };

        Map<String, Schema.SObjectField> fMap = Schema.SObjectType.Product2.fields.getMap();
        Set<String> safeFields = new Set<String>();
        for (String f : fieldsToQuery) {
            if (fMap.containsKey(f.toLowerCase())) {
                safeFields.add(fMap.get(f.toLowerCase()).getDescribe().getName());
            }
            if (fMap.containsKey(('QuickBridgeTLG__' + f).toLowerCase())) {
                safeFields.add(fMap.get(('QuickBridgeTLG__' + f).toLowerCase()).getDescribe().getName());
            }
        }

        for (String key : fMap.keySet()) {
            if (key.endsWith('quickbookid__c')) {
                safeFields.add(fMap.get(key).getDescribe().getName());
            }
        }

        Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();
        if (fieldMap != null) {
            for (String sfField : fieldMap.keySet()) {
                if (fMap.containsKey(sfField.toLowerCase())) {
                    safeFields.add(fMap.get(sfField.toLowerCase()).getDescribe().getName());
                }
            }
        }

        String query = 'SELECT ' + String.join(new List<String>(safeFields), ', ')
            + ' FROM Product2 WHERE Id IN :productIds';

        for (Product2 prod : Database.query(query)) {
            hydratedById.put(prod.Id, prod);
        }

        return hydratedById;
    }

    private static String getProductQbIdValue(Product2 prod) {
        if (prod == null) return null;
        try {
            String val = (String)prod.get('QuickbookID__c');
            if (String.isNotBlank(val)) return val;
        } catch (Exception e) {}
        try {
            String val = (String)prod.get('QuickBridgeTLG__QuickbookID__c');
            if (String.isNotBlank(val)) return val;
        } catch (Exception e) {}
        return null;
    }

    private static void setProductQbIdValue(Product2 prod, String qbId) {
        if (prod == null || String.isBlank(qbId)) return;
        try { prod.put('QuickbookID__c', qbId); } catch(Exception e){}
        try { prod.put('QuickBridgeTLG__QuickbookID__c', qbId); } catch(Exception e){}
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

    private static Object getSObjectFieldValue(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) return null;
        try {
            Object val = record.get(fieldName);
            if (val != null) return val;
        } catch (Exception e) {}
        try {
            Object val = record.get('QuickBridgeTLG__' + fieldName);
            if (val != null) return val;
        } catch (Exception e) {}
        return null;
    }

    private static String getStringFieldValue(SObject record, String fieldName) {
        Object val = getSObjectFieldValue(record, fieldName);
        return val == null ? null : String.valueOf(val);
    }

    private static Decimal getDecimalFieldValue(SObject record, String fieldName) {
        Object val = getSObjectFieldValue(record, fieldName);
        return val instanceof Decimal ? (Decimal)val : (val instanceof Integer ? Decimal.valueOf((Integer)val) : null);
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
            Object value = getSObjectFieldValue(record, sfField);

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
