public class QBQuoteToEstimateSyncBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {
    private Set<Id> quoteIds;
    private Boolean isInitialSync;

    public static Boolean isProcessing = false;
    private ConnectorExecutionResult sharedExecutionResult;
    private Set<Id> sharedSuccessfulRecordIds = new Set<Id>();
    private Set<Id> sharedFailedRecordIds = new Set<Id>();

    // QBO Estimate server-calculated read-only properties that must not be sent
    private static final Set<String> QBO_READONLY_PROPS = new Set<String>{
        'TotalAmt',
        'Balance',
        'HomeTotalAmt',
        'HomeBalance'
    };

    public QBQuoteToEstimateSyncBatch() {
        this.quoteIds = null;
        this.isInitialSync = false;
    }

    public QBQuoteToEstimateSyncBatch(Set<Id> ids, Boolean isInitial) {
        this.quoteIds = ids;
        this.isInitialSync = isInitial;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = buildQuoteScopeQuery();

        String qbIdField = getQbIdFieldName();

        if (this.quoteIds != null && !this.quoteIds.isEmpty()) {
            query += ' WHERE Id IN :quoteIds';
        } else {
            query += ' WHERE ' + qbIdField + ' = NULL';
        }

        return Database.getQueryLocator(query);
    }

    public static List<Quote> loadQuotesForSharedExecution(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Quote>();
        }
        return (List<Quote>) Database.query(
            buildQuoteScopeQuery() + ' WHERE Id IN :ids'
        );
    }

    public ConnectorExecutionResult executeSharedScope(List<Quote> scope) {
        sharedExecutionResult = ConnectorExecutionResult.success();
        sharedSuccessfulRecordIds.clear();
        sharedFailedRecordIds.clear();
        try {
            execute(null, scope == null ? new List<Quote>() : scope);
        } catch (Exception exceptionValue) {
            for (Quote quoteRecord : scope == null ? new List<Quote>() : scope) {
                recordSharedFailure(
                    quoteRecord == null ? null : quoteRecord.Id,
                    exceptionValue.getMessage(),
                    IntegrationRetryPolicy.isRetryable(exceptionValue) ||
                        IntegrationRetryPolicy.isRetryableMessage(exceptionValue.getMessage())
                );
            }
        }
        sharedExecutionResult.processedCount = scope == null ? 0 : scope.size();
        sharedExecutionResult.failedCount = sharedFailedRecordIds.size();
        sharedSuccessfulRecordIds.removeAll(sharedFailedRecordIds);
        sharedExecutionResult.successfulCount = sharedSuccessfulRecordIds.size();
        ConnectorExecutionResult result = sharedExecutionResult;
        sharedExecutionResult = null;
        return result;
    }

    private static String buildQuoteScopeQuery() {
        String quoteFields = buildQuoteQueryFields();
        String accQbIdField = getAccountQbIdFieldName();
        String prodQbIdField = getProductQbIdFieldName();
        return 'SELECT ' + quoteFields +
            ', AccountId, Account.' + accQbIdField +
            ', OpportunityId, Opportunity.AccountId, Opportunity.Account.' + accQbIdField +
            ', (SELECT Id, Quantity, UnitPrice, Description, TotalPrice' +
            ', PricebookEntryId, PricebookEntry.Product2Id, PricebookEntry.Product2.' + prodQbIdField + ', PricebookEntry.Product2.Name' +
            buildQuoteLineItemQueryFields() +
            ' FROM QuoteLineItems)' +
            ' FROM Quote';
    }

    private static String getQbIdFieldName() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Quote.fields.getMap();
        if (!schemaFields.containsKey('quickbookid__c') && schemaFields.containsKey('quickbridgetlg__quickbookid__c')) {
            return 'QuickBridgeTLG__QuickbookID__c';
        }
        return 'QuickbookID__c';
    }

    private static String getAccountQbIdFieldName() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Account.fields.getMap();
        if (!schemaFields.containsKey('quickbookid__c') && schemaFields.containsKey('quickbridgetlg__quickbookid__c')) {
            return 'QuickBridgeTLG__QuickbookID__c';
        }
        return 'QuickbookID__c';
    }

    private static String getProductQbIdFieldName() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Product2.fields.getMap();
        if (!schemaFields.containsKey('quickbookid__c') && schemaFields.containsKey('quickbridgetlg__quickbookid__c')) {
            return 'QuickBridgeTLG__QuickbookID__c';
        }
        return 'QuickbookID__c';
    }

    public static String buildQuoteQueryFields() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Quote.fields.getMap();
        Set<String> names = new Set<String>{ 'Id', 'Name', 'ExpirationDate', 'Description', 'QuickbookID__c', 'SyncToken__c' };
        for (String sfField : QBObjectMappings.getQuoteMapping().keySet()) {
            if (!sfField.contains('.')) {
                names.add(sfField);
            }
        }
        Set<String> resolved = new Set<String>();
        for (String f : names) {
            String key = f.toLowerCase();
            if (schemaFields.containsKey(key)) resolved.add(schemaFields.get(key).getDescribe().getName());
            if (schemaFields.containsKey('quickbridgetlg__' + key)) resolved.add(schemaFields.get('quickbridgetlg__' + key).getDescribe().getName());
        }
        return String.join(new List<String>(resolved), ', ');
    }

    public static String buildQuoteLineItemQueryFields() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.QuoteLineItem.fields.getMap();
        Set<String> extra = new Set<String>();
        for (String sfField : QBObjectMappings.getQuoteLineItemMapping().keySet()) {
            if (!sfField.contains('.')) {
                extra.add(sfField);
            }
        }
        Set<String> base = new Set<String>{ 'id', 'quantity', 'unitprice', 'description', 'totalprice', 'pricebookentryid' };
        List<String> additional = new List<String>();
        for (String f : extra) {
            if (!base.contains(f.toLowerCase())) {
                String key = f.toLowerCase();
                if (schemaFields.containsKey(key)) additional.add(', ' + schemaFields.get(key).getDescribe().getName());
                if (schemaFields.containsKey('quickbridgetlg__' + key)) additional.add(', ' + schemaFields.get('quickbridgetlg__' + key).getDescribe().getName());
            }
        }
        return String.join(additional, '');
    }

    public void execute(Database.BatchableContext bc, List<Quote> scope) {
        isProcessing = true;
        QBTriggerHandler.isQuoteProcessing = true;

        try {
            // Collect parent account IDs with fallback query
            Set<Id> parentAccountIds = new Set<Id>();
            Map<Id, Id> quoteToAccountIdMap = new Map<Id, Id>();

            Set<Id> oppIdsToQuery = new Set<Id>();
            for (Quote q : scope) {
                if (q.AccountId != null) {
                    quoteToAccountIdMap.put(q.Id, q.AccountId);
                    parentAccountIds.add(q.AccountId);
                } else if (q.OpportunityId != null) {
                    try {
                        if (q.Opportunity != null && q.Opportunity.AccountId != null) {
                            quoteToAccountIdMap.put(q.Id, q.Opportunity.AccountId);
                            parentAccountIds.add(q.Opportunity.AccountId);
                        } else {
                            oppIdsToQuery.add(q.OpportunityId);
                        }
                    } catch (Exception e) {
                        oppIdsToQuery.add(q.OpportunityId);
                    }
                }
            }

            if (!oppIdsToQuery.isEmpty()) {
                Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
                    SELECT Id, AccountId FROM Opportunity WHERE Id IN :oppIdsToQuery
                ]);
                for (Quote q : scope) {
                    if (!quoteToAccountIdMap.containsKey(q.Id) && q.OpportunityId != null && oppMap.containsKey(q.OpportunityId)) {
                        Id aId = oppMap.get(q.OpportunityId).AccountId;
                        if (aId != null) {
                            quoteToAccountIdMap.put(q.Id, aId);
                            parentAccountIds.add(aId);
                        }
                    }
                }
            }

            // Query existing Accounts upfront
            Map<Id, Account> refreshedAccounts = new Map<Id, Account>();
            if (!parentAccountIds.isEmpty()) {
                String accQueryFields = buildAccountQueryFields();
                refreshedAccounts = new Map<Id, Account>((List<Account>) Database.query(
                    'SELECT ' + accQueryFields + ' FROM Account WHERE Id IN :parentAccountIds'
                ));
            }

            // Identify missing parent Accounts
            Map<Id, Account> accountsToSyncMap = new Map<Id, Account>();
            for (Quote q : scope) {
                Id accId = quoteToAccountIdMap.get(q.Id);
                if (accId != null && refreshedAccounts.containsKey(accId)) {
                    Account accObj = refreshedAccounts.get(accId);
                    String qbId = (String) getSObjectField(accObj, 'QuickbookID__c');
                    if (String.isBlank(qbId)) {
                        accountsToSyncMap.put(accId, accObj);
                    }
                }
            }

            // Auto-sync missing parent Accounts if any
            if (!accountsToSyncMap.isEmpty()) {
                for (Account acc : accountsToSyncMap.values()) {
                    try {
                        QBAccountService.syncAccountToQuickBooks(acc, true);
                    } catch (Exception ex) {
                        ErrorLogUtility.logException('QuickBooks', 'QBQuoteToEstimateSyncBatch.execute.syncAccounts', ex, 'Account', acc.Id);
                    }
                }
                // Refresh updated Account QBO IDs
                String accQueryFields = buildAccountQueryFields();
                refreshedAccounts = new Map<Id, Account>((List<Account>) Database.query(
                    'SELECT ' + accQueryFields + ' FROM Account WHERE Id IN :parentAccountIds'
                ));
            }

            // 2. Bulk sync missing child Products
            Set<Id> productIdsToSync = new Set<Id>();
            for (Quote q : scope) {
                if (q.QuoteLineItems != null) {
                    for (QuoteLineItem qli : q.QuoteLineItems) {
                        if (qli.PricebookEntry != null && qli.PricebookEntry.Product2Id != null) {
                            String prodQbId = (String) getSObjectField(qli.PricebookEntry.Product2, 'QuickbookID__c');
                            if (String.isBlank(prodQbId)) {
                                productIdsToSync.add(qli.PricebookEntry.Product2Id);
                            }
                        }
                    }
                }
            }

            if (!productIdsToSync.isEmpty()) {
                List<Product2> unsyncedProducts = [
                    SELECT Id, Name, Description, ProductCode, QuickbookID__c, IsActive FROM Product2 WHERE Id IN :productIdsToSync
                ];
                try {
                    QBProductService.syncProductsToQuickBooks(unsyncedProducts, true);
                } catch (Exception ex) {
                    ErrorLogUtility.logException('QuickBooks', 'QBQuoteToEstimateSyncBatch.execute.syncProducts', ex, 'Product2', null);
                }
            }

            Map<Id, Product2> refreshedProducts = new Map<Id, Product2>([
                SELECT Id, QuickbookID__c FROM Product2 WHERE Id IN :productIdsToSync
            ]);

            // 3. Process each Quote -> QBO Estimate POST
            List<Quote> quotesToUpdate = new List<Quote>();

            for (Quote quoteRecord : scope) {
                try {
                    Id accId = quoteToAccountIdMap.get(quoteRecord.Id);
                    String customerQbId = null;
                    if (accId != null && refreshedAccounts.containsKey(accId)) {
                        customerQbId = (String) getSObjectField(refreshedAccounts.get(accId), 'QuickbookID__c');
                    }
                    if (String.isBlank(customerQbId) && quoteRecord.Account != null) {
                        customerQbId = (String) getSObjectField(quoteRecord.Account, 'QuickbookID__c');
                    }

                    if (String.isBlank(customerQbId)) {
                        ErrorLogUtility.logCalloutFailure('QuickBooks', 'QBQuoteToEstimateSyncBatch.execute', 'Parent Account has no QuickbookID__c for Quote ' + quoteRecord.Id, 400, 'Quote', quoteRecord.Id);
                        recordSharedFailure(quoteRecord.Id, 'Parent Account has no QuickbookID__c for Quote ' + quoteRecord.Id, false);
                        continue;
                    }

                    // Build Estimate Payload
                    Map<String, Object> payloadMap = new Map<String, Object>();

                    // Header Fields
                    Map<String, String> headerMap = QBObjectMappings.getQuoteMapping();
                    for (String sfField : headerMap.keySet()) {
                        String qboField = headerMap.get(sfField);
                        if (QBO_READONLY_PROPS.contains(qboField)) continue;
                        Object val = getFieldValue(quoteRecord, sfField);
                        if (val != null) {
                            if (val instanceof Date) {
                                val = String.valueOf((Date) val);
                            } else if (val instanceof Datetime) {
                                val = ((Datetime) val).format('yyyy-MM-dd');
                            }
                            putPath(payloadMap, qboField, val);
                        }
                    }

                    // Mandatory CustomerRef
                    payloadMap.put('CustomerRef', new Map<String, Object>{ 'value' => customerQbId });

                    // Handle Update vs Create
                    String qboId = (String) getSObjectField(quoteRecord, 'QuickbookID__c');
                    String syncToken = (String) getSObjectField(quoteRecord, 'SyncToken__c');
                    if (String.isNotBlank(qboId)) {
                        payloadMap.put('Id', qboId);
                        payloadMap.put('SyncToken', String.isNotBlank(syncToken) ? syncToken : '0');
                    }

                    // Line Items
                    List<Map<String, Object>> linesJson = new List<Map<String, Object>>();
                    Map<String, String> lineItemMapping = QBObjectMappings.getQuoteLineItemMapping();

                    if (quoteRecord.QuoteLineItems != null && !quoteRecord.QuoteLineItems.isEmpty()) {
                        for (QuoteLineItem qli : quoteRecord.QuoteLineItems) {
                            Map<String, Object> lineObj = new Map<String, Object>();
                            lineObj.put('DetailType', 'SalesItemLineDetail');

                            Map<String, Object> salesDetail = new Map<String, Object>();
                            if (qli.PricebookEntry != null && qli.PricebookEntry.Product2Id != null) {
                                String prodQbId = refreshedProducts.containsKey(qli.PricebookEntry.Product2Id) ? (String) getSObjectField(refreshedProducts.get(qli.PricebookEntry.Product2Id), 'QuickbookID__c') : (String) getSObjectField(qli.PricebookEntry.Product2, 'QuickbookID__c');
                                if (String.isNotBlank(prodQbId)) {
                                    salesDetail.put('ItemRef', new Map<String, Object>{ 'value' => prodQbId });
                                }
                            }

                            if (qli.UnitPrice != null) salesDetail.put('UnitPrice', qli.UnitPrice);
                            if (qli.Quantity != null) salesDetail.put('Qty', qli.Quantity);

                            lineObj.put('SalesItemLineDetail', salesDetail);
                            if (qli.Quantity != null && qli.UnitPrice != null) {
                                lineObj.put('Amount', qli.Quantity * qli.UnitPrice);
                            } else if (qli.TotalPrice != null) {
                                lineObj.put('Amount', qli.TotalPrice);
                            }
                            if (String.isNotBlank(qli.Description)) {
                                lineObj.put('Description', qli.Description);
                            }

                            // Apply dynamic QuoteLineItem mappings
                            for (String sfField : lineItemMapping.keySet()) {
                                String qboField = lineItemMapping.get(sfField);
                                Object val = getFieldValue(qli, sfField);
                                if (val != null) {
                                    String leaf = normalizeLineLeaf(qboField);
                                    if (leaf.contains('.')) {
                                        putPath(salesDetail, leaf, val);
                                    } else if (leaf == 'Qty' || leaf == 'UnitPrice') {
                                        salesDetail.put(leaf, val);
                                    } else {
                                        lineObj.put(leaf, val);
                                    }
                                }
                            }

                            linesJson.add(lineObj);
                        }
                    }
                    payloadMap.put('Line', linesJson);

                    if (linesJson.isEmpty()) {
                        System.debug('Skipping QBO Estimate sync for Quote ' + quoteRecord.Id + ' because it has no line items yet.');
                        recordSharedFailure(quoteRecord.Id, 'Quote has no line items.', false);
                        continue;
                    }

                    // Execute Callout
                    String jsonBody = JSON.serialize(payloadMap);
                    HttpResponse response = QuickBooksAuthHandler.makeApiCall('POST', '/estimate', jsonBody);

                    if (response != null && (response.getStatusCode() == 200 || response.getStatusCode() == 201) && String.isNotBlank(response.getBody())) {
                        Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                        if (respMap != null && respMap.containsKey('Estimate')) {
                            Map<String, Object> estObj = (Map<String, Object>) respMap.get('Estimate');
                            String returnedId = String.valueOf(estObj.get('Id'));
                            String returnedToken = String.valueOf(estObj.get('SyncToken'));

                            Quote quoteUpdate = new Quote(Id = quoteRecord.Id);
                            setSObjectField(quoteUpdate, 'QuickbookID__c', returnedId);
                            setSObjectField(quoteUpdate, 'SyncToken__c', returnedToken);
                            quotesToUpdate.add(quoteUpdate);

                            // Write back composite QBO Line IDs (EstimateId:LineId) to QuoteLineItem to prevent duplicates during inbound sync
                            if (estObj.containsKey('Line') && quoteRecord.QuoteLineItems != null && !quoteRecord.QuoteLineItems.isEmpty()) {
                                List<Object> respLines = (List<Object>) estObj.get('Line');
                                List<Map<String, Object>> salesLines = new List<Map<String, Object>>();
                                for (Object lObj : respLines) {
                                    if (lObj instanceof Map<String, Object>) {
                                        Map<String, Object> lMap = (Map<String, Object>) lObj;
                                        if (lMap.get('DetailType') == 'SalesItemLineDetail') {
                                            salesLines.add(lMap);
                                        }
                                    }
                                }

                                List<QuoteLineItem> qliUpdates = new List<QuoteLineItem>();
                                for (Integer i = 0; i < quoteRecord.QuoteLineItems.size(); i++) {
                                    QuoteLineItem sfQli = quoteRecord.QuoteLineItems[i];
                                    if (i < salesLines.size()) {
                                        Map<String, Object> qboLine = salesLines[i];
                                        String qbLineId = String.valueOf(qboLine.get('Id'));
                                        if (String.isNotBlank(qbLineId)) {
                                            QuoteLineItem qliUpd = new QuoteLineItem(Id = sfQli.Id);
                                            setSObjectField(qliUpd, 'QB_LineItemID__c', returnedId + ':' + qbLineId);
                                            qliUpdates.add(qliUpd);
                                        }
                                    }
                                }
                                if (!qliUpdates.isEmpty()) {
                                    Database.SaveResult[] lineResults = Database.update(qliUpdates, false);
                                    for (Database.SaveResult lineResult : lineResults) {
                                        if (!lineResult.isSuccess()) {
                                            recordSharedFailure(
                                                quoteRecord.Id,
                                                lineResult.getErrors()[0].getMessage(),
                                                IntegrationRetryPolicy.isRetryableMessage(lineResult.getErrors()[0].getMessage())
                                            );
                                        }
                                    }
                                }
                            }
                        } else {
                            recordSharedFailure(quoteRecord.Id, 'QuickBooks returned an empty Estimate response.', false);
                        }
                    } else {
                        String errBody = response != null ? response.getBody() : 'Null Response';
                        Integer statusCode = response != null ? response.getStatusCode() : 0;
                        ErrorLogUtility.logCalloutFailure('QuickBooks', 'QBQuoteToEstimateSyncBatch.execute', 'Failed QBO Estimate sync: ' + errBody, statusCode, 'Quote', quoteRecord.Id);
                        recordSharedFailure(
                            quoteRecord.Id,
                            'Failed QBO Estimate sync: ' + errBody,
                            IntegrationRetryPolicy.isRetryable(response)
                        );
                    }
                } catch (Exception ex) {
                    ErrorLogUtility.logException('QuickBooks', 'QBQuoteToEstimateSyncBatch.execute', ex, 'Quote', quoteRecord.Id);
                    recordSharedFailure(
                        quoteRecord.Id,
                        ex.getMessage(),
                        IntegrationRetryPolicy.isRetryable(ex) ||
                            IntegrationRetryPolicy.isRetryableMessage(ex.getMessage())
                    );
                }
            }

            if (!quotesToUpdate.isEmpty()) {
                Database.SaveResult[] results = Database.update(quotesToUpdate, false);
                ErrorLogUtility.logDmlResults('QuickBooks', 'QBQuoteToEstimateSyncBatch.execute.updateQuotes', 'update', quotesToUpdate, results, null, null);
                for (Integer resultIndex = 0; resultIndex < results.size(); resultIndex++) {
                    if (results[resultIndex].isSuccess()) {
                        sharedSuccessfulRecordIds.add(quotesToUpdate[resultIndex].Id);
                    } else {
                        String errorMessage = results[resultIndex].getErrors()[0].getMessage();
                        recordSharedFailure(
                            quotesToUpdate[resultIndex].Id,
                            errorMessage,
                            IntegrationRetryPolicy.isRetryableMessage(errorMessage)
                        );
                    }
                }
            }
        } finally {
            isProcessing = false;
            QBTriggerHandler.isQuoteProcessing = false;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('QBQuoteToEstimateSyncBatch finished.');
    }

    private void recordSharedFailure(Id recordId, String message, Boolean retryable) {
        if (sharedExecutionResult == null) {
            return;
        }
        if (recordId != null) {
            sharedFailedRecordIds.add(recordId);
        }
        sharedExecutionResult.addError(message);
        if (retryable == true) {
            sharedExecutionResult.retryable = true;
            sharedExecutionResult.retryDelaySeconds = 60;
            if (recordId != null && !sharedExecutionResult.retryRecordIds.contains(recordId)) {
                sharedExecutionResult.retryRecordIds.add(recordId);
            }
        }
    }

    private static String buildAccountQueryFields() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Account.fields.getMap();
        Set<String> fieldApiNames = new Set<String>{'Id', 'Name', 'QuickbookID__c'};
        for (String sfField : QBObjectMappings.getAccountToCustomerMapping().keySet()) {
            fieldApiNames.add(sfField);
        }
        Set<String> resolvedFields = new Set<String>();
        for (String fieldName : fieldApiNames) {
            String keyLower = fieldName.toLowerCase();
            if (schemaFields.containsKey(keyLower)) resolvedFields.add(schemaFields.get(keyLower).getDescribe().getName());
            if (schemaFields.containsKey('quickbridgetlg__' + keyLower)) resolvedFields.add(schemaFields.get('quickbridgetlg__' + keyLower).getDescribe().getName());
        }
        return String.join(new List<String>(resolvedFields), ', ');
    }

    private static void setSObjectField(SObject obj, String fieldName, Object val) {
        if (obj == null || String.isBlank(fieldName)) return;
        Map<String, Schema.SObjectField> fields = obj.getSObjectType().getDescribe().fields.getMap();
        String key = fieldName.toLowerCase();
        if (fields.containsKey(key)) {
            try {
                obj.put(fields.get(key).getDescribe().getName(), val);
            } catch (Exception e) {}
        }
        if (fields.containsKey('quickbridgetlg__' + key)) {
            try {
                obj.put(fields.get('quickbridgetlg__' + key).getDescribe().getName(), val);
            } catch (Exception e) {}
        }
    }

    private static Object getSObjectField(SObject obj, String fieldName) {
        if (obj == null || String.isBlank(fieldName)) return null;
        Map<String, Schema.SObjectField> fields = obj.getSObjectType().getDescribe().fields.getMap();
        String key = fieldName.toLowerCase();
        if (fields.containsKey(key)) {
            try {
                Object val = obj.get(fields.get(key).getDescribe().getName());
                if (val != null) return val;
            } catch (Exception e) {}
        }
        if (fields.containsKey('quickbridgetlg__' + key)) {
            try {
                Object val = obj.get(fields.get('quickbridgetlg__' + key).getDescribe().getName());
                if (val != null) return val;
            } catch (Exception e) {}
        }
        return null;
    }

    private void putPath(Map<String, Object> root, String dottedPath, Object value) {
        if (root == null || String.isBlank(dottedPath)) return;
        if (!dottedPath.contains('.')) {
            root.put(dottedPath, value);
            return;
        }
        List<String> parts = dottedPath.split('\\.');
        Map<String, Object> current = root;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            String part = parts[i];
            if (!(current.get(part) instanceof Map<String, Object>)) {
                current.put(part, new Map<String, Object>());
            }
            current = (Map<String, Object>) current.get(part);
        }
        current.put(parts[parts.size() - 1], value);
    }

    private String normalizeLineLeaf(String qboField) {
        String leaf = qboField;
        if (leaf.startsWith('Line.')) {
            leaf = leaf.substringAfter('Line.');
        }
        if (leaf.startsWith('SalesItemLineDetail.')) {
            leaf = leaf.substringAfter('SalesItemLineDetail.');
        }
        return leaf;
    }

    private Object getFieldValue(SObject obj, String fieldPath) {
        if (obj == null || String.isBlank(fieldPath)) return null;
        if (!fieldPath.contains('.')) {
            return getSObjectField(obj, fieldPath);
        }
        List<String> fields = fieldPath.split('\\.');
        SObject currentObj = obj;
        for (Integer i = 0; i < fields.size() - 1; i++) {
            currentObj = (SObject) getSObjectField(currentObj, fields[i]);
            if (currentObj == null) return null;
        }
        return getSObjectField(currentObj, fields[fields.size() - 1]);
    }
}