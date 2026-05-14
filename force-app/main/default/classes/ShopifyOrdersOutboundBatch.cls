global class ShopifyOrdersOutboundBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    private Set<Id> recordIds;
    private Boolean isInitialSync;
    private Integer successCount = 0;
    private Integer errorCount = 0;

    @TestVisible private static Boolean bypassAuthCheckForTest = false;

    global ShopifyOrdersOutboundBatch(Set<Id> recordIds, Boolean isInitialSync) {
        this.recordIds = recordIds;
        this.isInitialSync = isInitialSync;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, OrderReferenceNumber, EffectiveDate, Status, Shopify_ID__c,
                   Financial_Status__c, Fulfillment_Status__c,
                   Total_Amount__c, Total_Tax__c, Total_Discounts__c,
                   Contact_Email__c, Cancel_Reason__c, Payment_Gateway__c,
                   Account.PersonEmail, Account.Shopify_ID__c
            FROM Order
            WHERE Id IN :recordIds
        ]);
    }

    global void execute(Database.BatchableContext bc, List<sObject> scope) {
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            System.debug('Skipping ShopifyOrdersOutboundBatch — Shopify license not active.');
            return;
        }

        IntegrationUsageService.assertCanConsumeTask('Shopify', scope == null ? 1 : scope.size());

        Map<String, String> fieldMap = ShopifyObjectMappings.getOrderToShopifyMapping();
        List<Order> toUpdate = new List<Order>();

        for (sObject sobj : scope) {
            Order ord = (Order) sobj;
            try {
                Map<String, Object> payload = buildOrderPayload(ord, fieldMap);
                String responseId = upsertToShopify(ord.Shopify_ID__c, payload);
                if (String.isNotBlank(responseId)) {
                    ord.Shopify_ID__c = responseId;
                    toUpdate.add(ord);
                    successCount++;
                }
            } catch (Exception e) {
                errorCount++;
                ErrorLogUtility.logException(
                    'Shopify',
                    'ShopifyOrdersOutboundBatch.execute',
                    e,
                    'Order',
                    ord == null ? null : ord.Id
                );
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(toUpdate, false);
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
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('ShopifyOrdersOutboundBatch complete. Success: ' + successCount + ' | Errors: ' + errorCount);
        IntegrationUsageService.recordSuccessfulRecordSync('Shopify', successCount);
        IntegrationUsageService.incrementEndpointUsage('Shopify', successCount + errorCount);
    }

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

        String accountShopifyId = (String) ord.getSObject('Account')?.get('Shopify_ID__c');
        String accountEmail = (String) ord.getSObject('Account')?.get('PersonEmail');

        if (String.isNotBlank(accountShopifyId)) {
            order.put('customer', new Map<String, Object>{ 'id' => Long.valueOf(accountShopifyId) });
        } else if (String.isNotBlank(accountEmail)) {
            order.put('email', accountEmail);
        }

        return new Map<String, Object>{ 'order' => order };
    }

    private String upsertToShopify(String existingShopifyId, Map<String, Object> payload) {
        String endpoint;
        String method;

        if (String.isNotBlank(existingShopifyId)) {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/orders/' + existingShopifyId + '.json';
            method = 'PUT';
        } else {
            endpoint = 'callout:QuickBridgeTLG__Shopify_API/orders.json';
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

        ErrorLogUtility.logCalloutFailure(
            'Shopify',
            'ShopifyOrdersOutboundBatch.upsertToShopify',
            'Shopify orders API returned ' + res.getStatusCode() + ': ' + res.getBody(),
            res.getStatusCode(),
            null,
            null
        );
        throw new CalloutException('Shopify orders API returned ' + res.getStatusCode() + ': ' + res.getBody());
    }

}