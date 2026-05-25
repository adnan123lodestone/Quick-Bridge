public class KlaviyoListsBatch implements Database.Batchable<Integer>, Database.AllowsCallouts {
    
    private String endpoint;
    private String nextUrl;

    public KlaviyoListsBatch(String endpoint) {
        this.endpoint = endpoint;
    }
    
    public KlaviyoListsBatch() {
    }

    public Iterable<Integer> start(Database.BatchableContext BC) {
        return new List<Integer>{1};
    }

    public void execute(Database.BatchableContext BC, List<Integer> scope) {
        
        try {
            API_Callout_Control__mdt calloutControl = getCalloutControl();
            if (!calloutControl.Allow_Callouts__c) {
                System.debug('Callouts not allowed.');
                return;
            }
            
            String finalEndpoint;
            
            Integer daysAgo = Integer.valueOf(calloutControl.Days__c != null ? calloutControl.Days__c : 0);

            if (String.isBlank(this.endpoint)) {
    			finalEndpoint = '/api/lists';
                
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
            
            List<Campaign> campaignsToUpsert = new List<Campaign>();
            
            Http http = new Http();
        	HttpRequest req = KlaviyoAuthService.buildGetRequest(finalEndpoint);
            
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                // Deserialize the JSON response.
                Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> dataList = (List<Object>) jsonResponse.get('data');
                
                // Process the current page records.
                if (dataList != null) {
                    for (Object obj : dataList) {
                        Map<String, Object> listRecord = (Map<String, Object>) obj;
                        String klaviyoId = (String) listRecord.get('id'); // Klaviyo list Id

                        Map<String, Object> attributes = (Map<String, Object>) listRecord.get('attributes');
                        String listName = (String) attributes.get('name');
                        
                        // Extract the profiles self URL from the relationships.
                        Map<String, Object> relationships = (Map<String, Object>) listRecord.get('relationships');
                        String profilesSelfUrl = null;
                        if (relationships != null && relationships.containsKey('profiles')) {
                            Map<String, Object> profiles = (Map<String, Object>) relationships.get('profiles');
                            if (profiles != null && profiles.containsKey('links')) {
                                Map<String, Object> profilesLinks = (Map<String, Object>) profiles.get('links');
                                profilesSelfUrl = (String) profilesLinks.get('self');
                            }
                        }
                        
                        Campaign camp = new Campaign();
                        camp.Name = listName;
                        camp.Klaviyo_ID__c = klaviyoId;
                        camp.Profile_s_URL__c = profilesSelfUrl;
                        camp.Type = 'List';
                        
                        campaignsToUpsert.add(camp);
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
            } else {
                System.debug('HTTP callout failed. Status Code: ' + res.getStatusCode());
                endpoint = null;
            }
        
        	// Upsert all accumulated Campaign records using the external field.
        	if (!campaignsToUpsert.isEmpty()) {
            	Database.UpsertResult[] results = Database.upsert(campaignsToUpsert, Campaign.Klaviyo_ID__c, false);
            	Integer successCount = 0;
            	Integer failureCount = 0;
            	for (Integer i = 0; i < results.size(); i++) {
                	if (results[i].isSuccess()) {
                    	successCount++;
                	} else {
                    	failureCount++;
                    	for (Database.Error err : results[i].getErrors()) {
                        	System.debug('Error for record with Klaviyo_ID__c ' + campaignsToUpsert[i].Klaviyo_ID__c + ' : ' + err.getMessage());
                    	}
                	}
            	}
            	System.debug('Successful upserts: ' + successCount);
            	System.debug('Failed upserts: ' + failureCount);
        	}
        } catch (Exception e) {
            HandleCustomException.LogException(e, this.endpoint);
        }
    }

    public void finish(Database.BatchableContext BC) {
        if (String.isNotBlank(this.nextUrl)) {
            Database.executeBatch(new KlaviyoListsBatch(this.nextUrl), 1);
        } else {
            System.debug('No nextUrl. All records processed.');
        }
    }
    
    private API_Callout_Control__mdt getCalloutControl() {
        if (Test.isRunningTest()) {
            return new API_Callout_Control__mdt(Allow_Callouts__c = true, Days__c = 0);
        }
        return [SELECT Allow_Callouts__c, Days__c
                FROM API_Callout_Control__mdt 
                WHERE MasterLabel = 'Klaviyo - List' AND Endpoint__c = 'list' 
                LIMIT 1];
    }
    
    private static String getPastDateTimeFormatted(Integer daysAgo) {
        Datetime currentDateTime = Datetime.now();
        Datetime pastDateTime = currentDateTime.addDays(-daysAgo);
        String formattedDateTime = pastDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'+00:00\'');
        return formattedDateTime;
    }
}