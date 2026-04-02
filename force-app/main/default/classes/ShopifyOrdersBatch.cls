global class ShopifyOrdersBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {

    private String endpoint;
    private String accessToken;
    private String nextUrl;

    public ShopifyOrdersBatch(String endpoint) {
        this.endpoint = endpoint;
        Integration__mdt shopifyCred = getAccessToken();
        this.accessToken = shopifyCred.Access_Token__c;
    }

    public ShopifyOrdersBatch() {
        Integration__mdt shopifyCred = getAccessToken();
        this.accessToken = shopifyCred.Access_Token__c;
    }

    global Iterable<Integer> start(Database.BatchableContext BC) {
        return new List<Integer>{1};
    }

    global void execute(Database.BatchableContext BC, List<Integer> scope) {
        try {
            API_Callout_Control__mdt calloutControl = getCalloutControl();
            if (!calloutControl.Allow_Callouts__c) {
                System.debug('Callouts not allowed.');
                return;
            }

            String finalEndpoint;
            Integer daysAgo = calloutControl.Days__c != null ? Integer.valueOf(calloutControl.Days__c) : 0;

            if (String.isBlank(this.endpoint)) {
                Integration__mdt shopifyCred = getAccessToken();
                finalEndpoint = shopifyCred.URL__c + '/orders.json?status=any';
                if (daysAgo > 0) {
                    finalEndpoint += '&updated_at_min=' + getPastDateTimeFormatted(daysAgo);
                }
            } else {
                finalEndpoint = this.endpoint;
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(finalEndpoint);
            req.setMethod('GET');
            req.setHeader('X-Shopify-Access-Token', this.accessToken);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() != 200) {
                System.debug('HTTP callout failed: ' + res.getStatusCode());
                return;
            }

            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> orders = (List<Object>) jsonResponse.get('orders');
            if (orders == null) orders = new List<Object>();

            Set<String> emailSet = new Set<String>();
            Set<String> shopifyIdSet = new Set<String>();
            Set<String> productSKUSet = new Set<String>();
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
                List<Object> productsList = (List<Object>) orderMap.get('line_items');
                if (productsList != null) {
                    for (Object productObj : productsList) {
                        Map<String, Object> product = (Map<String, Object>) productObj;
                        String sku = (String) product.get('sku');
                        if (!String.isBlank(sku)) productSKUSet.add(sku);
                    }
                }
            }

            Id personAccountRTId = getPersonAccountRecordTypeId();
            Map<String, Account> existingByEmail = new Map<String, Account>();
            Map<String, Account> existingByShopifyId = new Map<String, Account>();
            Map<String, Product2> existingProducts = new Map<String, Product2>();
            Map<String, String> locationIdMap = new Map<String, String>();
            
            if (!locationIdSet.isEmpty()) {
                for (Schema.Location loc : [SELECT Id, Name, Shopify_ID__c FROM Location WHERE Shopify_ID__c IN :locationIdSet]) {
                    if (loc.Shopify_ID__c != null) locationIdMap.put(loc.Shopify_ID__c, loc.Id);
                }
            }

            if (!emailSet.isEmpty()) {
                for (Account acc : [SELECT Id, PersonEmail, External_ID__c FROM Account WHERE RecordTypeId = :personAccountRTId AND PersonEmail IN :emailSet]) {
                    if (acc.PersonEmail != null) existingByEmail.put(acc.PersonEmail.toLowerCase(), acc);
                }
            }

            if (!shopifyIdSet.isEmpty()) {
                for (Account acc : [SELECT Id, PersonEmail, External_ID__c FROM Account WHERE RecordTypeId = :personAccountRTId AND External_ID__c IN :shopifyIdSet]) {
                    if (acc.External_ID__c != null) existingByShopifyId.put(acc.External_ID__c, acc);
                }
            }

            if (!productSKUSet.isEmpty()) {
                for (Product2 prd : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :productSKUSet]) {
                    if (prd.StockKeepingUnit != null) existingProducts.put(prd.StockKeepingUnit, prd);
                }
            }

            List<Account> accountsToUpsert = new List<Account>();
            List<Product2> productsToUpsert = new List<Product2>();
            Set<String> processedShopifyIds = new Set<String>();
            Set<String> processedSkus = new Set<String>();

            for (Object obj : orders) {
                Map<String, Object> orderMap = (Map<String, Object>) obj;
                Map<String, Object> customer = (Map<String, Object>) orderMap.get('customer');
                if (customer != null) {
                    String email = (String) customer.get('email');
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
                            acc.PersonEmail = email;
                        }
                        acc.External_ID__c = shopifyId;
                        acc.FirstName = (String) customer.get('first_name');
                        acc.LastName = String.isNotBlank((String) customer.get('last_name')) ? (String) customer.get('last_name') : acc.FirstName;
                        acc.Phone = (String) customer.get('phone');
                        accountsToUpsert.add(acc);
                        processedShopifyIds.add(shopifyId);
                    }
                }

                List<Object> productsList = (List<Object>) orderMap.get('line_items');
                if (productsList != null) {
                    for (Object productObj : productsList) {
                        Map<String, Object> product = (Map<String, Object>) productObj;
                        String sku = (String) product.get('sku');
                        if (!String.isBlank(sku) && !processedSkus.contains(sku)) {
                            Product2 prd = existingProducts.get(sku);
                            if (prd == null) {
                                prd = new Product2();
                                prd.StockKeepingUnit = sku;
                            }
                            prd.Name = (String) product.get('title');
                            prd.IsActive = true;
                            productsToUpsert.add(prd);
                            processedSkus.add(sku);
                        }
                    }
                }
            }

            if (!accountsToUpsert.isEmpty()) Database.upsert(accountsToUpsert, false);
            if (!productsToUpsert.isEmpty()) {
                Database.upsert(productsToUpsert, false);
                Id pricebookId = getStdPricebookId();
                Set<Id> productIds = new Set<Id>();
                for (Product2 p : productsToUpsert) if (p.Id != null) productIds.add(p.Id);

                Map<Id, Id> existingPBE = new Map<Id, Id>();
                for (PricebookEntry pbe : [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productIds]) {
                    existingPBE.put(pbe.Product2Id, pbe.Id);
                }

                List<PricebookEntry> entriesToInsert = new List<PricebookEntry>();
                for (Product2 prd : productsToUpsert) {
                    if (!existingPBE.containsKey(prd.Id)) {
                        entriesToInsert.add(new PricebookEntry(
                            Pricebook2Id = pricebookId,
                            Product2Id = prd.Id,
                            UnitPrice = 0,
                            IsActive = true
                        ));
                    }
                }
                if (!entriesToInsert.isEmpty()) insert entriesToInsert;
            }

            Map<String, Order> ordersByExternalId = new Map<String, Order>();
            List<Order> ordersToUpsert = new List<Order>();
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
                String email = (String) customer.get('email');
                Id accountId = email != null ? emailToAccountId.get(email.toLowerCase()) : null;
                if (accountId == null) continue;

                Order ord = new Order();
                ord.AccountId = accountId;
                ord.EffectiveDate = orderMap.get('created_at') != null ? Date.valueOf(((String) orderMap.get('created_at')).substring(0, 10)) : System.today();
                ord.Status = 'Draft';
                ord.Pricebook2Id = getStdPricebookId();
                ord.OrderReferenceNumber = (String) orderMap.get('name');
                ord.External_Id__c = String.valueOf(orderMap.get('id'));
                ord.Buyer_Accepts_Marketing__c = (Boolean) orderMap.get('buyer_accepts_marketing');
    			ord.Cancel_Reason__c = (String) orderMap.get('cancel_reason');
    			ord.Cart_Token__c = (String) orderMap.get('cart_token');
    			ord.Checkout_Id__c = orderMap.get('checkout_id') != null ? String.valueOf(orderMap.get('checkout_id')) : null;
    			ord.Confirmation_Number__c = (String) orderMap.get('confirmation_number');
    			ord.Contact_Email__c = (String) orderMap.get('contact_email');
    			ord.Estimated_Taxes__c = (Boolean) orderMap.get('estimated_taxes');
    			ord.Financial_Status__c = (String) orderMap.get('financial_status');
    			ord.Fulfillment_Status__c = (String) orderMap.get('fulfillment_status');
                String locationId = orderMap.get('location_id') != null ? String.valueOf(orderMap.get('location_id')) : null;
                if (locationIdMap.containsKey(locationId)) {
                    ord.Location__c = locationIdMap.get(locationId);
                }
    			// ord.Shopify_Location_Id__c = orderMap.get('location_id') != null ? String.valueOf(orderMap.get('location_id')) : null;
    			ord.Order_Status_Url__c = (String) orderMap.get('order_status_url');
    
    			List<Object> gateways = (List<Object>) orderMap.get('payment_gateway_names');
    			ord.Payment_Gateway__c = (gateways != null && !gateways.isEmpty()) ? (String) gateways[0] : null;
    
    			ord.PoNumber = (String) orderMap.get('po_number');
    			ord.Currency__c = (String) orderMap.get('presentment_currency');
    			ord.Reference__c = (String) orderMap.get('reference');
    			ord.Referring_Site__c = (String) orderMap.get('referring_site');
    			ord.Source_Name__c = (String) orderMap.get('source_name');
    			ord.Source_Url__c = (String) orderMap.get('source_url');
    			ord.Order_Number__c = orderMap.get('order_number') != null ? Integer.valueOf(String.valueOf(orderMap.get('order_number'))) : null;
    			ord.Order_Tags__c = (String) orderMap.get('tags');
    			ord.Order_Tax_Exempt__c = (Boolean) orderMap.get('tax_exempt');
    			ord.Taxes_Included__c = (Boolean) orderMap.get('taxes_included');
    			ord.Total_Discounts__c = orderMap.get('total_discounts') != null ? Decimal.valueOf(String.valueOf(orderMap.get('total_discounts'))) : null;
    			ord.Total_Tax__c = orderMap.get('total_tax') != null ? Decimal.valueOf(String.valueOf(orderMap.get('total_tax'))) : null;
    			ord.Total_Tip__c = orderMap.get('total_tip_received') != null ? Decimal.valueOf(String.valueOf(orderMap.get('total_tip_received'))) : null;
                ord.Total_Amount__c = orderMap.get('total_price') != null ? Decimal.valueOf(String.valueOf(orderMap.get('total_price'))) : null;
    			ord.Total_Weight__c = orderMap.get('total_weight') != null ? Integer.valueOf(String.valueOf(orderMap.get('total_weight'))) : null;
    
    			ord.Cancelled_At__c = orderMap.get('cancelled_at') != null 
        			? Datetime.valueOfGmt(((String) orderMap.get('cancelled_at')).replace('T', ' ').replace('-05:00', '')) 
        			: null;
    			ord.Processed_At__c = orderMap.get('processed_at') != null 
        			? Datetime.valueOfGmt(((String) orderMap.get('processed_at')).replace('T', ' ').replace('-05:00', '')) 
        			: null;

                ordersByExternalId.put(ord.External_Id__c, ord);
                ordersToUpsert.add(ord);
            }

            if (!ordersToUpsert.isEmpty()) upsert ordersToUpsert External_Id__c;

            // OrderItems
            Map<String, Order> externalIdToOrder = new Map<String, Order>();
            for (Order o : ordersToUpsert) {
                externalIdToOrder.put(o.External_Id__c, o);
            }

            Set<Id> allProductIds = new Set<Id>();
            for (Product2 p : existingProducts.values()) if (p.Id != null) allProductIds.add(p.Id);
            for (Product2 p : productsToUpsert) if (p.Id != null) allProductIds.add(p.Id);

            Map<Id, Id> productToPBE = new Map<Id, Id>();
            for (PricebookEntry pbe : [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :getStdPricebookId() AND Product2Id IN :allProductIds]) {
                productToPBE.put(pbe.Product2Id, pbe.Id);
            }

            List<OrderItem> orderItemsToUpsert = new List<OrderItem>();
            for (Object obj : orders) {
                Map<String, Object> orderMap = (Map<String, Object>) obj;
                String orderExternalId = String.valueOf(orderMap.get('id'));
                Order ord = externalIdToOrder.get(orderExternalId);
                if (ord == null) continue;

                List<Object> lineItems = (List<Object>) orderMap.get('line_items');
                if (lineItems != null) {
                    for (Object itemObj : lineItems) {
                        Map<String, Object> productMap = (Map<String, Object>) itemObj;
                        String sku = (String) productMap.get('sku');
                        if (String.isBlank(sku)) continue;

                        Product2 product = existingProducts.get(sku);
                        if (product == null) {
                            for (Product2 p : productsToUpsert) {
                                if (p.StockKeepingUnit == sku) {
                                    product = p;
                                    break;
                                }
                            }
                        }
                        if (product == null || product.Id == null) continue;

                        Id pbeId = productToPBE.get(product.Id);
                        if (pbeId == null) continue;

                        OrderItem orderItem = new OrderItem();
                        orderItem.OrderId = ord.Id;
                        orderItem.External_Id__c = String.valueOf(productMap.get('id'));
                        orderItem.PricebookEntryId = pbeId;
                        orderItem.Product2Id = product.Id;
                        orderItem.Quantity = Integer.valueOf(String.valueOf(productMap.get('quantity')));
                        orderItem.UnitPrice = Decimal.valueOf(String.valueOf(productMap.get('price')));
                        orderItemsToUpsert.add(orderItem);
                    }
                }
            }

            if (!orderItemsToUpsert.isEmpty()) upsert orderItemsToUpsert External_Id__c;

            this.nextUrl = getNextPageUrl(res);

        } catch (Exception e) {
            HandleCustomException.LogException(e, this.endpoint);
        }
    }

    global void finish(Database.BatchableContext BC) {
        if (String.isNotBlank(this.nextUrl)) {
            Database.executeBatch(new ShopifyOrdersBatch(this.nextUrl), 1);
        } else {
            System.debug('No nextUrl. All Shopify orders processed.');
        }
    }

    private Integration__mdt getAccessToken() {
        return [SELECT Access_Token__c, URL__c FROM Integration__mdt WHERE MasterLabel = 'Shopify' LIMIT 1];
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
}