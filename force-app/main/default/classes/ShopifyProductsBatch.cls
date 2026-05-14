global class ShopifyProductsBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {

    private String endpoint;
    private String nextUrl;

    @TestVisible private static Boolean bypassAuthCheckForTest = false;

    public ShopifyProductsBatch() {
    }

    public ShopifyProductsBatch(String endpoint) {
        this.endpoint = endpoint;
    }

    global Iterable<Integer> start(Database.BatchableContext bc) {
        return new List<Integer>{ 1 };
    }

    global void execute(Database.BatchableContext bc, List<Integer> scope) {
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            System.debug('Skipping ShopifyProductsBatch — Shopify license not active.');
            return;
        }

        IntegrationUsageService.assertCanConsumeTask('Shopify', 1);

        try {
            API_Callout_Control__mdt calloutControl = getCalloutControl();
            if (!calloutControl.Allow_Callouts__c) {
                System.debug('ShopifyProductsBatch — callouts not allowed.');
                return;
            }

            String finalEndpoint;
            Integer daysAgo = calloutControl.Days__c != null ? Integer.valueOf(calloutControl.Days__c) : 0;

            if (String.isBlank(this.endpoint)) {
                finalEndpoint = 'callout:QuickBridgeTLG__Shopify_API/products.json';
                if (daysAgo > 0) {
                    finalEndpoint += '?updated_at_min=' + getPastDateTimeFormatted(daysAgo);
                }
            } else {
                if (this.endpoint.contains('/admin/api/')) {
                    finalEndpoint = 'callout:QuickBridgeTLG__Shopify_API/' + this.endpoint.substringAfter('/admin/api/').replaceFirst('^[^/]+/', '');
                } else {
                    finalEndpoint = this.endpoint;
                }
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(finalEndpoint);
            req.setMethod('GET');

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() != 200) {
                System.debug('ShopifyProductsBatch HTTP error: ' + res.getStatusCode());
                ErrorLogUtility.logCalloutFailure(
                    'Shopify',
                    'ShopifyProductsBatch.execute',
                    'Shopify products API returned HTTP ' + res.getStatusCode() + ': ' + res.getBody(),
                    res.getStatusCode(),
                    null,
                    null
                );
                return;
            }

            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> products = (List<Object>) jsonResponse.get('products');
            if (products == null || products.isEmpty()) return;

            Map<String, String> fieldMap = ShopifyObjectMappings.getShopifyToProductMapping();

            // Collect existing Product2 records by Shopify_ID__c
            Set<String> shopifyIds = new Set<String>();
            for (Object obj : products) {
                Map<String, Object> p = (Map<String, Object>) obj;
                if (p.get('id') != null) shopifyIds.add(String.valueOf(p.get('id')));
            }
            Map<String, Product2> existingByShopifyId = new Map<String, Product2>();
            if (!shopifyIds.isEmpty()) {
                for (Product2 p2 : [SELECT Id, Shopify_ID__c, StockKeepingUnit FROM Product2 WHERE Shopify_ID__c IN :shopifyIds]) {
                    existingByShopifyId.put(p2.Shopify_ID__c, p2);
                }
            }

            List<Product2> productsToUpsert = new List<Product2>();
            Map<String, Decimal> shopifyIdToPrice = new Map<String, Decimal>();

            for (Object obj : products) {
                Map<String, Object> productMap = (Map<String, Object>) obj;
                String shopifyId = productMap.get('id') != null ? String.valueOf(productMap.get('id')) : null;
                String title     = (String) productMap.get('title');
                if (String.isBlank(shopifyId) || String.isBlank(title)) continue;

                Product2 prod = existingByShopifyId.containsKey(shopifyId)
                    ? existingByShopifyId.get(shopifyId)
                    : new Product2();

                // Apply dynamic field mappings
                for (String shopifyField : fieldMap.keySet()) {
                    String sfField = fieldMap.get(shopifyField);
                    Object val = productMap.get(shopifyField);
                    if (val == null) continue;
                    // status is a special conversion — handled in identity block below
                    if (sfField == 'IsActive') continue;
                    try {
                        prod.put(sfField, val);
                    } catch (Exception ex) {
                        System.debug('ShopifyProductsBatch field map error ' + sfField + ': ' + ex.getMessage());
                    }
                }

                // Always set identity fields
                prod.Shopify_ID__c = shopifyId;
                prod.Name          = title;
                prod.IsActive      = String.valueOf(productMap.get('status')) == 'active';

                // Variant: SKU and price from first variant
                List<Object> variants = (List<Object>) productMap.get('variants');
                if (variants != null && !variants.isEmpty()) {
                    Map<String, Object> firstVariant = (Map<String, Object>) variants[0];
                    String variantSku = (String) firstVariant.get('sku');
                    if (String.isNotBlank(variantSku)) prod.StockKeepingUnit = variantSku;
                    Object priceVal = firstVariant.get('price');
                    Decimal variantPrice = 0;
                    if (priceVal != null) {
                        try { variantPrice = Decimal.valueOf(String.valueOf(priceVal)); } catch (Exception e) {}
                    }
                    shopifyIdToPrice.put(shopifyId, variantPrice);
                } else {
                    shopifyIdToPrice.put(shopifyId, 0);
                }

                productsToUpsert.add(prod);
            }

            if (productsToUpsert.isEmpty()) return;

            try {
                upsert productsToUpsert Shopify_ID__c;
            } catch (DmlException e) {
                logShopifyDmlException(
                    'ShopifyProductsBatch.execute.upsertProducts',
                    'upsert',
                    productsToUpsert,
                    e,
                    'Product2'
                );
                // Do not re-throw: outer catch would create a duplicate log entry
                return;
            }

            // Ensure Standard PricebookEntry exists for each upserted product
            Id pricebookId = getStdPricebookId();
            Set<Id> upsertedIds = new Set<Id>();
            Map<String, Id> shopifyIdToProductId = new Map<String, Id>();
            for (Product2 p : productsToUpsert) {
                if (p.Id != null) {
                    upsertedIds.add(p.Id);
                    shopifyIdToProductId.put(p.Shopify_ID__c, p.Id);
                }
            }

            Map<Id, Boolean> existingPBE = new Map<Id, Boolean>();
            for (PricebookEntry pbe : [SELECT Product2Id FROM PricebookEntry WHERE Pricebook2Id = :pricebookId AND Product2Id IN :upsertedIds]) {
                existingPBE.put(pbe.Product2Id, true);
            }

            List<PricebookEntry> entriesToInsert = new List<PricebookEntry>();
            for (Product2 p : productsToUpsert) {
                if (p.Id != null && !existingPBE.containsKey(p.Id)) {
                    Decimal price = shopifyIdToPrice.containsKey(p.Shopify_ID__c) ? shopifyIdToPrice.get(p.Shopify_ID__c) : 0;
                    entriesToInsert.add(new PricebookEntry(
                        Pricebook2Id = pricebookId,
                        Product2Id   = p.Id,
                        UnitPrice    = price,
                        IsActive     = true
                    ));
                }
            }
            if (!entriesToInsert.isEmpty()) {
                try {
                    insert entriesToInsert;
                } catch (DmlException e) {
                    logShopifyDmlException(
                        'ShopifyProductsBatch.execute.insertPricebookEntries',
                        'insert',
                        entriesToInsert,
                        e,
                        'PricebookEntry'
                    );
                    // Do not re-throw: outer catch would create a duplicate log entry
                    return;
                }
            }

            this.nextUrl = getNextPageUrl(res);

        } catch (Exception e) {
            ErrorLogUtility.logException(
                'Shopify',
                'ShopifyProductsBatch.execute',
                e,
                null,
                null
            );
        }
    }

    global void finish(Database.BatchableContext bc) {
        if (String.isNotBlank(this.nextUrl)) {
            Database.executeBatch(new ShopifyProductsBatch(this.nextUrl), 1);
        } else {
            System.debug('ShopifyProductsBatch complete — no further pages.');
        }
    }

    private API_Callout_Control__mdt getCalloutControl() {
        if (Test.isRunningTest()) {
            return new API_Callout_Control__mdt(Allow_Callouts__c = true, Days__c = 0);
        }
        return [SELECT Allow_Callouts__c, Days__c FROM API_Callout_Control__mdt
                WHERE MasterLabel = 'Shopify - Product' AND Endpoint__c = 'product' LIMIT 1];
    }

    private static Id getStdPricebookId() {
        if (Test.isRunningTest()) return Test.getStandardPricebookId();
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
    }

    private static String getPastDateTimeFormatted(Integer daysAgo) {
        return Datetime.now().addDays(-daysAgo).formatGmt('yyyy-MM-dd\'T\'HH:mm:ssZ');
    }

    private static String getNextPageUrl(HttpResponse response) {
        String linkHeader = response.getHeader('link');
        if (linkHeader != null) {
            for (String link : linkHeader.split(',')) {
                if (link.contains('rel="next"')) {
                    return link.split(';')[0].replace('<', '').replace('>', '').trim();
                }
            }
        }
        return null;
    }

    private static void logShopifyDmlException(
        String classMethodName,
        String operation,
        List<SObject> records,
        DmlException exceptionRecord,
        String fallbackObjectApiName
    ) {
        Integer failureCount = exceptionRecord == null ? 0 : exceptionRecord.getNumDml();
        for (Integer index = 0; index < failureCount; index++) {
            SObject failedRecord = records != null && index < records.size() ? records[index] : null;
            Id failedRecordId = exceptionRecord.getDmlId(index);
            if (failedRecordId == null && failedRecord != null) {
                failedRecordId = (Id) failedRecord.get('Id');
            }
            String objectApiName = failedRecord == null
                ? fallbackObjectApiName
                : failedRecord.getSObjectType().getDescribe().getName();
            ErrorLogUtility.logDmlFailure(
                'Shopify',
                classMethodName,
                operation,
                objectApiName,
                failedRecordId,
                exceptionRecord.getDmlMessage(index),
                null,
                null
            );
        }
    }
}