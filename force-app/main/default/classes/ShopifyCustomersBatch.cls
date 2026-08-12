global class ShopifyCustomersBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {
    
    private String endpoint;
    private String nextUrl;
    private Integer sharedProcessedCount = 0;
    private Integer sharedFailureCount = 0;
    private String sharedErrorSummary;
    private Boolean sharedRetryable = false;
    private Integer sharedRetryDelaySeconds;
    
    @TestVisible private static Boolean bypassAuthCheckForTest = false;
    @TestVisible private static Boolean suppressFinishEnqueue = false;
    
    public ShopifyCustomersBatch(String endpoint) {
        this.endpoint = endpoint;
    }
    
    public ShopifyCustomersBatch() {
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
            Integer daysAgo = Integer.valueOf(calloutControl.Days__c != null ? calloutControl.Days__c : 0);
            
            if (String.isBlank(this.endpoint)) {
                finalEndpoint = 'callout:QuickBridgeTLG__Shopify_API/admin/api/2024-04/customers.json?status=any';
                if (daysAgo != 0) {
                    String formattedDate = getPastDateTimeFormatted(daysAgo);
                    finalEndpoint += '&updated_at_min=' + formattedDate;
                }
            } else {
                // Handle pagination: Replace domain with callout prefix to maintain authentication
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
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> customers = (List<Object>) jsonResponse.get('customers');
                
                if (customers == null) customers = new List<Object>();
                sharedProcessedCount = customers.size();
                
                Set<String> emailSet = new Set<String>();
                Set<String> externalIdSet = new Set<String>();
                
                for (Object obj : customers) {
                    Map<String, Object> customer = (Map<String, Object>) obj;
                    String email = (String) customer.get('email');
                    String idStr = String.valueOf(customer.get('id'));
                    
                    if (String.isNotBlank(email)) emailSet.add(email.toLowerCase());
                    if (String.isNotBlank(idStr)) externalIdSet.add(idStr);
                }
                
                Id personAccountRTId = getPersonAccountRecordTypeId();
                Map<String, Account> existingByEmail = new Map<String, Account>();
                Map<String, Account> existingByExternalId = new Map<String, Account>();

                Map<String, String> fieldMap = ShopifyObjectMappings.getCustomerToAccountMapping();
                Set<String> sfFields = new Set<String>{'Id', 'PersonEmail', 'Shopify_ID__c', 'RecordTypeId'};
                sfFields.addAll(fieldMap.values());
                String accountFieldList = String.join(new List<String>(sfFields), ', ');

                if (!emailSet.isEmpty()) {
                    for (Account acc : Database.query(
                        'SELECT ' + accountFieldList + ' FROM Account WHERE RecordTypeId = :personAccountRTId AND PersonEmail IN :emailSet'
                    )) {
                        existingByEmail.put(((String) acc.get('PersonEmail')).toLowerCase(), acc);
                    }
                }

                if (!externalIdSet.isEmpty()) {
                    for (Account acc : Database.query(
                        'SELECT ' + accountFieldList + ' FROM Account WHERE RecordTypeId = :personAccountRTId AND Shopify_ID__c IN :externalIdSet'
                    )) {
                        existingByExternalId.put((String) acc.get('Shopify_ID__c'), acc);
                    }
                }
                List<Account> toUpsert = new List<Account>();
                
                for (Object obj : customers) {
                    Map<String, Object> customerMap = (Map<String, Object>) obj;
                    Map<String, Object> defaultAddress = (Map<String, Object>) customerMap.get('default_address');
                    Map<String, Object> smsConsent    = (Map<String, Object>) customerMap.get('sms_marketing_consent');
                    Map<String, Object> emailConsent  = (Map<String, Object>) customerMap.get('email_marketing_consent');
                    
                    String email      = (String) customerMap.get('email');
                    String customerId = String.valueOf(customerMap.get('id'));
                    String firstName  = (String) customerMap.get('first_name');
                    String lastName   = (String) customerMap.get('last_name');
                    if (String.isBlank(lastName)) lastName = firstName;
                    if (String.isBlank(lastName)) lastName = customerId;
                    
                    Account acc;
                    if (existingByExternalId.containsKey(customerId)) {
                        acc = existingByExternalId.get(customerId);
                    } else if (existingByEmail.containsKey(email?.toLowerCase())) {
                        acc = existingByEmail.get(email.toLowerCase());
                    } else {
                        acc = new Account();
                        acc.RecordTypeId = personAccountRTId;
                        acc.PersonEmail = email;
                    }
                    
                    // Apply dynamic field mappings from Field_Mapping__mdt (fallback to static map)
                    for (String shopifyPath : fieldMap.keySet()) {
                        String sfField = fieldMap.get(shopifyPath);
                        Object val = getNestedValue(customerMap, shopifyPath);
                        if (val == null) continue;
                        try {
                            if (sfField == 'Tax_Exempt__c') {
                                acc.put(sfField, (Boolean) val);
                            } else if (sfField == 'Total_Spent__c') {
                                acc.put(sfField, Decimal.valueOf(String.valueOf(val)));
                            } else if (sfField == 'Total_Orders__c') {
                                acc.put(sfField, Integer.valueOf(String.valueOf(val)));
                            } else {
                                acc.put(sfField, val);
                            }
                        } catch (Exception ex) {
                            System.debug('Field mapping error ' + sfField + ': ' + ex.getMessage());
                        }
                    }
                    
                    // Always ensure identity fields are set
                    acc.Shopify_ID__c = customerId;
                    if (String.isBlank(acc.LastName)) acc.LastName = lastName;
                    
                    // Nested objects not covered by flat mapping keys
                    if (smsConsent != null) {
                        if (!fieldMap.containsKey('sms_marketing_consent.state'))
                            acc.SMS_Consent_State__c = (String) smsConsent.get('state');
                        if (!fieldMap.containsKey('sms_marketing_consent.opt_in_level'))
                            acc.SMS_Opt_In_Level__c = (String) smsConsent.get('opt_in_level');
                    }
                    if (emailConsent != null) {
                        if (!fieldMap.containsKey('email_marketing_consent.state'))
                            acc.Email_Consent_State__c = (String) emailConsent.get('state');
                        if (!fieldMap.containsKey('email_marketing_consent.opt_in_level'))
                            acc.Email_Opt_In_Level__c = (String) emailConsent.get('opt_in_level');
                    }
                    if (defaultAddress != null && !fieldMap.containsKey('default_address.address1')) {
                        String street = (String) defaultAddress.get('address1');
                        if (defaultAddress.get('address2') != null) street += ' ' + (String) defaultAddress.get('address2');
                        acc.BillingStreet      = street;
                        acc.BillingCity        = (String) defaultAddress.get('city');
                        acc.BillingState       = (String) defaultAddress.get('province');
                        acc.BillingPostalCode  = (String) defaultAddress.get('zip');
                        acc.BillingCountry     = (String) defaultAddress.get('country');
                    }
                    
                    toUpsert.add(acc);
                }
                
                if (!toUpsert.isEmpty()) {
                    Database.UpsertResult[] upsertResults = Database.upsert(toUpsert, false);
                    for (Database.UpsertResult upsertResult : upsertResults) {
                        if (!upsertResult.isSuccess()) {
                            sharedFailureCount++;
                            if (String.isBlank(sharedErrorSummary)) {
                                sharedErrorSummary = 'A Shopify customer record could not be saved.';
                            }
                        }
                    }
                    ErrorLogUtility.logUpsertResults(
                        'Shopify',
                    'ShopifyCustomersBatch.execute.upsertCustomers',
                    'upsert',
                    toUpsert,
                    upsertResults,
                    null,
                    null
                        );
                }
                
                this.nextUrl = getNextPageUrl(res);
                
            } else {
                sharedFailureCount = 1;
                sharedErrorSummary = 'Shopify customers API returned HTTP ' + res.getStatusCode() + '.';
                sharedRetryable = ConnectorInboundOperationExecutor.isRetryableStatus(
                    res.getStatusCode()
                );
                sharedRetryDelaySeconds = sharedRetryable
                    ? ConnectorInboundOperationExecutor.retryAfterSeconds(res)
                    : null;
                System.debug('HTTP callout failed: ' + res.getStatusCode());
                ErrorLogUtility.logCalloutFailure(
                    'Shopify',
                'ShopifyCustomersBatch.execute',
                'Shopify customers API returned HTTP ' + res.getStatusCode() + ': ' + res.getBody(),
                res.getStatusCode(),
                null,
                null
                    );
            }
        } catch (Exception e) {
            sharedFailureCount = 1;
            sharedErrorSummary = e.getMessage();
            System.debug('Error: ' + e.getMessage());
            ErrorLogUtility.logException(
                'Shopify',
            'ShopifyCustomersBatch.execute',
            e,
            null,
            null
                );
        }
    }
    
    global void finish(Database.BatchableContext BC) {
        if (String.isNotBlank(this.nextUrl) && !suppressFinishEnqueue) {
            Database.executeBatch(new ShopifyCustomersBatch(this.nextUrl), 1);
        } else {
            System.debug('No nextUrl. All Shopify customers processed.');
        }
    }

    public static ConnectorExecutionResult executeSharedPage(ConnectorExecutionRequest request) {
        if (!bypassAuthCheckForTest && !PaymentGatewayService.isClientAuthorized('Shopify')) {
            return ConnectorExecutionResult.failed(
                'Shopify license is not active.',
                false,
                null
            );
        }
        ShopifyCustomersBatch batchValue = new ShopifyCustomersBatch(
            request == null ? null : request.cursor
        );
        batchValue.execute(null, new List<Integer>{ 1 });
        ConnectorExecutionResult result = ConnectorExecutionResult.success();
        result.processedCount = batchValue.sharedProcessedCount;
        result.failedCount = batchValue.sharedFailureCount;
        result.successfulCount = Math.max(0, result.processedCount - result.failedCount);
        result.errorSummary = batchValue.sharedErrorSummary;
        result.retryable = batchValue.sharedRetryable;
        result.retryDelaySeconds = batchValue.sharedRetryDelaySeconds;
        result.nextCursor = batchValue.nextUrl;
        return result;
    }
    
    private API_Callout_Control__mdt getCalloutControl() {
        if (Test.isRunningTest()) {
            return new API_Callout_Control__mdt(
                Allow_Callouts__c = true,
            Days__c = 0
                );
        }
        return [SELECT Allow_Callouts__c, Days__c FROM API_Callout_Control__mdt 
                WHERE MasterLabel = 'Shopify - Customer' AND Endpoint__c = 'customer' 
                LIMIT 1];
    }
    
    private Id getPersonAccountRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'PersonAccount' LIMIT 1].Id;
    }
    
    private static String getPastDateTimeFormatted(Integer daysAgo) {
        Datetime pastDateTime = Datetime.now().addDays(-daysAgo);
        return pastDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ssZ');
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
    
    // Resolves dot-notation paths like 'default_address.city' from a nested map
    private static Object getNestedValue(Map<String, Object> root, String path) {
        if (!path.contains('.')) return root.get(path);
        List<String> parts = path.split('\\.');
        Object current = root.get(parts[0]);
        for (Integer i = 1; i < parts.size(); i++) {
            if (!(current instanceof Map<String, Object>)) return null;
            current = ((Map<String, Object>) current).get(parts[i]);
        }
        return current;
    }
    
    public static void syncCustomerFromShopify(String customerId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:QuickBridgeTLG__Shopify_API/admin/api/2024-04/customers/' + customerId + '.json');
        req.setMethod('GET');
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> customer = (Map<String, Object>) data.get('customer');
            Account acc = buildAccountFromShopifyCustomer(customer);
            upsert acc Account.Shopify_ID__c;
        } else {
            throw new CalloutException('Shopify customer not found: ' + res.getBody());
        }
    }

    private static Account buildAccountFromShopifyCustomer(Map<String, Object> customer) {
        Id personAccountRTId = getPersonAccountRecordTypeIdStatic();
        String email = (String) customer.get('email');
        String customerId = String.valueOf(customer.get('id'));
        String firstName = (String) customer.get('first_name');
        String lastName = (String) customer.get('last_name');
        if (String.isBlank(lastName)) lastName = firstName;
        if (String.isBlank(lastName)) lastName = customerId;

        List<Account> existing = [SELECT Id, Shopify_ID__c, PersonEmail, RecordTypeId FROM Account
                                  WHERE Shopify_ID__c = :customerId OR PersonEmail = :email LIMIT 1];
        Account acc = existing.isEmpty() ? new Account() : existing[0];
        if (existing.isEmpty()) acc.RecordTypeId = personAccountRTId;

        Map<String, String> fieldMap = ShopifyObjectMappings.getCustomerToAccountMapping();
        for (String shopifyPath : fieldMap.keySet()) {
            String sfField = fieldMap.get(shopifyPath);
            Object val = getNestedValue(customer, shopifyPath);
            if (val == null) continue;
            try {
                if (sfField == 'Tax_Exempt__c') {
                    acc.put(sfField, (Boolean) val);
                } else if (sfField == 'Total_Spent__c') {
                    acc.put(sfField, Decimal.valueOf(String.valueOf(val)));
                } else if (sfField == 'Total_Orders__c') {
                    acc.put(sfField, Integer.valueOf(String.valueOf(val)));
                } else {
                    acc.put(sfField, val);
                }
            } catch (Exception ex) { /* ignore */ }
        }

        acc.Shopify_ID__c = customerId;
        if (String.isNotBlank(email)) acc.PersonEmail = email;
        if (String.isNotBlank(lastName)) acc.LastName = lastName;
        if (String.isNotBlank(firstName)) acc.FirstName = firstName;

        Map<String, Object> defaultAddress = (Map<String, Object>) customer.get('default_address');
        Map<String, Object> smsConsent = (Map<String, Object>) customer.get('sms_marketing_consent');
        Map<String, Object> emailConsent = (Map<String, Object>) customer.get('email_marketing_consent');
        if (smsConsent != null) {
            if (!fieldMap.containsKey('sms_marketing_consent.state'))
                acc.SMS_Consent_State__c = (String) smsConsent.get('state');
            if (!fieldMap.containsKey('sms_marketing_consent.opt_in_level'))
                acc.SMS_Opt_In_Level__c = (String) smsConsent.get('opt_in_level');
        }
        if (emailConsent != null) {
            if (!fieldMap.containsKey('email_marketing_consent.state'))
                acc.Email_Consent_State__c = (String) emailConsent.get('state');
            if (!fieldMap.containsKey('email_marketing_consent.opt_in_level'))
                acc.Email_Opt_In_Level__c = (String) emailConsent.get('opt_in_level');
        }
        if (defaultAddress != null && !fieldMap.containsKey('default_address.address1')) {
            String street = (String) defaultAddress.get('address1');
            if (defaultAddress.get('address2') != null) street += ' ' + (String) defaultAddress.get('address2');
            acc.BillingStreet = street;
            acc.BillingCity = (String) defaultAddress.get('city');
            acc.BillingState = (String) defaultAddress.get('province');
            acc.BillingPostalCode = (String) defaultAddress.get('zip');
            acc.BillingCountry = (String) defaultAddress.get('country');
        }
        return acc;
    }

    private static Id getPersonAccountRecordTypeIdStatic() {
        return [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'PersonAccount' LIMIT 1].Id;
    }

    @TestVisible
    private static Account testBuildAccountFromShopifyCustomer(Map<String, Object> customer) {
        return buildAccountFromShopifyCustomer(customer);
    }
}
