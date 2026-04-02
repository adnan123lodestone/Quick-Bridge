global class KlaviyoEventsBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {
    
    private String endpoint;
    private String accessToken;
    private String nextUrl;

    public KlaviyoEventsBatch(String endpoint) {
        this.endpoint = endpoint;
        Integration__mdt klaviyoCredential = getAccessToken();
        this.accessToken = klaviyoCredential.Access_Token__c;
    }
    
    public KlaviyoEventsBatch() {
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
    			finalEndpoint = klaviyoCredential.URL__c + '/api/events';
                
                if (daysAgo != 0) {
    				String formattedDate = getPastDateTimeFormatted(daysAgo+1);
    
    				if (!finalEndpoint.contains('?')) {
        				finalEndpoint += '?';
    				} else if (!finalEndpoint.endsWith('&') && !finalEndpoint.endsWith('?')) {
        				finalEndpoint += '&';
    				}
    				finalEndpoint += 'filter=greater-than(datetime,' + formattedDate + ')';
				}
            }
            else {
  				finalEndpoint = this.endpoint;
			}
            
			Http http = new Http();
        	HttpRequest req = new HttpRequest();
        	req.setEndpoint(finalEndpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Klaviyo-API-Key ' + this.accessToken);
            req.setHeader('revision', '2025-01-15');

        	HttpResponse res = http.send(req);
        	if (res.getStatusCode() != 200) {
            	System.debug('HTTP callout failed. Status Code: ' + res.getStatusCode());
            	return;
        	}

        	Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        	List<Object> eventsList = (List<Object>) jsonResponse.get('data');
        	if (eventsList == null || eventsList.isEmpty()) return;

        	Set<String> profileIds = new Set<String>();
        	Map<String, Map<String, Object>> eventIdToEventMap = new Map<String, Map<String, Object>>();

        	for (Object evtObj : eventsList) {
            	Map<String, Object> evtMap = (Map<String, Object>) evtObj;
            	if (evtMap == null || !evtMap.containsKey('id')) continue;

            	String eventId = (String) evtMap.get('id');
            	Map<String, Object> relationships = (Map<String, Object>) evtMap.get('relationships');
            	if (relationships == null) continue;

            	Map<String, Object> profileRel = (Map<String, Object>) relationships.get('profile');
            	if (profileRel == null || !profileRel.containsKey('data')) continue;

            	Map<String, Object> profileData = (Map<String, Object>) profileRel.get('data');
            	String profileId = (profileData != null) ? (String) profileData.get('id') : null;

            	if (String.isNotBlank(profileId)) {
                	profileIds.add(profileId);
                	eventIdToEventMap.put(eventId, evtMap);
            	}
        	}

        	Map<String, Id> profileIdToAccountId = new Map<String, Id>();
        	for (Account acc : [SELECT Id, Klaviyo_ID__c FROM Account WHERE Klaviyo_ID__c IN :profileIds]) {
            	profileIdToAccountId.put(acc.Klaviyo_ID__c, acc.Id);
        	}

        	List<Event> eventsToUpsert = new List<Event>();
        	for (String eventId : eventIdToEventMap.keySet()) {
            	Map<String, Object> evtMap = eventIdToEventMap.get(eventId);
            	Map<String, Object> relationships = (Map<String, Object>) evtMap.get('relationships');
            	Map<String, Object> profileRel = (Map<String, Object>) relationships.get('profile');
            	Map<String, Object> profileData = (Map<String, Object>) profileRel.get('data');
            	String profileId = (String) profileData.get('id');

            	if (!profileIdToAccountId.containsKey(profileId)) continue;

            	Id accountId = profileIdToAccountId.get(profileId);

           		Event ev = new Event();
            	ev.WhatId = accountId;
            	ev.WhoId = null;
            	ev.ActivityDateTime = DateTime.now();
            	ev.DurationInMinutes = 1;
            	ev.Klaviyo_Event_Id__c = eventId;

            	Map<String, Object> attributes = (Map<String, Object>) evtMap.get('attributes');
            	Map<String, Object> props = (attributes != null) ? (Map<String, Object>) attributes.get('event_properties') : null;
            
            	String subject = 'Klaviyo Event';
				if (props != null) {
    				for (String key : new List<String>{'Subject', 'Name', 'Product Name', 'title', 'Campaign Name', 'CollectionName', 'List', 'step_name', 'form_type', 'review_content', 'method', 'Message Name'}) {
        				if (props.containsKey(key) && String.isNotBlank(String.valueOf(props.get(key)))) {
            				subject = String.valueOf(props.get(key));
            				break;
        				}
    				}
				}
				ev.Subject = subject;
            
            	ev.Description = (props != null) ? flattenAndFormat(props) : '';

            	eventsToUpsert.add(ev);
        	}

        	if (!eventsToUpsert.isEmpty()) {
            	try {
                	upsert eventsToUpsert Klaviyo_Event_Id__c;
            	} catch (Exception e) {
                	System.debug('Upsert failed: ' + e.getMessage());
            	}
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
        } catch (Exception e) {
            HandleCustomException.LogException(e, this.endpoint);
        }
    }

    global void finish(Database.BatchableContext BC) {
        if (String.isNotBlank(this.nextUrl)) {
            Database.executeBatch(new KlaviyoEventsBatch(this.nextUrl), 1);
        } else {
            System.debug('No nextUrl. All records processed.');
        }
    }

    public static String flattenAndFormat(Map<String, Object> props) {
    	List<String> lines = new List<String>();

    	for (String key : props.keySet()) {
        	Object val = props.get(key);
        	if (val == null) continue;

        	try {
            	if (key == '$extra' && val instanceof Map<String, Object>) {
                	lines.add('\n--- Extra Information ---');

                	Map<String, Object> extraMap = (Map<String, Object>) val;

                	for (String subKey : extraMap.keySet()) {
                    	Object subVal = extraMap.get(subKey);

                    	if (subKey == 'line_items' && subVal instanceof List<Object>) {
                        	List<Object> items = (List<Object>) subVal;
                        	Integer count = 1;
                        	for (Object obj : items) {
                            	if (!(obj instanceof Map<String, Object>)) continue;
                            	Map<String, Object> item = (Map<String, Object>) obj;

                            	lines.add('\n--- Line Item ' + count + ' ---');
                            	lines.add('Title: ' + clean(item.get('title')));
                            	lines.add('SKU: ' + clean(item.get('sku')));
                            	lines.add('Price: ' + clean(item.get('price')));
                            	lines.add('Vendor: ' + clean(item.get('vendor')));
                            	lines.add('Quantity: ' + clean(item.get('quantity')));
                            	lines.add('Variant Title: ' + clean(item.get('variant_title')));
                            	lines.add('Product ID: ' + clean(item.get('product_id')));
                            	lines.add('Presentment Title: ' + clean(item.get('presentment_title')));
                            	lines.add('Presentment Variant Title: ' + clean(item.get('presentment_variant_title')));

                            	if (item.containsKey('product')) {
                                	Map<String, Object> product = (Map<String, Object>) item.get('product');
                                	if (product != null && product.containsKey('body_html')) {
                                    	lines.add('\nProduct Description:\n' + stripHtml(String.valueOf(product.get('body_html'))));
                                	}
                            	}

                            	if (item.containsKey('properties')) {
                                	List<Object> propsList = (List<Object>) item.get('properties');
                                	for (Object prop : propsList) {
                                    	if (prop instanceof Map<String, Object>) {
                                        	Map<String, Object> propMap = (Map<String, Object>) prop;
                                        	lines.add('Property - ' + clean(propMap.get('name')) + ': ' + clean(propMap.get('value')));
                                    	}
                                	}
                            	}

                            	count++;
                        	}
                    	} else {
                        	lines.add('$extra - ' + subKey + ': ' + clean(subVal));
                    	}
                	}

                	lines.add(''); // space after $extra

            	} else if (val instanceof List<Object>) {
                	List<Object> listVal = (List<Object>) val;
                	List<String> entries = new List<String>();
                	for (Object entry : listVal) {
                    	entries.add(clean(entry));
                	}
                	lines.add(key + ': ' + String.join(entries, ', '));

            	} else if (val instanceof Map<String, Object>) {
               		Map<String, Object> nested = (Map<String, Object>) val;
                	for (String subKey : nested.keySet()) {
                    	lines.add(key + ' - ' + subKey + ': ' + clean(nested.get(subKey)));
                	}

            	} else {
                	lines.add(key + ': ' + clean(val));
            	}

        	} catch (Exception e) {
            	lines.add(key + ': [error processing]');
        	}
    	}

    	return String.join(lines, '\n');
	}


    private static String clean(Object val) {
        if (val == null) return '';
        String str = String.valueOf(val);
        str = stripHtml(str);
        return str.replaceAll('[\\{\\}\\[\\]]', '');
    }

    private static String stripHtml(String input) {
        return input == null ? '' : input.replaceAll('<[^>]*>', '');
    }
    
    private static String getPastDateTimeFormatted(Integer daysAgo) {
        Datetime currentDateTime = Datetime.now();
        Datetime pastDateTime = currentDateTime.addDays(-daysAgo);
        String formattedDateTime = pastDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'+00:00\'');
        return formattedDateTime;
    }
    
    private Integration__mdt getAccessToken() {
        return [SELECT Access_Token__c, URL__c FROM Integration__mdt WHERE MasterLabel = 'Klaviyo' LIMIT 1];
    }

    private API_Callout_Control__mdt getCalloutControl() {
        return [SELECT Allow_Callouts__c, Days__c
                FROM API_Callout_Control__mdt 
                WHERE MasterLabel = 'Klaviyo - Event' AND Endpoint__c = 'event' 
                LIMIT 1];
    }
}