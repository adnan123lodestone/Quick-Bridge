global class ShopifyProductsOutboundBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    private Set<Id> recordIds;
    private Boolean isInitialSync;
    private Integer successCount = 0;
    private Integer errorCount = 0;
    private Map<String, String> fieldMap;
    private String shopifyIdField;

    private Set<Id> rateLimitedIds = new Set<Id>();
    private Integer retryAfterSeconds = 60;
    private Boolean hitRateLimit = false;

    @TestVisible private static Boolean bypassAuthCheckForTest = false;

    global ShopifyProductsOutboundBatch(Set<Id> recordIds, Boolean isInitialSync) {
        this.recordIds    = recordIds;
        this.isInitialSync = isInitialSync;
        this.fieldMap = ShopifyObjectMappings.getProductToShopifyMapping();
        this.shopifyIdField = resolveFieldName(Schema.SObjectType.Product2.fields.getMap(), 'shopify_id__c');
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        Map<String, Schema.SObjectField> product2Fields = Schema.SObjectType.Product2.fields.getMap();
        Set<String> fieldSet = new Set<String>{ 'id', 'name', 'stockkeepingunit', 'isactive' };
        for (String sfField : fieldMap.keySet()) {
            if (product2Fields.containsKey(sfField.toLowerCase())) {
                fieldSet.add(sfField.toLowerCase());
            }
        }
        Set<String> selected = new Set<String>{ shopifyIdField };
        for (String key : fieldSet) {
            Schema.SObjectField f = product2Fields.get(key);
            if (f != null) selected.add(f.getDescribe().getName());
        }
        String soql = 'SELECT ' + String.join(new List<String>(selected), ', ') +
                      ' FROM Product2 WHERE Id IN :recordIds';
        return Database.getQueryLocator(soql);
    }

    global void execute(Database.BatchableContext bc, List<sObject> scope) {
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            System.debug('Skipping ShopifyProductsOutboundBatch — Shopify license not active.');
            return;
        }

        IntegrationUsageService.assertCanConsumeTask('Shopify', scope == null ? 1 : scope.size());

        List<Product2> toUpdate = new List<Product2>();

        Boolean rateLimited = false;
        for (sObject sobj : scope) {
            Product2 prod = (Product2) sobj;
            if (rateLimited) {
                rateLimitedIds.add(prod.Id);
                continue;
            }
            try {
                Map<String, Object> payload = buildProductPayload(prod, fieldMap);
                String responseId = upsertToShopify((String) prod.get(shopifyIdField), payload);
                if (responseId == '__rate_limited__') {
                    rateLimited = true;
                    hitRateLimit = true;
                    rateLimitedIds.add(prod.Id);
                } else if (String.isNotBlank(responseId)) {
                    prod.put(shopifyIdField, responseId);
                    toUpdate.add(prod);
                    successCount++;
                }
            } catch (Exception e) {
                errorCount++;
                ErrorLogUtility.logException(
                    'Shopify',
                    'ShopifyProductsOutboundBatch.execute',
                    e,
                    'Product2',
                    prod == null ? null : prod.Id
                );
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(toUpdate, false);
            ErrorLogUtility.logDmlResults(
                'Shopify',
                'ShopifyProductsOutboundBatch.execute.updateShopifyIds',
                'update',
                toUpdate,
                updateResults,
                null,
                null
            );
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('ShopifyProductsOutboundBatch complete. Success: ' + successCount + ' | Errors: ' + errorCount);
        IntegrationUsageService.recordSuccessfulRecordSync('Shopify', successCount);
        IntegrationUsageService.incrementEndpointUsage('Shopify', successCount + errorCount);
        if (hitRateLimit && !rateLimitedIds.isEmpty()) {
            Integer delayMinutes = (Integer) Math.max(1, Math.ceil(retryAfterSeconds / 60.0));
            System.scheduleBatch(
                new ShopifyProductsOutboundBatch(rateLimitedIds, isInitialSync),
                'ShopifyProductsOutboundBatch_RateLimit_Retry_' + Datetime.now().getTime(),
                delayMinutes
            );
        }
    }

    private Map<String, Object> buildProductPayload(Product2 prod, Map<String, String> fieldMap) {
        Map<String, Object> product = new Map<String, Object>();

        for (String sfField : fieldMap.keySet()) {
            String shopifyPath = fieldMap.get(sfField);
            // status conversion handled separately
            if (shopifyPath == 'status') continue;
            Object val = prod.get(sfField);
            if (val == null) continue;
            product.put(shopifyPath, val);
        }

        // Always set status from IsActive
        product.put('status', prod.IsActive ? 'active' : 'draft');

        // Include variant with SKU when available
        if (String.isNotBlank(prod.StockKeepingUnit)) {
            product.put('variants', new List<Object>{
                new Map<String, Object>{ 'sku' => prod.StockKeepingUnit }
            });
        }

        return new Map<String, Object>{ 'product' => product };
    }

    private static String resolveFieldName(Map<String, Schema.SObjectField> fieldMap, String localName) {
        Schema.SObjectField f = fieldMap.get(localName);
        if (f == null) {
            for (String key : fieldMap.keySet()) {
                if (key.endsWith(localName) && !key.equals(localName)) {
                    f = fieldMap.get(key);
                    break;
                }
            }
        }
        return f?.getDescribe().getName();
    }

    private String upsertToShopify(String existingShopifyId, Map<String, Object> payload) {
        String endpoint;
        String method;

        if (String.isNotBlank(existingShopifyId)) {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/admin/api/2024-04/products/' + existingShopifyId + '.json';
            method   = 'PUT';
        } else {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/admin/api/2024-04/products.json';
            method   = 'POST';
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            Map<String, Object> body    = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> product = (Map<String, Object>) body.get('product');
            return (product != null && product.get('id') != null)
                ? String.valueOf(product.get('id'))
                : null;
        }

        if (res.getStatusCode() == 429) {
            String retryAfterHeader = res.getHeader('Retry-After');
            if (String.isNotBlank(retryAfterHeader)) {
                try { retryAfterSeconds = Integer.valueOf(retryAfterHeader.trim()); } catch (Exception e) {}
            }
            return '__rate_limited__';
        }

        ErrorLogUtility.logCalloutFailure(
            'Shopify',
            'ShopifyProductsOutboundBatch.upsertToShopify',
            'Shopify products API returned ' + res.getStatusCode() + ': ' + res.getBody(),
            res.getStatusCode(),
            null,
            null
        );
        throw new CalloutException('Shopify products API returned ' + res.getStatusCode() + ': ' + res.getBody());
    }

}