public class KlaviyoCampaignMembersBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    private Id campaignId;
    private String endpoint;
    private String nextUrl;
    private Boolean sharedExecution = false;
    private ConnectorExecutionResult sharedResult;

    public KlaviyoCampaignMembersBatch(Id campaignId) {
        this.campaignId = campaignId;
        
        Campaign camp = [
            SELECT Id, Profile_s_URL__c
            FROM Campaign
            WHERE Id = :campaignId
            LIMIT 1
        ];
        this.endpoint = camp.Profile_s_URL__c;
    }

    public KlaviyoCampaignMembersBatch(Id campaignId, String nextUrl) {
        this.campaignId = campaignId;
        this.nextUrl = nextUrl;
    }

    public Iterable<SObject> start(Database.BatchableContext BC) {
        return new List<SObject>{ new Campaign(Id = campaignId) };
    }

    public void execute(Database.BatchableContext BC, List<SObject> scope) {
        if (sharedExecution == true) {
            sharedResult = ConnectorExecutionResult.success();
        }
        try {
            Http http = new Http();
            String workingEndpoint = (String.isNotBlank(this.nextUrl)) ? this.nextUrl : this.endpoint;
            
            if (String.isBlank(workingEndpoint)) {
                System.debug('No endpoint to process.');
                recordFailure('Klaviyo campaign member endpoint is missing.', false, null);
                return;
            }
            
            HttpRequest req = KlaviyoAuthService.buildGetRequest(workingEndpoint);

            HttpResponse httpRes = http.send(req);
            if (httpRes.getStatusCode() == 200) {
                Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());
                List<Object> dataList = (List<Object>) jsonResponse.get('data');
                if (dataList == null && sharedExecution == true) {
                    recordFailure('Klaviyo campaign member response is missing the data collection.', false, null);
                    return;
                }

                Set<String> profileIds = new Set<String>();

                if (dataList != null) {
                    for (Object o : dataList) {
                        Map<String, Object> profile = (Map<String, Object>) o;
                        String profileId = (String) profile.get('id');
                        if (String.isNotBlank(profileId)) {
                            profileIds.add(profileId);
                        }
                    }
                }

                if (!profileIds.isEmpty()) {
                    createCampaignMembers(profileIds);
                }

                Map<String, Object> links = (Map<String, Object>) jsonResponse.get('links');
                if (links != null && links.containsKey('next')) {
                    String nextLink = (String) links.get('next');
                    this.nextUrl = String.isNotBlank(nextLink) ? nextLink : null;
                } else {
                    this.nextUrl = null;
                }

            } else {
                System.debug('HTTP callout failed with status code: ' + httpRes.getStatusCode());
                recordFailure(
                    'Klaviyo campaign member request failed with status ' + httpRes.getStatusCode() + '.',
                    ConnectorInboundOperationExecutor.isRetryableStatus(httpRes.getStatusCode()),
                    ConnectorInboundOperationExecutor.retryAfterSeconds(httpRes)
                );
                this.nextUrl = null;
            }
        } catch (Exception ex) {
            HandleCustomException.LogException(ex, 'KlaviyoCampaignMembersBatch');
            recordFailure(ex.getMessage(), false, null);
        }
    }

    /** Executes one campaign membership page for ConnectorInboundBatch. */
    public ConnectorExecutionResult executeSharedPage() {
        sharedExecution = true;
        execute(null, new List<SObject>{ new Campaign(Id = campaignId) });
        if (sharedResult == null) {
            sharedResult = ConnectorExecutionResult.failed(
                'Klaviyo campaign member synchronization returned no result.',
                false,
                null
            );
        }
        sharedResult.nextCursor = nextUrl;
        return sharedResult;
    }

    public void finish(Database.BatchableContext BC) {
        if (String.isNotBlank(this.nextUrl)) {
            // ➡️ Continue fetching next page immediately with a fresh batch
            Database.executeBatch(new KlaviyoCampaignMembersBatch(this.campaignId, this.nextUrl), 1);
        } else {
            System.debug('All pages processed successfully.');
        }
    }

    private void createCampaignMembers(Set<String> profileIds) {
        try {
            List<Account> accList = [
                SELECT Id, Klaviyo_ID__c, PersonContactId 
                FROM Account
                WHERE Klaviyo_ID__c IN :profileIds
            ];

            List<CampaignMember> membersToInsert = new List<CampaignMember>();
            for (Account acc : accList) {
                if (acc.PersonContactId != null) {
                    CampaignMember cm = new CampaignMember();
                    cm.CampaignId = campaignId;
                    cm.ContactId = acc.PersonContactId;
                    membersToInsert.add(cm);
                }
            }

            if (!membersToInsert.isEmpty()) {
                Set<Id> contactIds = new Set<Id>();
                for (CampaignMember cm : membersToInsert) {
                    contactIds.add(cm.ContactId);
                }

                List<CampaignMember> existingMembers = [
                    SELECT ContactId
                    FROM CampaignMember
                    WHERE CampaignId = :campaignId AND ContactId IN :contactIds
                ];

                Set<Id> existingContactIds = new Set<Id>();
                for (CampaignMember cm : existingMembers) {
                    existingContactIds.add(cm.ContactId);
                }

                List<CampaignMember> newMembersToInsert = new List<CampaignMember>();
                for (CampaignMember cm : membersToInsert) {
                    if (!existingContactIds.contains(cm.ContactId)) {
                        newMembersToInsert.add(cm);
                    }
                }

                if (!newMembersToInsert.isEmpty()) {
                    insert newMembersToInsert;
                    if (sharedExecution == true) {
                        sharedResult.processedCount += newMembersToInsert.size();
                        sharedResult.successfulCount += newMembersToInsert.size();
                    }
                    System.debug('Inserted ' + newMembersToInsert.size() + ' new CampaignMembers.');
                } else {
                    System.debug('All contacts were already campaign members.');
                }
            } else {
                System.debug('No matching Accounts with PersonContactId.');
            }
        } catch (Exception ex) {
            HandleCustomException.LogException(ex, 'KlaviyoCampaignMembersBatch_createCampaignMembers');
            recordFailure(ex.getMessage(), false, null);
        }
    }

    private void recordFailure(String message, Boolean retryable, Integer retryDelaySeconds) {
        if (sharedExecution == true) {
            sharedResult.mergeFrom(
                ConnectorExecutionResult.failed(message, retryable, retryDelaySeconds)
            );
        }
    }

}
