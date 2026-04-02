global class ShopifyCustomersBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {

    private String endpoint;
    private String accessToken;
    private String nextUrl;

    public ShopifyCustomersBatch(String endpoint) {
        this.endpoint = endpoint;
        Integration__mdt shopifyCred = getAccessToken();
        this.accessToken = shopifyCred.Access_Token__c;
    }

    public ShopifyCustomersBatch() {
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
            Integer daysAgo = Integer.valueOf(calloutControl.Days__c != null ? calloutControl.Days__c : 0);

            if (String.isBlank(this.endpoint)) {
                Integration__mdt shopifyCred = getAccessToken();
                finalEndpoint = shopifyCred.URL__c + '/customers.json?status=any';
                if (daysAgo != 0) {
                    String formattedDate = getPastDateTimeFormatted(daysAgo);
                    finalEndpoint += '&updated_at_min=' + formattedDate;
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
                        SELECT Id, PersonEmail, External_Id__c FROM Account
                        WHERE RecordTypeId = :personAccountRTId AND PersonEmail IN :emailSet
                    ]) {
                        existingByEmail.put(acc.PersonEmail.toLowerCase(), acc);
                    }
                }

                if (!externalIdSet.isEmpty()) {
                    for (Account acc : [
                        SELECT Id, External_Id__c FROM Account
                        WHERE RecordTypeId = :personAccountRTId AND External_Id__c IN :externalIdSet
                    ]) {
                        existingByExternalId.put(acc.External_Id__c, acc);
                    }
                }

                List<Account> toUpsert = new List<Account>();

                for (Object obj : customers) {
                    Map<String, Object> customer = (Map<String, Object>) obj;
                    Map<String, Object> defaultAddress = (Map<String, Object>) customer.get('default_address');
                    Map<String, Object> smsConsent = (Map<String, Object>) customer.get('sms_marketing_consent');
                    Map<String, Object> emailConsent = (Map<String, Object>) customer.get('email_marketing_consent');

                    String email = (String) customer.get('email');
                    String customerId = String.valueOf(customer.get('id'));
                    String firstName = (String) customer.get('first_name');
                    String lastName = (String) customer.get('last_name');
                    String phone = (String) customer.get('phone');
                    Boolean taxExempt = customer.containsKey('tax_exempt') ? (Boolean) customer.get('tax_exempt') : false;
                    String tags = (String) customer.get('tags');

                    // ➡️ New fields
                    Decimal totalSpent = customer.get('total_spent') != null ? Decimal.valueOf(String.valueOf(customer.get('total_spent'))) : null;
                    Integer ordersCount = customer.get('orders_count') != null ? Integer.valueOf(String.valueOf(customer.get('orders_count'))) : null;

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

                    acc.External_Id__c = customerId;
                    acc.FirstName = firstName;
                    acc.LastName = lastName;
                    acc.Phone = phone;
                    acc.Shopify_Tags__c = tags;
                    acc.Tax_Exempt__c = taxExempt;

                    acc.Total_Spent__c = totalSpent;
                    acc.Total_Orders__c = ordersCount;

                    if (smsConsent != null) {
                        acc.SMS_Consent_State__c = (String) smsConsent.get('state');
                        acc.SMS_Opt_In_Level__c = (String) smsConsent.get('opt_in_level');
                    }
                    if (emailConsent != null) {
                        acc.Email_Consent_State__c = (String) emailConsent.get('state');
                        acc.Email_Opt_In_Level__c = (String) emailConsent.get('opt_in_level');
                    }
                    if (defaultAddress != null) {
                        acc.BillingStreet = ((String) defaultAddress.get('address1')) + 
                                            (defaultAddress.get('address2') != null ? ' ' + (String) defaultAddress.get('address2') : '');
                        acc.BillingCity = (String) defaultAddress.get('city');
                        acc.BillingState = (String) defaultAddress.get('province');
                        acc.BillingPostalCode = (String) defaultAddress.get('zip');
                        acc.BillingCountry = (String) defaultAddress.get('country');
                    }

                    toUpsert.add(acc);
                }

                if (!toUpsert.isEmpty()) {
                    Database.upsert(toUpsert, false);
                }

                this.nextUrl = getNextPageUrl(res);

            } else {
                System.debug('HTTP callout failed: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            HandleCustomException.LogException(e, this.endpoint);
        }
    }

    global void finish(Database.BatchableContext BC) {
        if (String.isNotBlank(this.nextUrl)) {
            Database.executeBatch(new ShopifyCustomersBatch(this.nextUrl), 1);
        } else {
            System.debug('No nextUrl. All Shopify customers processed.');
        }
    }

    private Integration__mdt getAccessToken() {
        return [SELECT Access_Token__c, URL__c FROM Integration__mdt WHERE MasterLabel = 'Shopify' LIMIT 1];
    }

    private API_Callout_Control__mdt getCalloutControl() {
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
}