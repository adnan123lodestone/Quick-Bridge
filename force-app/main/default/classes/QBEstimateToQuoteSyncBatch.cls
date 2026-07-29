public class QBEstimateToQuoteSyncBatch implements Database.Batchable<String>, Database.AllowsCallouts, Database.Stateful {

    private String lastSyncDate;
    public static Boolean isProcessing = false;

    private Map<String, Id> customerIdMap = new Map<String, Id>();
    private Map<String, Id> productIdMap = new Map<String, Id>();
    private Map<String, Id> quoteIdMap = new Map<String, Id>();
    private Id standardPricebookId;

    public QBEstimateToQuoteSyncBatch() {
        Datetime yesterday = Datetime.now().addDays(-1);
        this.lastSyncDate = yesterday.format('YYYY-MM-dd');
        this.standardPricebookId = getStandardPricebookId();
    }
    
    public QBEstimateToQuoteSyncBatch(String syncDate) {
        this.lastSyncDate = syncDate;
        this.standardPricebookId = getStandardPricebookId();
    }

    private Id getStandardPricebookId() {
        try {
            if (Test.isRunningTest()) return Test.getStandardPricebookId();
            return [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1].Id;
        } catch (Exception e) {
            System.debug('Error getting standard pricebook: ' + e.getMessage());
            return null;
        }
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> estimateIds = new List<String>();
        try {
            String query = 'select * from Estimate Where Metadata.LastUpdatedTime > \'' + lastSyncDate + '\'';
            String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
            String resourcePath = '/query?query=' + encodedQuery;

            HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', resourcePath, null);

            if(response != null && response.getStatusCode() == 200 && String.isNotBlank(response.getBody())) {
                Map<String, Object> result = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                if(result != null && result.containsKey('QueryResponse')) {
                    Map<String, Object> queryResponse = (Map<String, Object>)result.get('QueryResponse');
                    if(queryResponse != null && queryResponse.containsKey('Estimate')) {
                        List<Object> estimates = (List<Object>)queryResponse.get('Estimate');
                        if(estimates != null) {
                            for(Object est : estimates) {
                                if(est != null) {
                                    estimateIds.add(JSON.serialize(est));
                                }
                            }
                        }
                    }
                }
            } else if (response != null) {
                ErrorLogUtility.logCalloutFailure('QuickBooks', 'QBEstimateToQuoteSyncBatch.start', 'HTTP ' + response.getStatusCode() + ': ' + response.getBody(), response.getStatusCode(), null, null);
            }
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBEstimateToQuoteSyncBatch.start', e, null, null);
        }
        return estimateIds;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        isProcessing = true;
        if (this.standardPricebookId == null) {
            this.standardPricebookId = getStandardPricebookId();
        }

        try {
            processAccountsAndProducts(scope);
            processQuotes(scope);
            processQuoteLineItems(scope);
        } catch(Exception e) {
            System.debug('QBEstimateToQuoteSyncBatch EXECUTE EXCEPTION: ' + e.getMessage() + '\n' + e.getStackTraceString());
            ErrorLogUtility.logException('QuickBooks', 'QBEstimateToQuoteSyncBatch.execute', e, null, null);
        } finally {
            isProcessing = false;
        }
    }

    private void processAccountsAndProducts(List<String> scope) {
        List<Account> accountsToUpsert = new List<Account>();
        List<Product2> productsToUpsert = new List<Product2>();
        Set<String> productQBIds = new Set<String>();
        Set<String> customerQBIds = new Set<String>();

        for(String jsonStr : scope) {
            Map<String, Object> estimate = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);
            if(estimate.containsKey('CustomerRef')) {
                Map<String, Object> customerRef = (Map<String, Object>)estimate.get('CustomerRef');
                if (customerRef != null && customerRef.containsKey('value')) {
                    customerQBIds.add((String)customerRef.get('value'));
                }
            }
        }

        if (!customerQBIds.isEmpty()) {
            String accQuery = 'SELECT Id, ' + getAccountQbIdSelectFields() + ' FROM Account WHERE ' + getAccountQbIdWhereClause();
            for (Account a : (List<Account>) Database.query(accQuery)) {
                String qbId = (String) getSObjectField(a, 'QuickbookID__c');
                if (String.isNotBlank(qbId)) customerIdMap.put(qbId, a.Id);
            }
        }

        for(String jsonStr : scope) {
            Map<String, Object> estimate = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);

            if(estimate.containsKey('CustomerRef')) {
                Map<String, Object> customerRef = (Map<String, Object>)estimate.get('CustomerRef');
                String qbCustomerId = (String)customerRef.get('value');
                String customerName = (String)customerRef.get('name');

                if(!customerIdMap.containsKey(qbCustomerId)) {
                    Account newAcc = new Account(
                        Name = (String.isNotBlank(customerName) ? customerName : 'Unknown Customer')
                    );
                    putFieldValue(newAcc, 'QuickbookID__c', qbCustomerId);
                    accountsToUpsert.add(newAcc);
                }
            }

            if(estimate.containsKey('Line')) {
                List<Object> lines = (List<Object>)estimate.get('Line');
                for(Object lineObj : lines) {
                    Map<String, Object> line = (Map<String, Object>)lineObj;
                    if(line.get('DetailType') == 'SalesItemLineDetail') {
                        Map<String, Object> detail = (Map<String, Object>)line.get('SalesItemLineDetail');
                        if(detail != null && detail.containsKey('ItemRef')) {
                            Map<String, Object> itemRef = (Map<String, Object>)detail.get('ItemRef');
                            productQBIds.add((String)itemRef.get('value'));
                        }
                    }
                }
            }
        }

        if(!accountsToUpsert.isEmpty()) {
            Map<String, Account> dedupMap = new Map<String, Account>();
            for (Account a : accountsToUpsert) {
                String qbId = (String) getSObjectField(a, 'QuickbookID__c');
                if (String.isNotBlank(qbId)) dedupMap.put(qbId, a);
            }
            Database.UpsertResult[] results = Database.upsert(dedupMap.values(), getAccountQbIdField(), false);
            for(Integer i = 0; i < results.size(); i++) {
                String qbId = (String) getSObjectField(dedupMap.values()[i], 'QuickbookID__c');
                if(results[i].isSuccess() && String.isNotBlank(qbId)) customerIdMap.put(qbId, results[i].getId());
            }
        }

        if (!productQBIds.isEmpty()) {
            String prodQuery = 'SELECT Id, ' + getProductQbIdSelectFields() + ' FROM Product2 WHERE ' + getProductQbIdWhereClause();
            for(Product2 p : (List<Product2>) Database.query(prodQuery)) {
                String qbId = (String) getSObjectField(p, 'QuickbookID__c');
                if (String.isNotBlank(qbId)) productIdMap.put(qbId, p.Id);
            }
        }

        for(String jsonStr : scope) {
            Map<String, Object> estimate = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);
            if(estimate.containsKey('Line')) {
                for(Object lineObj : (List<Object>)estimate.get('Line')) {
                    Map<String, Object> line = (Map<String, Object>)lineObj;
                    if(line.get('DetailType') == 'SalesItemLineDetail') {
                        Map<String, Object> detail = (Map<String, Object>)line.get('SalesItemLineDetail');
                        if(detail != null && detail.containsKey('ItemRef')) {
                            Map<String, Object> itemRef = (Map<String, Object>)detail.get('ItemRef');
                            String qbProdId = (String)itemRef.get('value');
                            if(!productIdMap.containsKey(qbProdId)) {
                                Product2 pNew = new Product2(Name = (String)itemRef.get('name'), IsActive = true);
                                putFieldValue(pNew, 'QuickbookID__c', qbProdId);
                                productsToUpsert.add(pNew);
                            }
                        }
                    }
                }
            }
        }

        if(!productsToUpsert.isEmpty()) {
            Database.UpsertResult[] results = Database.upsert(productsToUpsert, getProductQbIdField(), false);
            List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
            for(Integer i = 0; i < results.size(); i++) {
                String qbId = (String) getSObjectField(productsToUpsert[i], 'QuickbookID__c');
                if(results[i].isSuccess()) {
                    if (String.isNotBlank(qbId)) productIdMap.put(qbId, results[i].getId());
                    pbesToInsert.add(new PricebookEntry(Pricebook2Id = standardPricebookId, Product2Id = results[i].getId(), UnitPrice = 0, IsActive = true));
                }
            }
            if(!pbesToInsert.isEmpty()) insert pbesToInsert;
        }
    }

    private void processQuotes(List<String> scope) {
        List<Quote> quotesToUpsert = new List<Quote>();
        Map<String, String> quoteMapping = QBObjectMappings.getQuoteMapping();

        Set<Id> accountIds = new Set<Id>();
        for (Id aId : customerIdMap.values()) {
            if (aId != null) accountIds.add(aId);
        }

        Map<Id, Id> accountToOppMap = new Map<Id, Id>();
        if (!accountIds.isEmpty()) {
            for (Opportunity opp : [SELECT Id, AccountId FROM Opportunity WHERE AccountId IN :accountIds ORDER BY CreatedDate DESC]) {
                if (!accountToOppMap.containsKey(opp.AccountId)) {
                    accountToOppMap.put(opp.AccountId, opp.Id);
                }
            }
        }

        List<Opportunity> newOppsToInsert = new List<Opportunity>();
        Map<Id, Integer> accToNewOppIndex = new Map<Id, Integer>();
        for (String jsonStr : scope) {
            Map<String, Object> estimate = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);
            Map<String, Object> customerRef = (Map<String, Object>)estimate.get('CustomerRef');
            if (customerRef != null) {
                String qbCustomerId = (String)customerRef.get('value');
                Id sfAccountId = customerIdMap.get(qbCustomerId);
                if (sfAccountId != null && !accountToOppMap.containsKey(sfAccountId) && !accToNewOppIndex.containsKey(sfAccountId)) {
                    String docNum = (String)estimate.get('DocNumber');
                    Opportunity opp = new Opportunity(
                        Name = 'Estimate Opp ' + (String.isNotBlank(docNum) ? docNum : (String)estimate.get('Id')),
                        AccountId = sfAccountId,
                        StageName = 'Prospecting',
                        CloseDate = Date.today().addDays(30),
                        Pricebook2Id = standardPricebookId
                    );
                    accToNewOppIndex.put(sfAccountId, newOppsToInsert.size());
                    newOppsToInsert.add(opp);
                }
            }
        }

        if (!newOppsToInsert.isEmpty()) {
            insert newOppsToInsert;
            for (Id sfAccountId : accToNewOppIndex.keySet()) {
                Integer idx = accToNewOppIndex.get(sfAccountId);
                accountToOppMap.put(sfAccountId, newOppsToInsert[idx].Id);
            }
        }

        for(String jsonStr : scope) {
            Map<String, Object> estimate = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);
            String qbEstimateId = (String)estimate.get('Id');

            if(!quoteIdMap.containsKey(qbEstimateId)) {
                Map<String, Object> customerRef = (Map<String, Object>)estimate.get('CustomerRef');
                if (customerRef == null) continue;
                
                String qbCustomerId = (String)customerRef.get('value');
                Id sfAccountId = customerIdMap.get(qbCustomerId);

                if(sfAccountId != null) {
                    Quote newQuote = new Quote(
                        OpportunityId = accountToOppMap.get(sfAccountId),
                        Pricebook2Id = standardPricebookId,
                        Status = 'Draft'
                    );
                    putFieldValue(newQuote, 'QuickbookID__c', qbEstimateId);

                    // 2. Apply Dynamic Mappings safely
                    applyDynamicMapping(newQuote, estimate, quoteMapping);

                    // Name requires a special fallback if DocNumber isn't provided or mapped
                    if (String.isBlank(newQuote.Name)) {
                        String docNumber = (String)estimate.get('DocNumber');
                        newQuote.Name = 'Estimate ' + (String.isNotBlank(docNumber) ? docNumber : qbEstimateId);
                    }

                    quotesToUpsert.add(newQuote);
                }
            }
        }

        if(!quotesToUpsert.isEmpty()) {
            Schema.SObjectField extIdField = getQuoteQbIdField();
            Database.UpsertResult[] results = Database.upsert(quotesToUpsert, extIdField, false);
            for(Integer i = 0; i < results.size(); i++) {
                String qbId = (String) getSObjectField(quotesToUpsert[i], 'QuickbookID__c');
                if(results[i].isSuccess() && String.isNotBlank(qbId)) quoteIdMap.put(qbId, results[i].getId());
            }
        }
    }

    public void processQuoteLineItems(List<String> scope) {
        List<QuoteLineItem> linesToUpsert = new List<QuoteLineItem>();
        
        // Fetch Dynamic Mapping for Quote Line Items
        Map<String, String> lineMapping = QBObjectMappings.getQuoteLineItemMapping();
        if (lineMapping == null) {
            lineMapping = new Map<String, String>();
        }
        Set<String> mappedTargetFields = new Set<String>(lineMapping.values());
        if (!lineMapping.containsKey('Qty') && !lineMapping.containsKey('SalesItemLineDetail.Qty') && !mappedTargetFields.contains('Quantity')) {
            lineMapping.put('Qty', 'Quantity');
        }
        if (!lineMapping.containsKey('UnitPrice') && !lineMapping.containsKey('SalesItemLineDetail.UnitPrice') && !mappedTargetFields.contains('UnitPrice')) {
            lineMapping.put('UnitPrice', 'UnitPrice');
        }
        if (!lineMapping.containsKey('Description') && !lineMapping.containsKey('Line.Description') && !mappedTargetFields.contains('Description')) {
            lineMapping.put('Description', 'Description');
        }
        
        Map<Id, Id> productToPbeMap = new Map<Id, Id>();
        for(PricebookEntry pbe : [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :standardPricebookId AND Product2Id IN :productIdMap.values() AND IsActive = true]) {
            productToPbeMap.put(pbe.Product2Id, pbe.Id);
        }

        for(String jsonStr : scope) {
            Map<String, Object> estimate = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);
            String qbEstimateId = (String)estimate.get('Id');
            Id sfQuoteId = quoteIdMap.get(qbEstimateId);

            if(sfQuoteId == null || !estimate.containsKey('Line')) continue;

            List<Object> lines = (List<Object>)estimate.get('Line');
            for(Object lineObj : lines) {
                Map<String, Object> line = (Map<String, Object>)lineObj;
                if(line.get('DetailType') != 'SalesItemLineDetail') continue;

                Map<String, Object> detail = (Map<String, Object>)line.get('SalesItemLineDetail');
                if(detail == null || !detail.containsKey('ItemRef')) continue;

                Map<String, Object> itemRef = (Map<String, Object>)detail.get('ItemRef');
                String qbProductId = (String)itemRef.get('value');
                String qbLineId = (String)line.get('Id');
                String compositeId = qbEstimateId + ':' + qbLineId;

                Id sfProductId = productIdMap.get(qbProductId);
                Id pbeId = productToPbeMap.get(sfProductId);

                if(pbeId != null) {
                    // Initialize base QuoteLineItem with required Lookups and Default Quantities
                    QuoteLineItem qli = new QuoteLineItem(
                        QuoteId = sfQuoteId,
                        Product2Id = sfProductId,
                        PricebookEntryId = pbeId,
                        Quantity = 1,
                        UnitPrice = 0,
                        QB_LineItemID__c = compositeId
                    );
                    
                    // Combine line details to make mapping easier
                    Map<String, Object> flatLineData = new Map<String, Object>(line);
                    for (String key : detail.keySet()) {
                        flatLineData.put(key, detail.get(key));
                    }

                    // Apply Dynamic Mappings safely
                    applyDynamicMapping(qli, flatLineData, lineMapping);
                    
                    linesToUpsert.add(qli);
                }
            }
        }

        if(!linesToUpsert.isEmpty()) {
            Database.upsert(linesToUpsert, getQuoteLineItemQbIdField(), false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Estimate to Quote Sync Completed.');
    }

    // Helper to dynamically apply field values
    private void applyDynamicMapping(SObject record, Map<String, Object> qbData, Map<String, String> mapping) {
        if (record == null || qbData == null || mapping == null) return;

        for (String qbField : mapping.keySet()) {
            String normalizedField = normalizeLineLeaf(qbField);
            Object qbValue = getNestedValue(qbData, normalizedField);
            if (qbValue == null && qbData.containsKey(normalizedField)) {
                qbValue = qbData.get(normalizedField);
            }
            if (qbValue != null) {
                try {
                    putFieldValue(record, mapping.get(qbField), qbValue);
                } catch (Exception e) {}
            }
        }
    }

    private String normalizeLineLeaf(String qboField) {
        if (String.isBlank(qboField)) return qboField;
        String leaf = qboField;
        if (leaf.startsWith('Line.')) {
            leaf = leaf.substringAfter('Line.');
        }
        if (leaf.startsWith('SalesItemLineDetail.')) {
            leaf = leaf.substringAfter('SalesItemLineDetail.');
        }
        return leaf;
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
        if (record == null || String.isBlank(fieldName) || fieldName.contains('.') || value == null) return;
        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        String lowName = fieldName.toLowerCase();
        if (!fields.containsKey(lowName) && fields.containsKey('quickbridgetlg__' + lowName)) {
            lowName = 'quickbridgetlg__' + lowName;
        }
        if (!fields.containsKey(lowName)) return;
        Schema.DescribeFieldResult d = fields.get(lowName).getDescribe();
        if (!d.isCreateable() && !d.isUpdateable()) return;
        Schema.DisplayType displayType = d.getType();
        record.put(d.getName(), coerceValue(value, displayType));
    }

    private Object coerceValue(Object value, Schema.DisplayType displayType) {
        if (value == null) return null;
        try {
            if (displayType == Schema.DisplayType.Currency || displayType == Schema.DisplayType.Double || displayType == Schema.DisplayType.Percent) {
                return Decimal.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.Integer) {
                return Integer.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.Boolean) {
                return String.valueOf(value).toLowerCase() == 'true';
            }
            if (displayType == Schema.DisplayType.Date) {
                return Date.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.DateTime) {
                return Datetime.valueOf(String.valueOf(value));
            }
        } catch (Exception e) {}
        return String.valueOf(value);
    }

    private static String getAccountQbIdSelectFields() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Account.fields.getMap();
        List<String> fList = new List<String>();
        if (schemaFields.containsKey('quickbookid__c')) fList.add('QuickbookID__c');
        if (schemaFields.containsKey('quickbridgetlg__quickbookid__c')) fList.add('QuickBridgeTLG__QuickbookID__c');
        if (fList.isEmpty()) fList.add('QuickbookID__c');
        return String.join(fList, ', ');
    }

    private static String getAccountQbIdWhereClause() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Account.fields.getMap();
        List<String> clauses = new List<String>();
        if (schemaFields.containsKey('quickbookid__c')) clauses.add('QuickbookID__c IN :customerQBIds');
        if (schemaFields.containsKey('quickbridgetlg__quickbookid__c')) clauses.add('QuickBridgeTLG__QuickbookID__c IN :customerQBIds');
        if (clauses.isEmpty()) return 'QuickbookID__c IN :customerQBIds';
        return '(' + String.join(clauses, ' OR ') + ')';
    }

    private static String getProductQbIdSelectFields() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Product2.fields.getMap();
        List<String> fList = new List<String>();
        if (schemaFields.containsKey('quickbookid__c')) fList.add('QuickbookID__c');
        if (schemaFields.containsKey('quickbridgetlg__quickbookid__c')) fList.add('QuickBridgeTLG__QuickbookID__c');
        if (fList.isEmpty()) fList.add('QuickbookID__c');
        return String.join(fList, ', ');
    }

    private static String getProductQbIdWhereClause() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Product2.fields.getMap();
        List<String> clauses = new List<String>();
        if (schemaFields.containsKey('quickbookid__c')) clauses.add('QuickbookID__c IN :productQBIds');
        if (schemaFields.containsKey('quickbridgetlg__quickbookid__c')) clauses.add('QuickBridgeTLG__QuickbookID__c IN :productQBIds');
        if (clauses.isEmpty()) return 'QuickbookID__c IN :productQBIds';
        return '(' + String.join(clauses, ' OR ') + ')';
    }

    private static Schema.SObjectField getQuoteLineItemQbIdField() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.QuoteLineItem.fields.getMap();
        if (fields.containsKey('quickbridgetlg__qb_lineitemid__c')) return fields.get('quickbridgetlg__qb_lineitemid__c');
        return fields.get('qb_lineitemid__c');
    }

    private static String getAccountQbIdFieldName() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Account.fields.getMap();
        if (!schemaFields.containsKey('quickbookid__c') && schemaFields.containsKey('quickbridgetlg__quickbookid__c')) {
            return 'QuickBridgeTLG__QuickbookID__c';
        }
        return 'QuickbookID__c';
    }

    private static Schema.SObjectField getQuoteQbIdField() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Quote.fields.getMap();
        if (fields.containsKey('quickbridgetlg__quickbookid__c')) return fields.get('quickbridgetlg__quickbookid__c');
        return fields.get('quickbookid__c');
    }

    private static Schema.SObjectField getAccountQbIdField() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Account.fields.getMap();
        if (fields.containsKey('quickbridgetlg__quickbookid__c')) return fields.get('quickbridgetlg__quickbookid__c');
        return fields.get('quickbookid__c');
    }

    private static Schema.SObjectField getProductQbIdField() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Product2.fields.getMap();
        if (fields.containsKey('quickbridgetlg__quickbookid__c')) return fields.get('quickbridgetlg__quickbookid__c');
        return fields.get('quickbookid__c');
    }

    private static String getProductQbIdFieldName() {
        Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Product2.fields.getMap();
        if (!schemaFields.containsKey('quickbookid__c') && schemaFields.containsKey('quickbridgetlg__quickbookid__c')) {
            return 'QuickBridgeTLG__QuickbookID__c';
        }
        return 'QuickbookID__c';
    }

    private static Object getSObjectField(SObject obj, String fieldName) {
        if (obj == null || String.isBlank(fieldName)) return null;
        Map<String, Schema.SObjectField> fields = obj.getSObjectType().getDescribe().fields.getMap();
        String key = fieldName.toLowerCase();
        if (fields.containsKey(key)) {
            return obj.get(fields.get(key).getDescribe().getName());
        }
        if (fields.containsKey('quickbridgetlg__' + key)) {
            return obj.get(fields.get('quickbridgetlg__' + key).getDescribe().getName());
        }
        return null;
    }
}