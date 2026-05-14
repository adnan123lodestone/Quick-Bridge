global class ShopifyOrdersBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {

    private String endpoint;
    private String nextUrl;

    public ShopifyOrdersBatch(String endpoint) {
        this.endpoint = endpoint;
    }

    public ShopifyOrdersBatch() {
    }

    global Iterable<Integer> start(Database.BatchableContext BC) {
        return new List<Integer>{1};
    }

    global void execute(Database.BatchableContext BC, List<Integer> scope) {

        if (!PaymentGatewayService.isClientAuthorized('Shopify')) {
            System.debug('Skipping execution. Shopify license not active.');
            return;
        }

        IntegrationUsageService.assertCanConsumeTask('Shopify', 1);

        try {
            API_Callout_Control__mdt calloutControl = getCalloutControl();
            if (!calloutControl.Allow_Callouts__c) {
                System.debug('Callouts not allowed.');
                return;
            }

            String finalEndpoint;
            Integer daysAgo = calloutControl.Days__c != null ? Integer.valueOf(calloutControl.Days__c) : 0;

            if (String.isBlank(this.endpoint)) {
                finalEndpoint = 'callout:QuickBridgeTLG__Shopify_API/orders.json?status=any';
                if (daysAgo > 0) {
                    finalEndpoint += '&updated_at_min=' + getPastDateTimeFormatted(daysAgo);
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

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() != 200) {
                System.debug('HTTP callout failed: ' + res.getStatusCode());
                ErrorLogUtility.logCalloutFailure(
                    'Shopify',
                    'ShopifyOrdersBatch.execute',
                    'Shopify orders API returned HTTP ' + res.getStatusCode() + ': ' + res.getBody(),
                    res.getStatusCode(),
                    null,
                    null
                );
                return;
            }

            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> orders = (List<Object>) jsonResponse.get('orders');
            if (orders == null) orders = new List<Object>();

            Set<String> emailSet      = new Set<String>();
            Set<String> shopifyIdSet  = new Set<String>();
            Set<String> locationIdSet = new Set<String>();

            for (Object obj : orders) {
                Map<String, Object> orderMap = (Map<String, Object>) obj;
                Map<String, Object> customer = (Map<String, Object>) orderMap.get('customer');
                String locationId = orderMap.get('location_id') != null ? String.valueOf(orderMap.get('location_id')) : null;
                if (locationId != null) locationIdSet.add(locationId);
                if (customer != null) {
                    String email = (String) customer.get('email');
                    if (email != null) emailSet.add(email.toLowerCase());
                    Object custId = customer.get('id');
                    if (custId != null) shopifyIdSet.add(String.valueOf(custId));
                }
            }

            Id personAccountRTId = getPersonAccountRecordTypeId();
            Map<String, Account> existingByEmail     = new Map<String, Account>();
            Map<String, Account> existingByShopifyId = new Map<String, Account>();
            Map<String, String>  locationIdMap       = new Map<String, String>();

            if (!locationIdSet.isEmpty()) {
                for (Schema.Location loc : [SELECT Id, Name, Shopify_ID__c FROM Location WHERE Shopify_ID__c IN :locationIdSet]) {
                    if (loc.Shopify_ID__c != null) locationIdMap.put(loc.Shopify_ID__c, loc.Id);
                }
            }

            if (!emailSet.isEmpty()) {
                for (Account acc : [SELECT Id, PersonEmail, Shopify_ID__c FROM Account WHERE RecordTypeId = :personAccountRTId AND PersonEmail IN :emailSet]) {
                    if (acc.PersonEmail != null) existingByEmail.put(acc.PersonEmail.toLowerCase(), acc);
                }
            }

            if (!shopifyIdSet.isEmpty()) {
                for (Account acc : [SELECT Id, PersonEmail, Shopify_ID__c FROM Account WHERE RecordTypeId = :personAccountRTId AND Shopify_ID__c IN :shopifyIdSet]) {
                    if (acc.Shopify_ID__c != null) existingByShopifyId.put(acc.Shopify_ID__c, acc);
                }
            }

            List<Account> accountsToUpsert  = new List<Account>();
            Set<String>   processedShopifyIds = new Set<String>();

            for (Object obj : orders) {
                Map<String, Object> orderMap = (Map<String, Object>) obj;
                Map<String, Object> customer = (Map<String, Object>) orderMap.get('customer');
                if (customer != null) {
                    String email     = (String) customer.get('email');
                    String shopifyId = customer.get('id') != null ? String.valueOf(customer.get('id')) : null;
                    if (!String.isBlank(shopifyId) && !processedShopifyIds.contains(shopifyId)) {
                        Account acc;
                        if (existingByShopifyId.containsKey(shopifyId)) {
                            acc = existingByShopifyId.get(shopifyId);
                        } else if (email != null && existingByEmail.containsKey(email.toLowerCase())) {
                            acc = existingByEmail.get(email.toLowerCase());
                        } else {
                            acc = new Account();
                            acc.RecordTypeId = personAccountRTId;
                            acc.PersonEmail  = email;
                        }
                        acc.Shopify_ID__c = shopifyId;
                        acc.FirstName     = (String) customer.get('first_name');
                        acc.LastName      = String.isNotBlank((String) customer.get('last_name')) ? (String) customer.get('last_name') : acc.FirstName;
                        acc.Phone         = (String) customer.get('phone');
                        accountsToUpsert.add(acc);
                        processedShopifyIds.add(shopifyId);
                    }
                }
            }

            if (!accountsToUpsert.isEmpty()) {
                Database.UpsertResult[] accountResults = Database.upsert(accountsToUpsert, false);
                ErrorLogUtility.logUpsertResults(
                    'Shopify',
                    'ShopifyOrdersBatch.execute.upsertAccounts',
                    'upsert',
                    accountsToUpsert,
                    accountResults,
                    null,
                    null
                );
            }

            Map<String, String> orderFieldMap   = ShopifyObjectMappings.getShopifyToOrderMapping();
            Map<String, String> lineItemFieldMap = ShopifyObjectMappings.getLineItemMapping();

            List<Order> ordersToUpsert    = new List<Order>();
            Map<String, Id> emailToAccountId = new Map<String, Id>();
            for (Account acc : accountsToUpsert) {
                if (String.isNotBlank(acc.PersonEmail)) {
                    emailToAccountId.put(acc.PersonEmail.toLowerCase(), acc.Id);
                }
            }

            for (Object obj : orders) {
                Map<String, Object> orderMap = (Map<String, Object>) obj;
                Map<String, Object> customer = (Map<String, Object>) orderMap.get('customer');
                if (customer == null) continue;
                String email     = (String) customer.get('email');
                Id     accountId = email != null ? emailToAccountId.get(email.toLowerCase()) : null;
                if (accountId == null) continue;

                Order ord = new Order();
                ord.AccountId   = accountId;
                ord.Status      = 'Draft';
                ord.Pricebook2Id = getStdPricebookId();

                for (String shopifyField : orderFieldMap.keySet()) {
                    String sfField = orderFieldMap.get(shopifyField);
                    Object val     = orderMap.get(shopifyField);
                    if (val == null) continue;
                    try {
                        if (sfField == 'EffectiveDate') {
                            ord.EffectiveDate = Date.valueOf(String.valueOf(val).substring(0, 10));
                        } else if (sfField == 'Total_Amount__c' || sfField == 'Total_Tax__c' || sfField == 'Total_Discounts__c') {
                            ord.put(sfField, Decimal.valueOf(String.valueOf(val)));
                        } else {
                            ord.put(sfField, val);
                        }
                    } catch (Exception ex) {
                        System.debug('Order field mapping error ' + sfField + ': ' + ex.getMessage());
                    }
                }

                ord.Shopify_ID__c = String.valueOf(orderMap.get('id'));
                if (ord.EffectiveDate == null) ord.EffectiveDate = System.today();

                if (!orderFieldMap.containsKey('buyer_accepts_marketing'))
                    ord.Buyer_Accepts_Marketing__c = (Boolean) orderMap.get('buyer_accepts_marketing');
                if (!orderFieldMap.containsKey('cart_token'))
                    ord.Cart_Token__c = (String) orderMap.get('cart_token');
                if (!orderFieldMap.containsKey('checkout_id') && orderMap.get('checkout_id') != null)
                    ord.Checkout_Id__c = String.valueOf(orderMap.get('checkout_id'));
                if (!orderFieldMap.containsKey('confirmation_number'))
                    ord.Confirmation_Number__c = (String) orderMap.get('confirmation_number');
                if (!orderFieldMap.containsKey('estimated_taxes'))
                    ord.Estimated_Taxes__c = (Boolean) orderMap.get('estimated_taxes');
                if (!orderFieldMap.containsKey('order_status_url'))
                    ord.Order_Status_Url__c = (String) orderMap.get('order_status_url');
                if (!orderFieldMap.containsKey('po_number'))
                    ord.PoNumber = (String) orderMap.get('po_number');
                if (!orderFieldMap.containsKey('presentment_currency'))
                    ord.Currency__c = (String) orderMap.get('presentment_currency');
                if (!orderFieldMap.containsKey('reference'))
                    ord.Reference__c = (String) orderMap.get('reference');
                if (!orderFieldMap.containsKey('referring_site'))
                    ord.Referring_Site__c = (String) orderMap.get('referring_site');
                if (!orderFieldMap.containsKey('source_name'))
                    ord.Source_Name__c = (String) orderMap.get('source_name');
                if (!orderFieldMap.containsKey('source_url'))
                    ord.Source_Url__c = (String) orderMap.get('source_url');
                if (!orderFieldMap.containsKey('order_number') && orderMap.get('order_number') != null)
                    ord.Order_Number__c = Integer.valueOf(String.valueOf(orderMap.get('order_number')));
                if (!orderFieldMap.containsKey('tags'))
                    ord.Order_Tags__c = (String) orderMap.get('tags');
                if (!orderFieldMap.containsKey('tax_exempt'))
                    ord.Order_Tax_Exempt__c = (Boolean) orderMap.get('tax_exempt');
                if (!orderFieldMap.containsKey('taxes_included'))
                    ord.Taxes_Included__c = (Boolean) orderMap.get('taxes_included');
                if (!orderFieldMap.containsKey('total_tip_received') && orderMap.get('total_tip_received') != null)
                    ord.Total_Tip__c = Decimal.valueOf(String.valueOf(orderMap.get('total_tip_received')));
                if (!orderFieldMap.containsKey('total_weight') && orderMap.get('total_weight') != null)
                    ord.Total_Weight__c = Integer.valueOf(String.valueOf(orderMap.get('total_weight')));
                if (!orderFieldMap.containsKey('payment_gateway_names')) {
                    List<Object> gateways = (List<Object>) orderMap.get('payment_gateway_names');
                    ord.Payment_Gateway__c = (gateways != null && !gateways.isEmpty()) ? (String) gateways[0] : null;
                }
                if (!orderFieldMap.containsKey('cancelled_at') && orderMap.get('cancelled_at') != null) {
                    ord.Cancelled_At__c = Datetime.valueOfGmt(((String) orderMap.get('cancelled_at')).replace('T', ' ').replaceAll('[+-]\\d{2}:\\d{2}', ''));
                }
                if (!orderFieldMap.containsKey('processed_at') && orderMap.get('processed_at') != null) {
                    ord.Processed_At__c = Datetime.valueOfGmt(((String) orderMap.get('processed_at')).replace('T', ' ').replaceAll('[+-]\\d{2}:\\d{2}', ''));
                }

                String locationId = orderMap.get('location_id') != null ? String.valueOf(orderMap.get('location_id')) : null;
                if (locationIdMap.containsKey(locationId)) {
                    ord.Location__c = locationIdMap.get(locationId);
                }

                ordersToUpsert.add(ord);
            }

            if (!ordersToUpsert.isEmpty()) {
                try {
                    upsert ordersToUpsert Shopify_ID__c;
                } catch (DmlException e) {
                    logShopifyDmlException(
                        'ShopifyOrdersBatch.execute.upsertOrders',
                        'upsert',
                        ordersToUpsert,
                        e,
                        'Order'
                    );
                    // Do not re-throw: outer catch would create a duplicate log entry
                    return;
                }
            }

            // Build order lookup for OrderItem creation
            Map<String, Order> externalIdToOrder = new Map<String, Order>();
            for (Order o : ordersToUpsert) {
                externalIdToOrder.put(o.Shopify_ID__c, o);
            }

            // Collect product_ids referenced by line items, then look up Product2 and PricebookEntries
            Set<String> productShopifyIds = new Set<String>();
            for (Object obj : orders) {
                Map<String, Object> orderMap = (Map<String, Object>) obj;
                List<Object> lineItems = (List<Object>) orderMap.get('line_items');
                if (lineItems != null) {
                    for (Object itemObj : lineItems) {
                        Map<String, Object> li = (Map<String, Object>) itemObj;
                        Object pid = li.get('product_id');
                        if (pid != null) productShopifyIds.add(String.valueOf(pid));
                    }
                }
            }

            Map<String, Id> shopifyIdToProductId = new Map<String, Id>();
            if (!productShopifyIds.isEmpty()) {
                for (Product2 p : [SELECT Id, Shopify_ID__c FROM Product2 WHERE Shopify_ID__c IN :productShopifyIds]) {
                    shopifyIdToProductId.put(p.Shopify_ID__c, p.Id);
                }
            }

            Map<Id, Id> productToPBE = new Map<Id, Id>();
            if (!shopifyIdToProductId.isEmpty()) {
                Set<Id> foundProductIds = new Set<Id>(shopifyIdToProductId.values());
                for (PricebookEntry pbe : [SELECT Id, Product2Id FROM PricebookEntry
                                           WHERE Pricebook2Id = :getStdPricebookId()
                                           AND Product2Id IN :foundProductIds]) {
                    productToPBE.put(pbe.Product2Id, pbe.Id);
                }
            }

            List<OrderItem> orderItemsToUpsert = new List<OrderItem>();
            for (Object obj : orders) {
                Map<String, Object> orderMap    = (Map<String, Object>) obj;
                String              orderExtId  = String.valueOf(orderMap.get('id'));
                Order               ord         = externalIdToOrder.get(orderExtId);
                if (ord == null) continue;

                List<Object> lineItems = (List<Object>) orderMap.get('line_items');
                if (lineItems == null) continue;

                for (Object itemObj : lineItems) {
                    Map<String, Object> productMap    = (Map<String, Object>) itemObj;
                    String              productShopifyId = productMap.get('product_id') != null
                        ? String.valueOf(productMap.get('product_id')) : null;

                    if (String.isBlank(productShopifyId) || !shopifyIdToProductId.containsKey(productShopifyId)) continue;

                    Id productId = shopifyIdToProductId.get(productShopifyId);
                    Id pbeId     = productToPBE.get(productId);
                    if (pbeId == null) continue;

                    OrderItem orderItem = new OrderItem();
                    orderItem.OrderId          = ord.Id;
                    orderItem.Product2Id       = productId;
                    orderItem.PricebookEntryId = pbeId;

                    for (String shopifyField : lineItemFieldMap.keySet()) {
                        String sfField = lineItemFieldMap.get(shopifyField);
                        Object val     = productMap.get(shopifyField);
                        if (val == null) continue;
                        try {
                            if (sfField == 'Quantity') {
                                orderItem.Quantity = Integer.valueOf(String.valueOf(val));
                            } else if (sfField == 'UnitPrice') {
                                orderItem.UnitPrice = Decimal.valueOf(String.valueOf(val));
                            } else {
                                orderItem.put(sfField, val);
                            }
                        } catch (Exception ex) {
                            System.debug('LineItem field mapping error ' + sfField + ': ' + ex.getMessage());
                        }
                    }

                    orderItem.Shopify_ID__c = String.valueOf(productMap.get('id'));
                    if (orderItem.Quantity  == null) orderItem.Quantity  = 1;
                    if (orderItem.UnitPrice == null) orderItem.UnitPrice = 0;

                    orderItemsToUpsert.add(orderItem);
                }
            }

            if (!orderItemsToUpsert.isEmpty()) {
                try {
                    upsert orderItemsToUpsert Shopify_ID__c;
                } catch (DmlException e) {
                    logShopifyDmlException(
                        'ShopifyOrdersBatch.execute.upsertOrderItems',
                        'upsert',
                        orderItemsToUpsert,
                        e,
                        'OrderItem'
                    );
                    // Do not re-throw: outer catch would create a duplicate log entry
                    return;
                }
            }

            this.nextUrl = getNextPageUrl(res);

        } catch (Exception e) {
            ErrorLogUtility.logException(
                'Shopify',
                'ShopifyOrdersBatch.execute',
                e,
                null,
                null
            );
        }
    }

    global void finish(Database.BatchableContext BC) {
        if (String.isNotBlank(this.nextUrl)) {
            Database.executeBatch(new ShopifyOrdersBatch(this.nextUrl), 1);
        } else {
            System.debug('No nextUrl. All Shopify orders processed.');
        }
    }

    private API_Callout_Control__mdt getCalloutControl() {
        return [SELECT Allow_Callouts__c, Days__c FROM API_Callout_Control__mdt WHERE MasterLabel = 'Shopify - Order' AND Endpoint__c = 'order' LIMIT 1];
    }

    private Id getPersonAccountRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND Name = 'Person Account' LIMIT 1].Id;
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