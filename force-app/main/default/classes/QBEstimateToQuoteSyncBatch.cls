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

        try {
            processAccountsAndProducts(scope);
            processQuotes(scope);
            processQuoteLineItems(scope);
        } catch(Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBEstimateToQuoteSyncBatch.execute', e, null, null);
        } finally {
            isProcessing = false;
        }
    }

    private void processAccountsAndProducts(List<String> scope) {
        List<Account> accountsToUpsert = new List<Account>();
        List<Product2> productsToUpsert = new List<Product2>();
        Set<String> productQBIds = new Set<String>();

        for(String jsonStr : scope) {
            Map<String, Object> estimate = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);

            if(estimate.containsKey('CustomerRef')) {
                Map<String, Object> customerRef = (Map<String, Object>)estimate.get('CustomerRef');
                String qbCustomerId = (String)customerRef.get('value');
                String customerName = (String)customerRef.get('name');

                if(!customerIdMap.containsKey(qbCustomerId)) {
                    accountsToUpsert.add(new Account(
                        Name = (String.isNotBlank(customerName) ? customerName : 'Unknown Customer'),
                        QuickbookID__c = qbCustomerId
                    ));
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
            for (Account a : accountsToUpsert) dedupMap.put(a.QuickbookID__c, a);
            Database.UpsertResult[] results = Database.upsert(dedupMap.values(), Account.Fields.QuickbookID__c, false);
            for(Integer i = 0; i < results.size(); i++) {
                if(results[i].isSuccess()) customerIdMap.put(dedupMap.values()[i].QuickbookID__c, results[i].getId());
            }
        }

        for(Product2 p : [SELECT Id, QuickbookID__c FROM Product2 WHERE QuickbookID__c IN :productQBIds]) {
            productIdMap.put(p.QuickbookID__c, p.Id);
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
                                productsToUpsert.add(new Product2(Name = (String)itemRef.get('name'), QuickbookID__c = qbProdId, IsActive = true));
                            }
                        }
                    }
                }
            }
        }

        if(!productsToUpsert.isEmpty()) {
            Database.UpsertResult[] results = Database.upsert(productsToUpsert, Product2.Fields.QuickbookID__c, false);
            List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
            for(Integer i = 0; i < results.size(); i++) {
                if(results[i].isSuccess()) {
                    productIdMap.put(productsToUpsert[i].QuickbookID__c, results[i].getId());
                    pbesToInsert.add(new PricebookEntry(Pricebook2Id = standardPricebookId, Product2Id = results[i].getId(), UnitPrice = 0, IsActive = true));
                }
            }
            if(!pbesToInsert.isEmpty()) insert pbesToInsert;
        }
    }

    private void processQuotes(List<String> scope) {
        List<Quote> quotesToUpsert = new List<Quote>();
        
        // 1. Fetch Dynamic Mapping for Quote
        Map<String, String> quoteMapping = QBObjectMappings.getQuoteMapping();

        for(String jsonStr : scope) {
            Map<String, Object> estimate = (Map<String, Object>)JSON.deserializeUntyped(jsonStr);
            String qbEstimateId = (String)estimate.get('Id');

            if(!quoteIdMap.containsKey(qbEstimateId)) {
                Map<String, Object> customerRef = (Map<String, Object>)estimate.get('CustomerRef');
                if (customerRef == null) continue;
                
                String qbCustomerId = (String)customerRef.get('value');
                Id sfAccountId = customerIdMap.get(qbCustomerId);

                if(sfAccountId != null) {
                    // Initialize base Quote with required/fixed values
                    Quote newQuote = new Quote(
                        //AccountId = sfAccountId,
                        Pricebook2Id = standardPricebookId,
                        QuickbookID__c = qbEstimateId,
                        Status = 'Draft'
                    );

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
            Schema.SObjectField extIdField = Quote.Fields.QuickbookID__c;
            Database.UpsertResult[] results = Database.upsert(quotesToUpsert, extIdField, false);
            for(Integer i = 0; i < results.size(); i++) {
                if(results[i].isSuccess()) quoteIdMap.put(quotesToUpsert[i].QuickbookID__c, results[i].getId());
            }
        }
    }

    public void processQuoteLineItems(List<String> scope) {
        List<QuoteLineItem> linesToUpsert = new List<QuoteLineItem>();
        
        // Fetch Dynamic Mapping for Quote Line Items
        Map<String, String> lineMapping = QBObjectMappings.getQuoteLineItemMapping();
        
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
            Database.upsert(linesToUpsert, QuoteLineItem.Fields.QB_LineItemID__c, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Estimate to Quote Sync Completed.');
    }

    // Helper to dynamically apply field values
    private void applyDynamicMapping(SObject record, Map<String, Object> qbData, Map<String, String> mapping) {
        if (record == null || qbData == null || mapping == null) return;

        for (String qbField : mapping.keySet()) {
            Object qbValue = getNestedValue(qbData, qbField);
            if (qbValue != null) {
                try {
                    putFieldValue(record, mapping.get(qbField), qbValue);
                } catch (Exception e) {}
            }
        }
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
        if (!fields.containsKey(fieldName)) return;
        Schema.DisplayType displayType = fields.get(fieldName).getDescribe().getType();
        record.put(fieldName, coerceValue(value, displayType));
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
        return value;
    }
}