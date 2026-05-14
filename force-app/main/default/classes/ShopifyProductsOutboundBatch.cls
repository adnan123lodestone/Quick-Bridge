global class ShopifyProductsOutboundBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    private Set<Id> recordIds;
    private Boolean isInitialSync;
    private Integer successCount = 0;
    private Integer errorCount = 0;

    @TestVisible private static Boolean bypassAuthCheckForTest = false;

    global ShopifyProductsOutboundBatch(Set<Id> recordIds, Boolean isInitialSync) {
        this.recordIds    = recordIds;
        this.isInitialSync = isInitialSync;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, StockKeepingUnit, IsActive, Shopify_ID__c
            FROM Product2
            WHERE Id IN :recordIds
        ]);
    }

    global void execute(Database.BatchableContext bc, List<sObject> scope) {
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            System.debug('Skipping ShopifyProductsOutboundBatch — Shopify license not active.');
            return;
        }

        IntegrationUsageService.assertCanConsumeTask('Shopify', scope == null ? 1 : scope.size());

        Map<String, String> fieldMap = ShopifyObjectMappings.getProductToShopifyMapping();
        List<Product2> toUpdate = new List<Product2>();

        for (sObject sobj : scope) {
            Product2 prod = (Product2) sobj;
            try {
                Map<String, Object> payload = buildProductPayload(prod, fieldMap);
                String responseId = upsertToShopify(prod.Shopify_ID__c, payload);
                if (String.isNotBlank(responseId)) {
                    prod.Shopify_ID__c = responseId;
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

    private String upsertToShopify(String existingShopifyId, Map<String, Object> payload) {
        String endpoint;
        String method;

        if (String.isNotBlank(existingShopifyId)) {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/products/' + existingShopifyId + '.json';
            method   = 'PUT';
        } else {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/products.json';
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