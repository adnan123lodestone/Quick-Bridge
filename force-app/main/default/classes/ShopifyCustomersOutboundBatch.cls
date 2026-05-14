global class ShopifyCustomersOutboundBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    private Set<Id> recordIds;
    private Boolean isInitialSync;
    private Integer successCount = 0;
    private Integer errorCount = 0;

    @TestVisible private static Boolean bypassAuthCheckForTest = false;

    global ShopifyCustomersOutboundBatch(Set<Id> recordIds, Boolean isInitialSync) {
        this.recordIds = recordIds;
        this.isInitialSync = isInitialSync;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, PersonEmail, FirstName, LastName, Phone, Shopify_ID__c,
                   Tax_Exempt__c, Shopify_Tags__c,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account
            WHERE Id IN :recordIds
        ]);
    }

    global void execute(Database.BatchableContext bc, List<sObject> scope) {
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            System.debug('Skipping ShopifyCustomersOutboundBatch — Shopify license not active.');
            return;
        }

        IntegrationUsageService.assertCanConsumeTask('Shopify', scope == null ? 1 : scope.size());

        Map<String, String> fieldMap = ShopifyObjectMappings.getAccountToCustomerMapping();
        List<Account> toUpdate = new List<Account>();

        for (sObject sobj : scope) {
            Account acc = (Account) sobj;
            try {
                Map<String, Object> payload = buildCustomerPayload(acc, fieldMap);
                String responseId = upsertToShopify(acc.Shopify_ID__c, payload);
                if (String.isNotBlank(responseId)) {
                    acc.Shopify_ID__c = responseId;
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

    private String upsertToShopify(String existingShopifyId, Map<String, Object> payload) {
        String endpoint;
        String method;

        if (String.isNotBlank(existingShopifyId)) {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/customers/' + existingShopifyId + '.json';
            method = 'PUT';
        } else {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/customers.json';
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