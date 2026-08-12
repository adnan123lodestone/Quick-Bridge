global class ShopifyOrdersBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {
    
    private String endpoint;
    private String nextUrl;
    private Integer sharedProcessedCount = 0;
    private Integer sharedFailureCount = 0;
    private String sharedErrorSummary;
    private Boolean sharedRetryable = false;
    private Integer sharedRetryDelaySeconds;

    @TestVisible private static Boolean bypassAuthCheckForTest = false;
    
    public ShopifyOrdersBatch(String endpoint) {
        this.endpoint = endpoint;
    }
    
    public ShopifyOrdersBatch() {
    }
    
    global Iterable<Integer> start(Database.BatchableContext BC) {
        return new List<Integer>{1};
    }
    
    global void execute(Database.BatchableContext BC, List<Integer> scope) {
        
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            System.debug('Skipping execution. Shopify license not active.');
            return;
        }
        
        try {
            API_Callout_Control__mdt calloutControl = getCalloutControl();
            if (!calloutControl.Allow_Callouts__c) {
                System.debug('Callouts not allowed.');
                return;
            }
            
            String finalEndpoint;
            Integer daysAgo = calloutControl.Days__c != null ? Integer.valueOf(calloutControl.Days__c) : 0;
            
            if (String.isBlank(this.endpoint)) {
                finalEndpoint = 'callout:QuickBridgeTLG__Shopify_API/admin/api/2024-04/orders.json?status=any';
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
                sharedFailureCount = 1;
                sharedErrorSummary = 'Shopify orders API returned HTTP ' + res.getStatusCode() + '.';
                sharedRetryable = ConnectorInboundOperationExecutor.isRetryableStatus(
                    res.getStatusCode()
                );
                sharedRetryDelaySeconds = sharedRetryable
                    ? ConnectorInboundOperationExecutor.retryAfterSeconds(res)
                    : null;
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
            sharedProcessedCount = orders.size();
            
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

            Map<String, String> customerFieldMap = ShopifyObjectMappings.getCustomerToAccountMapping();
            Set<String> acctFields = new Set<String>{'Id', 'PersonEmail', 'Shopify_ID__c', 'RecordTypeId'};
            acctFields.addAll(customerFieldMap.values());
            String acctFieldList = String.join(new List<String>(acctFields), ', ');

            if (!locationIdSet.isEmpty()) {
                for (Schema.Location loc : [SELECT Id, Name, Shopify_ID__c FROM Location WHERE Shopify_ID__c IN :locationIdSet]) {
                    if (loc.Shopify_ID__c != null) locationIdMap.put(loc.Shopify_ID__c, loc.Id);
                }
            }

            if (!emailSet.isEmpty()) {
                for (Account acc : Database.query(
                    'SELECT ' + acctFieldList + ' FROM Account WHERE RecordTypeId = :personAccountRTId AND PersonEmail IN :emailSet'
                )) {
                    if (acc.get('PersonEmail') != null) existingByEmail.put(((String) acc.get('PersonEmail')).toLowerCase(), acc);
                }
            }

            if (!shopifyIdSet.isEmpty()) {
                for (Account acc : Database.query(
                    'SELECT ' + acctFieldList + ' FROM Account WHERE RecordTypeId = :personAccountRTId AND Shopify_ID__c IN :shopifyIdSet'
                )) {
                    if (acc.get('Shopify_ID__c') != null) existingByShopifyId.put((String) acc.get('Shopify_ID__c'), acc);
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
                        String resolvedLastName = String.isNotBlank((String) customer.get('last_name'))
                            ? (String) customer.get('last_name')
                            : acc.FirstName;
                        acc.LastName = String.isNotBlank(resolvedLastName) ? resolvedLastName : ('Customer-' + shopifyId);
                        acc.Phone         = (String) customer.get('phone');
                        accountsToUpsert.add(acc);
                        processedShopifyIds.add(shopifyId);
                    }
                }
            }
            
            if (!accountsToUpsert.isEmpty()) {
                Database.UpsertResult[] accountResults = Database.upsert(accountsToUpsert, false);
                for (Database.UpsertResult accountResult : accountResults) {
                    if (!accountResult.isSuccess()) {
                        recordSharedFailure(
                            1,
                            'A Shopify order customer could not be saved. ' +
                            firstDmlError(accountResult.getErrors())
                        );
                    }
                }
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
            Map<String, Id> emailToAccountId    = new Map<String, Id>();
            Map<String, Id> shopifyIdToAccountId = new Map<String, Id>();
            for (Account acc : accountsToUpsert) {
                if (String.isNotBlank(acc.PersonEmail)) {
                    emailToAccountId.put(acc.PersonEmail.toLowerCase(), acc.Id);
                }
                if (String.isNotBlank((String) acc.get('Shopify_ID__c'))) {
                    shopifyIdToAccountId.put((String) acc.get('Shopify_ID__c'), acc.Id);
                }
            }

            for (Object obj : orders) {
                Map<String, Object> orderMap = (Map<String, Object>) obj;
                Map<String, Object> customer = (Map<String, Object>) orderMap.get('customer');
                if (customer == null) continue;
                String email      = (String) customer.get('email');
                String shopifyId  = customer.get('id') != null ? String.valueOf(customer.get('id')) : null;
                Id accountId = email != null ? emailToAccountId.get(email.toLowerCase()) : null;
                if (accountId == null && String.isNotBlank(shopifyId)) {
                    accountId = shopifyIdToAccountId.get(shopifyId);
                }
                if (accountId == null) continue;
                
                Order ord = new Order();
                ord.AccountId   = accountId;
                ord.Status      = 'Draft';
                ord.Pricebook2Id = getStdPricebookId();
                
                for (String shopifyField : orderFieldMap.keySet()) {
                    String sfField = orderFieldMap.get(shopifyField);
                    Object val     = orderMap.get(shopifyField);
                    if (val == null) continue;
                    // endsWith is namespace-safe: dynamic mappings return QuickBridgeTLG__Total_Amount__c,
                    // fallback returns Total_Amount__c — both end with the same suffix
                    try {
                        if (sfField == 'EffectiveDate') {
                            ord.EffectiveDate = Date.valueOf(String.valueOf(val).substring(0, 10));
                        } else if (sfField.endsWith('Total_Amount__c') || sfField.endsWith('Total_Tax__c') || sfField.endsWith('Total_Discounts__c')) {
                            ord.put(sfField, Decimal.valueOf(String.valueOf(val)));
                        } else {
                            ord.put(sfField, val);
                        }
                    } catch (Exception ex) {
                        ErrorLogUtility.logException('Shopify', 'ShopifyOrdersBatch.mapOrderFields', ex, null, null);
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
                    recordSharedFailure(Math.max(1, e.getNumDml()), e.getMessage());
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
                    recordSharedFailure(Math.max(1, e.getNumDml()), e.getMessage());
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
            recordSharedFailure(1, e.getMessage());
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

    public static ConnectorExecutionResult executeSharedPage(
        ConnectorExecutionRequest request
    ) {
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            return ConnectorExecutionResult.failed(
                'Shopify license is not active.',
                false,
                null
            );
        }
        ShopifyOrdersBatch batchValue = new ShopifyOrdersBatch(
            request == null ? null : request.cursor
        );
        batchValue.execute(null, new List<Integer>{ 1 });
        ConnectorExecutionResult result = ConnectorExecutionResult.success();
        result.processedCount = batchValue.sharedProcessedCount > 0
            ? batchValue.sharedProcessedCount
            : (batchValue.sharedFailureCount > 0 ? 1 : 0);
        result.failedCount = Math.min(
            result.processedCount,
            batchValue.sharedFailureCount
        );
        result.successfulCount = Math.max(0, result.processedCount - result.failedCount);
        result.errorSummary = batchValue.sharedErrorSummary;
        result.retryable = batchValue.sharedRetryable;
        result.retryDelaySeconds = batchValue.sharedRetryDelaySeconds;
        result.nextCursor = batchValue.nextUrl;
        return result;
    }

    private void recordSharedFailure(Integer failureCount, String message) {
        sharedFailureCount += Math.max(1, failureCount == null ? 1 : failureCount);
        ConnectorExecutionResult summary = ConnectorExecutionResult.success();
        summary.errorSummary = sharedErrorSummary;
        summary.addError(message);
        sharedErrorSummary = summary.errorSummary;
    }

    private static String firstDmlError(Database.Error[] errors) {
        return errors == null || errors.isEmpty()
            ? 'No Salesforce DML diagnostic was returned.'
            : errors[0].getMessage();
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
    
    public static void syncOrderFromShopify(String orderId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:QuickBridgeTLG__Shopify_API/admin/api/2024-04/orders/' + orderId + '.json');
        req.setMethod('GET');
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> order = (Map<String, Object>) data.get('order');
            Order ord = buildOrderFromShopifyOrder(order);
            upsert ord Order.Shopify_ID__c;
        } else {
            throw new CalloutException('Shopify order not found: ' + res.getBody());
        }
    }

    private static Order buildOrderFromShopifyOrder(Map<String, Object> orderData) {
        Map<String, Object> customer = (Map<String, Object>) orderData.get('customer');
        String shopifyCustomerId = customer != null && customer.get('id') != null ? String.valueOf(customer.get('id')) : null;
        String email = customer != null ? (String) customer.get('email') : null;
        Id accountId = null;
        if (String.isNotBlank(shopifyCustomerId)) {
            List<Account> acc = [SELECT Id FROM Account WHERE Shopify_ID__c = :shopifyCustomerId LIMIT 1];
            if (!acc.isEmpty()) accountId = acc[0].Id;
        }
        if (accountId == null && String.isNotBlank(email)) {
            List<Account> acc = [SELECT Id FROM Account WHERE PersonEmail = :email LIMIT 1];
            if (!acc.isEmpty()) accountId = acc[0].Id;
        }
        if (accountId == null) {
            throw new CalloutException('No matching Salesforce Account found for Shopify customer id: ' + shopifyCustomerId + ' / email: ' + email);
        }

        Order ord = new Order();
        ord.AccountId = accountId;
        ord.Status = 'Draft';
        ord.Pricebook2Id = getStdPricebookIdStatic();

        Map<String, String> fieldMap = ShopifyObjectMappings.getShopifyToOrderMapping();
        for (String shopifyField : fieldMap.keySet()) {
            String sfField = fieldMap.get(shopifyField);
            Object val = orderData.get(shopifyField);
            if (val == null) continue;
            try {
                if (sfField == 'EffectiveDate') {
                    ord.EffectiveDate = Date.valueOf(String.valueOf(val).substring(0, 10));
                } else if (sfField.endsWith('Total_Amount__c') || sfField.endsWith('Total_Tax__c') || sfField.endsWith('Total_Discounts__c')) {
                    ord.put(sfField, Decimal.valueOf(String.valueOf(val)));
                } else {
                    ord.put(sfField, val);
                }
            } catch (Exception ex) {
                ErrorLogUtility.logException('Shopify', 'ShopifyOrdersBatch.buildOrderFromData', ex, null, null);
            }
        }

        // Additional fields from your execute method
        if (!fieldMap.containsKey('buyer_accepts_marketing'))
            ord.Buyer_Accepts_Marketing__c = (Boolean) orderData.get('buyer_accepts_marketing');
        if (!fieldMap.containsKey('cart_token'))
            ord.Cart_Token__c = (String) orderData.get('cart_token');
        if (!fieldMap.containsKey('checkout_id') && orderData.get('checkout_id') != null)
            ord.Checkout_Id__c = String.valueOf(orderData.get('checkout_id'));
        if (!fieldMap.containsKey('confirmation_number'))
            ord.Confirmation_Number__c = (String) orderData.get('confirmation_number');
        if (!fieldMap.containsKey('estimated_taxes'))
            ord.Estimated_Taxes__c = (Boolean) orderData.get('estimated_taxes');
        if (!fieldMap.containsKey('order_status_url'))
            ord.Order_Status_Url__c = (String) orderData.get('order_status_url');
        if (!fieldMap.containsKey('po_number'))
            ord.PoNumber = (String) orderData.get('po_number');
        if (!fieldMap.containsKey('presentment_currency'))
            ord.Currency__c = (String) orderData.get('presentment_currency');
        if (!fieldMap.containsKey('reference'))
            ord.Reference__c = (String) orderData.get('reference');
        if (!fieldMap.containsKey('referring_site'))
            ord.Referring_Site__c = (String) orderData.get('referring_site');
        if (!fieldMap.containsKey('source_name'))
            ord.Source_Name__c = (String) orderData.get('source_name');
        if (!fieldMap.containsKey('source_url'))
            ord.Source_Url__c = (String) orderData.get('source_url');
        if (!fieldMap.containsKey('order_number') && orderData.get('order_number') != null)
            ord.Order_Number__c = Integer.valueOf(String.valueOf(orderData.get('order_number')));
        if (!fieldMap.containsKey('tags'))
            ord.Order_Tags__c = (String) orderData.get('tags');
        if (!fieldMap.containsKey('tax_exempt'))
            ord.Order_Tax_Exempt__c = (Boolean) orderData.get('tax_exempt');
        if (!fieldMap.containsKey('taxes_included'))
            ord.Taxes_Included__c = (Boolean) orderData.get('taxes_included');
        if (!fieldMap.containsKey('total_tip_received') && orderData.get('total_tip_received') != null)
            ord.Total_Tip__c = Decimal.valueOf(String.valueOf(orderData.get('total_tip_received')));
        if (!fieldMap.containsKey('total_weight') && orderData.get('total_weight') != null)
            ord.Total_Weight__c = Integer.valueOf(String.valueOf(orderData.get('total_weight')));
        if (!fieldMap.containsKey('payment_gateway_names')) {
            List<Object> gateways = (List<Object>) orderData.get('payment_gateway_names');
            ord.Payment_Gateway__c = (gateways != null && !gateways.isEmpty()) ? (String) gateways[0] : null;
        }
        if (!fieldMap.containsKey('cancelled_at') && orderData.get('cancelled_at') != null) {
            ord.Cancelled_At__c = Datetime.valueOfGmt(((String) orderData.get('cancelled_at')).replace('T', ' ').replaceAll('[+-]\\d{2}:\\d{2}', ''));
        }
        if (!fieldMap.containsKey('processed_at') && orderData.get('processed_at') != null) {
            ord.Processed_At__c = Datetime.valueOfGmt(((String) orderData.get('processed_at')).replace('T', ' ').replaceAll('[+-]\\d{2}:\\d{2}', ''));
        }

        String locationId = orderData.get('location_id') != null ? String.valueOf(orderData.get('location_id')) : null;
        if (locationId != null) {
            List<Schema.Location> loc = [SELECT Id FROM Location WHERE Shopify_ID__c = :locationId LIMIT 1];
            if (!loc.isEmpty()) ord.Location__c = loc[0].Id;
        }

        ord.Shopify_ID__c = String.valueOf(orderData.get('id'));
        return ord;
    }

    private static Id getStdPricebookIdStatic() {
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
    }
}
