global class ShopifyOrdersOutboundBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    private Set<Id> recordIds;
    private Boolean isInitialSync;
    private Integer successCount = 0;
    private Integer errorCount = 0;
    private Map<String, String> fieldMap;
    private String shopifyIdField;
    private String acctShopifyIdField;

    // Rate-limit state — populated when Shopify returns 429 mid-execute
    private Set<Id> rateLimitedIds = new Set<Id>();
    private Integer retryAfterSeconds = 60;
    private Boolean hitRateLimit = false;
    private String sharedErrorSummary;
    private Integer sharedDmlFailureCount = 0;

    @TestVisible private static Boolean bypassAuthCheckForTest = false;
    @testVisible private static Boolean suppressFinishSchedule = false;
    @TestVisible private static Map<String, String> testFieldMap;
    @TestVisible private static Map<String, String> testLineItemFieldMap;
    // Lightweight error context collected during callout loop, flushed after all callouts.
    private class PendingError {
        String method;
        Exception ex;
        String message;
        Integer httpStatus;
        Id recordId;
        Boolean isCallout;

        PendingError(String method, Exception ex, Id recordId) {
            this.method   = method;
            this.ex       = ex;
            this.recordId = recordId;
            this.isCallout = false;
        }

        PendingError(String method, String message, Integer httpStatus, Id recordId) {
            this.method     = method;
            this.message    = message;
            this.httpStatus = httpStatus;
            this.recordId   = recordId;
            this.isCallout  = true;
        }
    }

    private Map<String, String> lineItemFieldMap;

    global ShopifyOrdersOutboundBatch(Set<Id> recordIds, Boolean isInitialSync) {
        this.recordIds = recordIds;
        this.isInitialSync = isInitialSync;
        this.fieldMap = Test.isRunningTest() && testFieldMap != null
            ? new Map<String, String>(testFieldMap)
            : ShopifyObjectMappings.getOrderToShopifyMapping();
        this.lineItemFieldMap = Test.isRunningTest() && testLineItemFieldMap != null
            ? new Map<String, String>(testLineItemFieldMap)
            : ShopifyObjectMappings.getOrderItemToLineItemMapping();
        this.shopifyIdField = resolveFieldName(Schema.SObjectType.Order.fields.getMap(), 'shopify_id__c');
        this.acctShopifyIdField = resolveFieldName(Schema.SObjectType.Account.fields.getMap(), 'shopify_id__c');
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(sourceQuery());
    }

    private String sourceQuery() {
        Map<String, Schema.SObjectField> orderFields = Schema.SObjectType.Order.fields.getMap();
        Set<String> fieldSet = new Set<String>{
            'id', 'orderreferencenumber', 'effectivedate', 'status'
        };
        for (String sfField : fieldMap.keySet()) {
            String lower = sfField.toLowerCase();
            // Skip relationship paths (e.g. Account.PersonEmail) — handled via getSObject separately
            if (!lower.contains('.') && orderFields.containsKey(lower)) {
                fieldSet.add(lower);
            }
        }
        Set<String> selected = new Set<String>{ shopifyIdField };
        for (String key : fieldSet) {
            Schema.SObjectField f = orderFields.get(key);
            if (f != null) selected.add(f.getDescribe().getName());
        }
        String soql = 'SELECT ' + String.join(new List<String>(selected), ', ') +
                      ', Account.PersonEmail, Account.' + acctShopifyIdField +
                      ', (SELECT Id, Quantity, UnitPrice, Description,' +
                      ' Product2.Name, Product2.StockKeepingUnit FROM OrderItems)' +
                      ' FROM Order WHERE Id IN :recordIds';
        return soql;
    }

    global void execute(Database.BatchableContext bc, List<sObject> scope) {
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            System.debug('Skipping ShopifyOrdersOutboundBatch — Shopify license not active.');
            return;
        }

        List<Order> toUpdate       = new List<Order>();
        List<PendingError> errors  = new List<PendingError>();

        // ── Phase 1: callouts only — no DML ──────────────────────────────────────
        Boolean rateLimited = false;
        for (sObject sobj : scope) {
            Order ord = (Order) sobj;
            if (rateLimited) {
                rateLimitedIds.add(ord.Id);
                continue;
            }
            try {
                Map<String, Object> payload = buildOrderPayload(ord, fieldMap);
                if (payload == null) {
                    errorCount++;
                    if (String.isBlank(sharedErrorSummary)) {
                        sharedErrorSummary = 'Order has no line items and cannot be sent to Shopify';
                    }
                    errors.add(new PendingError(
                        'ShopifyOrdersOutboundBatch.execute',
                        new IllegalArgumentException('Order has no line items and cannot be sent to Shopify'),
                        ord.Id
                    ));
                    continue;
                }
                String responseId = upsertToShopify((String) ord.get(shopifyIdField), payload, errors, ord.Id);
                if (responseId == '__rate_limited__') {
                    rateLimited = true;
                    hitRateLimit = true;
                    rateLimitedIds.add(ord.Id);
                } else if (String.isNotBlank(responseId)) {
                    ord.put(shopifyIdField, responseId);
                    toUpdate.add(ord);
                    successCount++;
                }
            } catch (Exception e) {
                errorCount++;
                if (String.isBlank(sharedErrorSummary)) sharedErrorSummary = e.getMessage();
                errors.add(new PendingError(
                    'ShopifyOrdersOutboundBatch.execute', e, ord == null ? null : ord.Id
                ));
            }
        }

        // ── Phase 2: DML — all callouts are finished ──────────────────────────────
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(toUpdate, false);
            for (Integer resultIndex = 0; resultIndex < updateResults.size(); resultIndex++) {
                if (!updateResults[resultIndex].isSuccess()) {
                    sharedDmlFailureCount++;
                    if (String.isBlank(sharedErrorSummary)) {
                        sharedErrorSummary =
                            'Salesforce ID update failed for Order ' +
                            String.valueOf(toUpdate[resultIndex].Id) + ': ' +
                            updateResults[resultIndex].getErrors()[0].getMessage();
                    }
                }
            }
            ErrorLogUtility.logDmlResults(
                'Shopify',
                'ShopifyOrdersOutboundBatch.execute.updateShopifyIds',
                'update',
                toUpdate,
                updateResults,
                null,
                null
            );
        }

        for (PendingError pe : errors) {
            if (pe.isCallout) {
                ErrorLogUtility.logCalloutFailure(
                    'Shopify', pe.method, pe.message, pe.httpStatus, 'Order', pe.recordId
                );
            } else {
                ErrorLogUtility.logException(
                    'Shopify', pe.method, pe.ex, 'Order', pe.recordId
                );
            }
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('ShopifyOrdersOutboundBatch complete. Success: ' + successCount + ' | Errors: ' + errorCount);
        IntegrationUsageService.recordSuccessfulRecordSync('Shopify', successCount);
        IntegrationUsageService.incrementEndpointUsage('Shopify', successCount + errorCount);
        
        // Never schedule a follow‑up batch during tests
        if (Test.isRunningTest() || suppressFinishSchedule) {
            return;
        }
        
        if (hitRateLimit && !rateLimitedIds.isEmpty()) {
            Integer delayMinutes = (Integer) Math.max(1, Math.ceil(retryAfterSeconds / 60.0));
            System.scheduleBatch(
                new ShopifyOrdersOutboundBatch(rateLimitedIds, isInitialSync),
                'ShopifyOrdersOutboundBatch_RateLimit_Retry_' + Datetime.now().getTime(),
                delayMinutes
            );
        }
    }

    public static ConnectorExecutionResult executeSharedScope(
        ConnectorExecutionRequest request,
        List<SObject> scope
    ) {
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            return ConnectorExecutionResult.failed(
                'Shopify license is not active.',
                false,
                null
            );
        }
        Set<Id> scopeIds = new Set<Id>();
        for (SObject recordValue : scope == null ? new List<SObject>() : scope) {
            if (recordValue != null && recordValue.Id != null) scopeIds.add(recordValue.Id);
        }
        ShopifyOrdersOutboundBatch batchValue = new ShopifyOrdersOutboundBatch(
            scopeIds,
            request != null && request.initialSync == true
        );
        Set<Id> recordIds = scopeIds;
        List<SObject> hydratedScope = scopeIds.isEmpty()
            ? new List<SObject>()
            : Database.query(batchValue.sourceQuery());
        batchValue.execute(null, hydratedScope);

        if (!bypassAuthCheckForTest) {
            IntegrationUsageService.recordSuccessfulRecordSync('Shopify', batchValue.successCount);
            IntegrationUsageService.incrementEndpointUsage(
                'Shopify',
                batchValue.successCount + batchValue.errorCount
            );
        }

        ConnectorExecutionResult result = ConnectorExecutionResult.success();
        result.processedCount = hydratedScope.size();
        result.successfulCount = Math.max(
            0,
            batchValue.successCount - batchValue.sharedDmlFailureCount
        );
        Integer unresolvedCount = Math.max(
            0,
            hydratedScope.size() -
            batchValue.successCount -
            batchValue.errorCount -
            batchValue.rateLimitedIds.size()
        );
        result.failedCount =
            batchValue.errorCount +
            batchValue.sharedDmlFailureCount +
            batchValue.rateLimitedIds.size() +
            unresolvedCount;
        result.retryable =
            batchValue.errorCount == 0 &&
            batchValue.sharedDmlFailureCount == 0 &&
            unresolvedCount == 0 &&
            !batchValue.rateLimitedIds.isEmpty();
        result.retryDelaySeconds = result.retryable ? batchValue.retryAfterSeconds : null;
        result.retryRecordIds = new List<Id>(batchValue.rateLimitedIds);
        if (
            batchValue.errorCount > 0 ||
            batchValue.sharedDmlFailureCount > 0 ||
            unresolvedCount > 0
        ) {
            result.errorSummary = String.isBlank(batchValue.sharedErrorSummary)
                ? (unresolvedCount > 0
                    ? 'Shopify order response did not include an external ID.'
                    : 'One or more Shopify order records failed to synchronize.')
                : batchValue.sharedErrorSummary;
        } else if (!batchValue.rateLimitedIds.isEmpty()) {
            result.errorSummary = 'Shopify order synchronization was rate limited.';
        }
        return result;
    }

    // Returns null when the order has no usable line items (caller must skip the callout).
    private Map<String, Object> buildOrderPayload(Order ord, Map<String, String> fieldMap) {
        Map<String, Object> order = new Map<String, Object>();

        for (String sfField : fieldMap.keySet()) {
            String shopifyPath = fieldMap.get(sfField);
            Object val;
            try {
                val = ord.get(sfField);
            } catch (Exception e) {
                continue;
            }
            if (val == null) continue;
            order.put(shopifyPath, val);
        }

        String accountShopifyId = (String) ord.getSObject('Account')?.get(acctShopifyIdField);
        String accountEmail = (String) ord.getSObject('Account')?.get('PersonEmail');

        if (String.isNotBlank(accountShopifyId)) {
            order.put('customer', new Map<String, Object>{ 'id' => Long.valueOf(accountShopifyId) });
        } else if (String.isNotBlank(accountEmail)) {
            order.put('email', accountEmail);
        }

        List<Object> lineItems = new List<Object>();
        List<OrderItem> items = ord.OrderItems;
        if (items != null) {
            for (OrderItem item : items) {
                Map<String, Object> li = new Map<String, Object>();

                // Apply dynamic field mappings (SF field → Shopify field)
                for (String sfField : lineItemFieldMap.keySet()) {
                    String shopifyField = lineItemFieldMap.get(sfField);
                    Object val;
                    try { val = item.get(sfField); } catch (Exception e) { continue; }
                    if (val == null) continue;
                    // price must be a decimal string per Shopify spec
                    if (shopifyField == 'price' && val instanceof Decimal) {
                        li.put(shopifyField, ((Decimal) val).setScale(2).toPlainString());
                    } else if (shopifyField == 'quantity' && val instanceof Decimal) {
                        li.put(shopifyField, ((Decimal) val).intValue());
                    } else {
                        li.put(shopifyField, val);
                    }
                }

                // title and sku come from Product2 relationship — not direct OrderItem fields
                String title = null;
                String sku = null;
                if (item.Product2 != null) {
                    title = item.Product2.Name;
                    sku = item.Product2.StockKeepingUnit;
                }
                if (String.isBlank(title)) title = item.Description;
                if (String.isBlank(title)) title = 'Item';
                li.put('title', title);
                if (String.isNotBlank(sku)) li.put('sku', sku);

                lineItems.add(li);
            }
        }

        if (lineItems.isEmpty()) return null;

        order.put('line_items', lineItems);
        return new Map<String, Object>{ 'order' => order };
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

    // Returns the Shopify ID on success, '__rate_limited__' on 429, null on other non-2xx.
    private String upsertToShopify(String existingShopifyId, Map<String, Object> payload, List<PendingError> errors, Id orderId) {
        String endpoint;
        String method;

        if (String.isNotBlank(existingShopifyId)) {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/admin/api/2024-04/orders/' + existingShopifyId + '.json';
            method = 'PUT';
        } else {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/admin/api/2024-04/orders.json';
            method = 'POST';
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> order = (Map<String, Object>) body.get('order');
            return order != null && order.get('id') != null
                ? String.valueOf(order.get('id'))
                : null;
        }

        if (res.getStatusCode() == 429) {
            String retryAfterHeader = res.getHeader('Retry-After');
            if (String.isNotBlank(retryAfterHeader)) {
                try { retryAfterSeconds = Integer.valueOf(retryAfterHeader.trim()); } catch (Exception e) {}
            }
            return '__rate_limited__';
        }

        String errMsg = 'Shopify orders API returned ' + res.getStatusCode() + ': ' + res.getBody();
        if (String.isBlank(sharedErrorSummary)) sharedErrorSummary = errMsg;
        errors.add(new PendingError(
            'ShopifyOrdersOutboundBatch.upsertToShopify', errMsg, res.getStatusCode(), orderId
        ));
        errorCount++;
        return null;
    }

}