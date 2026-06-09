global class ShopifyCustomersOutboundBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

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

    global ShopifyCustomersOutboundBatch(Set<Id> recordIds, Boolean isInitialSync) {
        this.recordIds = recordIds;
        this.isInitialSync = isInitialSync;
        this.fieldMap = ShopifyObjectMappings.getAccountToCustomerMapping();
        this.shopifyIdField = resolveFieldName(Schema.SObjectType.Account.fields.getMap(), 'shopify_id__c');
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
        // Bare standard field keys — these resolve directly regardless of namespace
        Set<String> fieldSet = new Set<String>{
            'id', 'personemail', 'firstname', 'lastname', 'phone',
            'billingstreet', 'billingcity', 'billingstate', 'billingpostalcode', 'billingcountry'
        };
        for (String sfField : fieldMap.keySet()) {
            if (accountFields.containsKey(sfField.toLowerCase())) {
                fieldSet.add(sfField.toLowerCase());
            }
        }
        // Resolve bare keys to canonical API names
        Set<String> selected = new Set<String>{ shopifyIdField };
        for (String key : fieldSet) {
            Schema.SObjectField f = accountFields.get(key);
            if (f != null) selected.add(f.getDescribe().getName());
        }
        String soql = 'SELECT ' + String.join(new List<String>(selected), ', ') +
                      ' FROM Account WHERE Id IN :recordIds';
        return Database.getQueryLocator(soql);
    }

    global void execute(Database.BatchableContext bc, List<sObject> scope) {
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            System.debug('Skipping ShopifyCustomersOutboundBatch — Shopify license not active.');
            return;
        }

        IntegrationUsageService.assertCanConsumeTask('Shopify', scope == null ? 1 : scope.size());
        List<Account> toUpdate = new List<Account>();

        Boolean rateLimited = false;
        for (sObject sobj : scope) {
            Account acc = (Account) sobj;
            if (rateLimited) {
                rateLimitedIds.add(acc.Id);
                continue;
            }
            try {
                Map<String, Object> payload = buildCustomerPayload(acc, fieldMap);
                String responseId = upsertToShopify((String) acc.get(shopifyIdField), payload);
                if (responseId == '__rate_limited__') {
                    rateLimited = true;
                    hitRateLimit = true;
                    rateLimitedIds.add(acc.Id);
                } else if (String.isNotBlank(responseId)) {
                    acc.put(shopifyIdField, responseId);
                    toUpdate.add(acc);
                    successCount++;
                }
            } catch (Exception e) {
                errorCount++;
                ErrorLogUtility.logException(
                    'Shopify',
                    'ShopifyCustomersOutboundBatch.execute',
                    e,
                    'Account',
                    acc == null ? null : acc.Id
                );
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(toUpdate, false);
            ErrorLogUtility.logDmlResults(
                'Shopify',
                'ShopifyCustomersOutboundBatch.execute.updateShopifyIds',
                'update',
                toUpdate,
                updateResults,
                null,
                null
            );
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('ShopifyCustomersOutboundBatch complete. Success: ' + successCount + ' | Errors: ' + errorCount);
        IntegrationUsageService.recordSuccessfulRecordSync('Shopify', successCount);
        IntegrationUsageService.incrementEndpointUsage('Shopify', successCount + errorCount);
        if (hitRateLimit && !rateLimitedIds.isEmpty()) {
            Integer delayMinutes = (Integer) Math.max(1, Math.ceil(retryAfterSeconds / 60.0));
            System.scheduleBatch(
                new ShopifyCustomersOutboundBatch(rateLimitedIds, isInitialSync),
                'ShopifyCustomersOutboundBatch_RateLimit_Retry_' + Datetime.now().getTime(),
                delayMinutes
            );
        }
    }

    private Map<String, Object> buildCustomerPayload(Account acc, Map<String, String> fieldMap) {
        Map<String, Object> customer = new Map<String, Object>();
        Map<String, Object> address = new Map<String, Object>();
        Boolean hasAddress = false;

        for (String sfField : fieldMap.keySet()) {
            String shopifyPath = fieldMap.get(sfField);
            Object val = acc.get(sfField);
            if (val == null) continue;

            if (shopifyPath.startsWith('default_address.')) {
                address.put(shopifyPath.substringAfter('default_address.'), val);
                hasAddress = true;
            } else {
                customer.put(shopifyPath, val);
            }
        }

        if (hasAddress) customer.put('addresses', new List<Object>{ address });
        return new Map<String, Object>{ 'customer' => customer };
    }

    // Returns the canonical API name (with namespace if present) for a field looked up by bare local name.
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
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/admin/api/2024-04/customers/' + existingShopifyId + '.json';
            method = 'PUT';
        } else {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/admin/api/2024-04/customers.json';
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
            Map<String, Object> customer = (Map<String, Object>) body.get('customer');
            return customer != null && customer.get('id') != null
                ? String.valueOf(customer.get('id'))
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
            'ShopifyCustomersOutboundBatch.upsertToShopify',
            'Shopify customers API returned ' + res.getStatusCode() + ': ' + res.getBody(),
            res.getStatusCode(),
            null,
            null
        );
        throw new CalloutException('Shopify customers API returned ' + res.getStatusCode() + ': ' + res.getBody());
    }

}