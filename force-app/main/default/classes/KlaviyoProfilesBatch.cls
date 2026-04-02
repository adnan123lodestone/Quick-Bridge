global class KlaviyoProfilesBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {

    private String endpoint;
    private String accessToken;
    private String nextUrl;

    public KlaviyoProfilesBatch(String endpoint) {
        this.endpoint = endpoint;
        Integration__mdt klaviyoCredential = getAccessToken();
        this.accessToken = klaviyoCredential.Access_Token__c;
    }
    
    public KlaviyoProfilesBatch() {
        Integration__mdt klaviyoCredential = getAccessToken();
        this.accessToken = klaviyoCredential.Access_Token__c;
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
                Integration__mdt klaviyoCredential = getAccessToken();
    			finalEndpoint = klaviyoCredential.URL__c + '/api/profiles';
                
                if (daysAgo != 0) {
    				String formattedDate = getPastDateTimeFormatted(daysAgo+1);
    
    				if (!finalEndpoint.contains('?')) {
        				finalEndpoint += '?';
    				} else if (!finalEndpoint.endsWith('&') && !finalEndpoint.endsWith('?')) {
        				finalEndpoint += '&';
    				}
    				finalEndpoint += 'filter=greater-than(updated,' + formattedDate + ')';
				}
            }
            else {
  				finalEndpoint = this.endpoint;
			}
			
            HttpRequest req = new HttpRequest();
            req.setEndpoint(finalEndpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Klaviyo-API-Key ' + this.accessToken);
            req.setHeader('revision', '2025-01-15');

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> dataList = (List<Object>) jsonResponse.get('data');

                Set<String> emailSet = new Set<String>();
                Set<String> klaviyoIdSet = new Set<String>();

                for (Object obj : dataList) {
                    Map<String, Object> profile = (Map<String, Object>) obj;
                    Map<String, Object> attributes = (Map<String, Object>) profile.get('attributes');

                    String email = (String) attributes.get('email');
                    String klaviyoId = (String) profile.get('id');

                    if (String.isNotBlank(email)) emailSet.add(email.toLowerCase());
                    if (String.isNotBlank(klaviyoId)) klaviyoIdSet.add(klaviyoId);
                }

                Id personAccountRTId = getPersonAccountRecordTypeId();
                Map<String, Account> existingByEmail = new Map<String, Account>();
                Map<String, Account> existingByKlaviyoId = new Map<String, Account>();

                if (!emailSet.isEmpty()) {
                    for (Account acc : [
                        SELECT Id, PersonEmail, Klaviyo_ID__c FROM Account
                        WHERE RecordTypeId = :personAccountRTId AND PersonEmail IN :emailSet
                    ]) {
                        existingByEmail.put(acc.PersonEmail.toLowerCase(), acc);
                    }
                }

                if (!klaviyoIdSet.isEmpty()) {
                    for (Account acc : [
                        SELECT Id, Klaviyo_ID__c FROM Account
                        WHERE RecordTypeId = :personAccountRTId AND Klaviyo_ID__c IN :klaviyoIdSet
                    ]) {
                        existingByKlaviyoId.put(acc.Klaviyo_ID__c, acc);
                    }
                }

                List<Account> toUpsert = new List<Account>();

                for (Object obj : dataList) {
                    Map<String, Object> profile = (Map<String, Object>) obj;
                    Map<String, Object> attr = (Map<String, Object>) profile.get('attributes');
                    Map<String, Object> props = (Map<String, Object>) attr.get('properties');
                    Map<String, Object> location = (Map<String, Object>) attr.get('location');

                    String email = (String) attr.get('email');
                    String klaviyoId = (String) profile.get('id');
                    String firstName = (String) attr.get('first_name');
                    String lastName = (String) attr.get('last_name');
                    String org = (String) attr.get('organization');
                    String phone = (String) attr.get('phone_number');

                    if (String.isBlank(lastName)) lastName = firstName;
                    if (String.isBlank(lastName)) lastName = org;
                    if (String.isBlank(lastName)) lastName = klaviyoId;

                    String addr1 = location != null ? (String) location.get('address1') : null;
                    String addr2 = location != null ? (String) location.get('address2') : null;
                    String city = location != null ? (String) location.get('city') : null;
                    String state = location != null ? (String) location.get('region') : null;
                    String country = location != null ? (String) location.get('country') : null;
                    String zip = location != null ? (String) location.get('zip') : null;

                    String street = (addr1 != null ? addr1 : '') + (addr2 != null ? ' ' + addr2 : '');

                    Boolean acceptsMarketing = props != null && props.containsKey('Accepts Marketing') ?
                        Boolean.valueOf(String.valueOf(props.get('Accepts Marketing'))) : false;

                    Account acc;
                    if (existingByKlaviyoId.containsKey(klaviyoId)) {
                        acc = existingByKlaviyoId.get(klaviyoId);
                    } else if (existingByEmail.containsKey(email?.toLowerCase())) {
                        acc = existingByEmail.get(email.toLowerCase());
                    } else {
                        acc = new Account();
                        acc.RecordTypeId = personAccountRTId;
                        acc.PersonEmail = email;
                    }

                    acc.Klaviyo_ID__c = klaviyoId;
                    acc.FirstName = firstName;
                    acc.LastName = lastName;
                    acc.Phone = phone;
                    acc.BillingStreet = street.trim();
                    acc.BillingCity = city;
                    acc.BillingState = state;
                    acc.BillingPostalCode = zip;
                    acc.BillingCountry = country;
                    acc.Accepts_Marketing__c = acceptsMarketing;

                    if (props != null) {
                        // acc.Shopify_Tags__c = String.valueOf(props.get('Shopify Tags'));
                        acc.Omnisend_Segment__c = (String) props.get('Omnisend Segment');
                        // acc.Total_Spent__c = props.get('Total Spent') != null ? Decimal.valueOf(String.valueOf(props.get('Total Spent'))) : null;
                        // acc.Total_Orders__c = props.get('Total Orders') != null ? Integer.valueOf(String.valueOf(props.get('Total Orders'))) : null;
                        acc.Smile_Points_Balance__c = props.get('Smile Points Balance') != null ? Decimal.valueOf(String.valueOf(props.get('Smile Points Balance'))) : null;
                        acc.Smile_Referral_URL__c = (String) props.get('Smile Referral URL');
                        acc.Smile_State__c = (String) props.get('Smile State');
                        acc.Smile_VIP_Tier_ID__c = props.get('Smile VIP Tier ID') != null ? Integer.valueOf(String.valueOf(props.get('Smile VIP Tier ID'))) : null;
                        acc.Smile_VIP_Tier_Name__c = (String) props.get('Smile VIP Tier Name');
                    }

                    toUpsert.add(acc);
                }

                if (!toUpsert.isEmpty()) {
                    Database.upsert(toUpsert, false);
                }

                Map<String, Object> links = (Map<String, Object>) jsonResponse.get('links');
                if (links != null && links.containsKey('next')) {
                    Object nextObj = links.get('next');
                    if (nextObj instanceof String) {
                        this.nextUrl = (String) nextObj;
                    } else if (nextObj instanceof List<Object>) {
                        List<Object> nextList = (List<Object>) nextObj;
                        if (!nextList.isEmpty() && nextList[0] instanceof String) {
                            this.nextUrl = (String) nextList[0];
                        }
                    }
                }
            } else {
                System.debug('HTTP callout failed: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            HandleCustomException.LogException(e, this.endpoint);
        }
    }

    global void finish(Database.BatchableContext BC) {
        if (String.isNotBlank(this.nextUrl)) {
            Database.executeBatch(new KlaviyoProfilesBatch(this.nextUrl), 1);
        } else {
            System.debug('No nextUrl. All records processed.');
        }
    }

    private Integration__mdt getAccessToken() {
        return [SELECT Access_Token__c, URL__c FROM Integration__mdt WHERE MasterLabel = 'Klaviyo' LIMIT 1];
    }

    private API_Callout_Control__mdt getCalloutControl() {
        return [SELECT Allow_Callouts__c, Days__c
                FROM API_Callout_Control__mdt 
                WHERE MasterLabel = 'Klaviyo - Profile' AND Endpoint__c = 'profile' 
                LIMIT 1];
    }

    private Id getPersonAccountRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND Name = 'Person Account' LIMIT 1].Id;
    }
    
    private static String getPastDateTimeFormatted(Integer daysAgo) {
        Datetime currentDateTime = Datetime.now();
        Datetime pastDateTime = currentDateTime.addDays(-daysAgo);
        String formattedDateTime = pastDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'+00:00\'');
        return formattedDateTime;
    }
}