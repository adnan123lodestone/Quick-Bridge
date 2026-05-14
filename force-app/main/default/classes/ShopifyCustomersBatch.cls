global class ShopifyCustomersBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {
    
    private String endpoint;
    private String nextUrl;
    
    @TestVisible private static Boolean bypassAuthCheckForTest = false; 
    
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

        IntegrationUsageService.assertCanConsumeTask('Shopify', 1);

        try {
            API_Callout_Control__mdt calloutControl = getCalloutControl();
            if (!calloutControl.Allow_Callouts__c) {
                System.debug('Callouts not allowed.');
                return;
            }
            
            String finalEndpoint;
            Integer daysAgo = Integer.valueOf(calloutControl.Days__c != null ? calloutControl.Days__c : 0);
            
            if (String.isBlank(this.endpoint)) {
                finalEndpoint = 'callout:QuickBridgeTLG__Shopify_API/customers.json?status=any';
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
                
                if (!emailSet.isEmpty()) {
                    for (Account acc : [
                        SELECT Id, PersonEmail, Shopify_ID__c FROM Account
                        WHERE RecordTypeId = :personAccountRTId AND PersonEmail IN :emailSet
                    ]) {
                        existingByEmail.put(acc.PersonEmail.toLowerCase(), acc);
                    }
                }

                if (!externalIdSet.isEmpty()) {
                    for (Account acc : [
                        SELECT Id, Shopify_ID__c FROM Account
                        WHERE RecordTypeId = :personAccountRTId AND Shopify_ID__c IN :externalIdSet
                    ]) {
                        existingByExternalId.put(acc.Shopify_ID__c, acc);
                    }
                }
                
                Map<String, String> fieldMap = ShopifyObjectMappings.getCustomerToAccountMapping();
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
        if (String.isNotBlank(this.nextUrl)) {
            Database.executeBatch(new ShopifyCustomersBatch(this.nextUrl), 1);
        } else {
            System.debug('No nextUrl. All Shopify customers processed.');
        }
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
}