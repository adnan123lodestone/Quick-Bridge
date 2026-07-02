@IsTest
private class MetaRemainingIntegrationTest {
    private static final String CONNECTOR_KEY = 'meta';
    private static final String NAMED_CREDENTIAL = 'Meta_Graph_API';

    @testSetup
    static void setupMetaConfigAndRecords() {
        Connector_Instance__c instanceRecord = new Connector_Instance__c(
            Name = 'Meta',
            Connector_Key__c = CONNECTOR_KEY,
            Connector_Label__c = 'Meta',
            Active__c = true,
            Entitlement_Status__c = 'Active',
            Health_Status__c = 'Unknown',
            Named_Credential__c = NAMED_CREDENTIAL
        );
        insert instanceRecord;

        insert new List<Connector_Config_Value__c>{
            configValue(instanceRecord.Id, 'accessTokenRef', 'Meta_Access_Token_QA', true),
            configValue(instanceRecord.Id, 'appSecretRef', 'meta-test-secret', true),
            configValue(instanceRecord.Id, 'webhookVerifyTokenRef', 'meta-verify-token', true),
            configValue(instanceRecord.Id, 'adAccountId', 'act_123', false),
            configValue(instanceRecord.Id, 'pageId', 'page-123', false),
            configValue(instanceRecord.Id, 'instagramBusinessAccountId', 'ig-123', false),
            configValue(instanceRecord.Id, 'campaignSyncEnabled', 'true', false),
            configValue(instanceRecord.Id, 'insightsSyncEnabled', 'true', false),
            configValue(instanceRecord.Id, 'leadAdsEnabled', 'true', false),
            configValue(instanceRecord.Id, 'commentAttributionEnabled', 'true', false),
            configValue(instanceRecord.Id, 'defaultLeadSource', 'Meta Lead Ad', false),
            configValue(instanceRecord.Id, 'defaultCampaignMemberStatus', 'Responded', false),
            configValue(instanceRecord.Id, 'autoCreateCampaignMember', 'true', false),
            configValue(instanceRecord.Id, 'leadCreationMode', 'Keyword Match', false),
            configValue(instanceRecord.Id, 'keywordRulesJson', '["pricing"]', false),
            configValue(instanceRecord.Id, 'attributionWindowDays', '30', false)
        };

        Campaign insightsCampaign = new Campaign(
            Name = 'Existing Insights Campaign',
            IsActive = true,
            Meta_Campaign_Id__c = 'camp-insights',
            Platform__c = 'Meta'
        );
        insert insightsCampaign;

        Meta_Ad_Set__c insightsAdSet = new Meta_Ad_Set__c(
            Name = 'Existing Insights Ad Set',
            Meta_Ad_Set_Id__c = 'adset-insights',
            Meta_Campaign_Id__c = 'camp-insights',
            Campaign__c = insightsCampaign.Id
        );
        insert insightsAdSet;

        insert new Meta_Ad__c(
            Name = 'Existing Insights Ad',
            Meta_Ad_Id__c = 'ad-insights',
            Meta_Ad_Set_Id__c = 'adset-insights',
            Meta_Campaign_Id__c = 'camp-insights',
            Meta_Ad_Set__c = insightsAdSet.Id,
            Campaign__c = insightsCampaign.Id
        );

        insert new Campaign(
            Name = 'Lead Detail Campaign',
            IsActive = true,
            Meta_Campaign_Id__c = 'camp-lead',
            Platform__c = 'Meta'
        );
    }

    @IsTest
    static void apiClientPaginatesAndClassifiesErrors() {
        Test.setMock(HttpCalloutMock.class, new MetaMock()
            .withResponse('/campaigns', '{"data":[{"id":"camp-a","name":"Campaign A"}],"paging":{"next":"https://graph.facebook.com/v21.0/act_123/campaigns?after=page2"}}')
            .withResponse('after=page2', '{"data":[{"id":"camp-b","name":"Campaign B"}]}')
        );

        Test.startTest();
        List<Map<String, Object>> rows = MetaApiClient.configured().getAll('/act_123/campaigns', new Map<String, String>{ 'fields' => 'id,name' });
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'The client should collect records across paging.next URLs.');
        System.assertEquals('camp-a', (String) rows[0].get('id'));
        System.assertEquals('camp-b', (String) rows[1].get('id'));

        Test.setMock(HttpCalloutMock.class, new MetaMock()
            .withStatus('/campaigns', 500, '{"error":{"message":"Server unavailable","code":2}}')
        );
        try {
            MetaApiClient.configured().getAll('/act_123/campaigns', new Map<String, String>{ 'fields' => 'id,name' });
            System.assert(false, 'Expected a MetaApiClientException for non-2xx responses.');
        } catch (MetaApiClient.MetaApiClientException expected) {
            System.assert(expected.getMessage().contains('Server unavailable'), expected.getMessage());
        }
    }

    @IsTest
    static void campaignSyncUpsertsCampaignAdSetAndAd() {
        Test.setMock(HttpCalloutMock.class, campaignSyncMock());

        Test.startTest();
        MetaCampaignSyncService.syncCampaignHierarchy();
        Test.stopTest();

        Campaign campaignRecord = [
            SELECT Name, Meta_Campaign_Id__c, Meta_Ad_Account_Id__c, Meta_Objective__c,
                Meta_Status__c, Daily_Budget__c, Lifetime_Budget__c, Platform__c, Campaign_Source__c
            FROM Campaign
            WHERE Meta_Campaign_Id__c = 'camp-sync'
            LIMIT 1
        ];
        System.assertEquals('Synced Campaign', campaignRecord.Name);
        System.assertEquals('act_123', campaignRecord.Meta_Ad_Account_Id__c);
        System.assertEquals('LEAD_GENERATION', campaignRecord.Meta_Objective__c);
        System.assertEquals(50, campaignRecord.Daily_Budget__c);
        System.assertEquals('Meta', campaignRecord.Platform__c);
        System.assertEquals('Meta Ads', campaignRecord.Campaign_Source__c);

        Meta_Ad_Set__c adSetRecord = [
            SELECT Campaign__c, Meta_Campaign_Id__c, Status__c, Optimization_Goal__c, Daily_Budget__c
            FROM Meta_Ad_Set__c
            WHERE Meta_Ad_Set_Id__c = 'adset-sync'
            LIMIT 1
        ];
        System.assertEquals(campaignRecord.Id, adSetRecord.Campaign__c);
        System.assertEquals('camp-sync', adSetRecord.Meta_Campaign_Id__c);
        System.assertEquals('LEAD_GENERATION', adSetRecord.Optimization_Goal__c);
        System.assertEquals(25, adSetRecord.Daily_Budget__c);

        Meta_Ad__c adRecord = [
            SELECT Campaign__c, Meta_Ad_Set__c, Meta_Campaign_Id__c, Meta_Ad_Set_Id__c, Status__c, Creative_Id__c
            FROM Meta_Ad__c
            WHERE Meta_Ad_Id__c = 'ad-sync'
            LIMIT 1
        ];
        System.assertEquals(campaignRecord.Id, adRecord.Campaign__c);
        System.assertEquals(adSetRecord.Id, adRecord.Meta_Ad_Set__c);
        System.assertEquals('creative-sync', adRecord.Creative_Id__c);
    }

    @IsTest
    static void insightsSyncUpdatesExistingRecordsOnly() {
        Test.setMock(HttpCalloutMock.class, insightsSyncMock());

        Test.startTest();
        MetaInsightsSyncService.syncInsights();
        Test.stopTest();

        Campaign campaignRecord = [
            SELECT Spend_To_Date__c, Impressions__c, Clicks__c, Reach__c, Leads_From_Meta__c, Cost_Per_Lead__c, Last_Meta_Sync_At__c
            FROM Campaign
            WHERE Meta_Campaign_Id__c = 'camp-insights'
            LIMIT 1
        ];
        System.assertEquals(123.45, campaignRecord.Spend_To_Date__c);
        System.assertEquals(1000, campaignRecord.Impressions__c);
        System.assertEquals(50, campaignRecord.Clicks__c);
        System.assertEquals(900, campaignRecord.Reach__c);
        System.assertEquals(5, campaignRecord.Leads_From_Meta__c);
        System.assertEquals(24.69, campaignRecord.Cost_Per_Lead__c);
        System.assertNotEquals(null, campaignRecord.Last_Meta_Sync_At__c);

        Meta_Ad_Set__c adSetRecord = [
            SELECT Spend__c, Impressions__c, Clicks__c, Leads__c, Cost_Per_Lead__c, Last_Meta_Sync_At__c
            FROM Meta_Ad_Set__c
            WHERE Meta_Ad_Set_Id__c = 'adset-insights'
            LIMIT 1
        ];
        System.assertEquals(44.44, adSetRecord.Spend__c);
        System.assertEquals(4, adSetRecord.Leads__c);

        Meta_Ad__c adRecord = [
            SELECT Spend__c, Impressions__c, Clicks__c, Leads__c, Cost_Per_Lead__c, Last_Meta_Sync_At__c
            FROM Meta_Ad__c
            WHERE Meta_Ad_Id__c = 'ad-insights'
            LIMIT 1
        ];
        System.assertEquals(22.22, adRecord.Spend__c);
        System.assertEquals(2, adRecord.Leads__c);
        System.assertEquals(0, [SELECT COUNT() FROM Campaign WHERE Meta_Campaign_Id__c = 'missing-campaign']);
    }

    @IsTest
    static void leadAdsServiceFetchesLeadDetailAndKeepsIdempotency() {
        Test.setMock(HttpCalloutMock.class, leadDetailMock());

        MetaPayloadNormalizer.NormalizedEvent eventRecord = new MetaPayloadNormalizer.NormalizedEvent();
        eventRecord.platform = 'Meta';
        eventRecord.interactionType = 'Meta Lead Ad';
        eventRecord.leadgenId = 'leadgen-detail';
        eventRecord.campaignId = 'camp-lead';

        Test.startTest();
        MetaLeadAdsService.processLeadgenEvent(eventRecord);
        MetaLeadAdsService.processLeadgenEvent(eventRecord);
        Test.stopTest();

        Lead leadRecord = [
            SELECT Email, Phone, FirstName, LastName, Meta_Leadgen_Id__c, Meta_Campaign_Id__c, Primary_Campaign__c
            FROM Lead
            WHERE Meta_Leadgen_Id__c = 'leadgen-detail'
            LIMIT 1
        ];
        System.assertEquals('buyer@example.com', leadRecord.Email);
        System.assertEquals('5551112222', leadRecord.Phone);
        System.assertEquals('Ada', leadRecord.FirstName);
        System.assertEquals('Buyer', leadRecord.LastName);
        System.assertEquals(1, [SELECT COUNT() FROM Social_Interaction__c WHERE Meta_Leadgen_Id__c = 'leadgen-detail']);
        System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE LeadId = :leadRecord.Id]);
    }

    @IsTest
    static void reconciliationRepairsUnattributedInteractions() {
        Campaign campaignRecord = new Campaign(
            Name = 'Late Synced Campaign',
            IsActive = true,
            Meta_Campaign_Id__c = 'camp-late',
            Platform__c = 'Meta'
        );
        insert campaignRecord;

        Lead leadRecord = new Lead(
            LastName = 'Late',
            Company = 'Meta Lead',
            Meta_Campaign_Id__c = 'camp-late',
            Meta_Leadgen_Id__c = 'leadgen-late',
            Attribution_Status__c = 'Needs Review'
        );
        insert leadRecord;

        insert new Social_Interaction__c(
            Name = 'leadgen-late',
            External_Key__c = 'Meta|leadgen|leadgen-late',
            Platform__c = 'Meta',
            Interaction_Type__c = 'Meta Lead Ad',
            Meta_Campaign_Id__c = 'camp-late',
            Meta_Leadgen_Id__c = 'leadgen-late',
            Lead__c = leadRecord.Id,
            Processing_Status__c = 'Processed',
            Attribution_Status__c = 'Needs Review'
        );

        Test.startTest();
        MetaReconciliationService.reconcile();
        MetaReconciliationService.reconcile();
        Test.stopTest();

        Social_Interaction__c interactionRecord = [
            SELECT Campaign__c, Attribution_Status__c
            FROM Social_Interaction__c
            WHERE Meta_Leadgen_Id__c = 'leadgen-late'
            LIMIT 1
        ];
        System.assertEquals(campaignRecord.Id, interactionRecord.Campaign__c);
        System.assertEquals('Attributed', interactionRecord.Attribution_Status__c);

        Lead updatedLead = [
            SELECT Primary_Campaign__c, Attribution_Status__c
            FROM Lead
            WHERE Id = :leadRecord.Id
        ];
        System.assertEquals(campaignRecord.Id, updatedLead.Primary_Campaign__c);
        System.assertEquals('Attributed', updatedLead.Attribution_Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campaignRecord.Id AND LeadId = :leadRecord.Id]);
    }

    private static Connector_Config_Value__c configValue(Id instanceId, String fieldKey, String value, Boolean secretReference) {
        return new Connector_Config_Value__c(
            Name = CONNECTOR_KEY + ':' + fieldKey,
            Connector_Instance__c = instanceId,
            Connector_Key__c = CONNECTOR_KEY,
            Field_Key__c = fieldKey,
            Value__c = value,
            Is_Secret_Reference__c = secretReference
        );
    }

    private static MetaMock campaignSyncMock() {
        return new MetaMock()
            .withResponse('/campaigns', '{"data":[{"id":"camp-sync","name":"Synced Campaign","account_id":"act_123","objective":"LEAD_GENERATION","status":"ACTIVE","daily_budget":"5000","lifetime_budget":"10000"}]}')
            .withResponse('/adsets', '{"data":[{"id":"adset-sync","name":"Synced Ad Set","campaign_id":"camp-sync","status":"ACTIVE","optimization_goal":"LEAD_GENERATION","daily_budget":"2500","lifetime_budget":"5000"}]}')
            .withResponse('/ads', '{"data":[{"id":"ad-sync","name":"Synced Ad","campaign_id":"camp-sync","adset_id":"adset-sync","status":"ACTIVE","creative":{"id":"creative-sync"},"preview_shareable_link":"https://example.test/ad"}]}');
    }

    private static MetaMock insightsSyncMock() {
        return new MetaMock()
            .withResponse('level=campaign', '{"data":[{"campaign_id":"camp-insights","spend":"123.45","impressions":"1000","clicks":"50","reach":"900","actions":[{"action_type":"lead","value":"5"}]}]}')
            .withResponse('level=adset', '{"data":[{"adset_id":"adset-insights","spend":"44.44","impressions":"400","clicks":"20","actions":[{"action_type":"lead","value":"4"}]}]}')
            .withResponse('level=ad', '{"data":[{"ad_id":"ad-insights","spend":"22.22","impressions":"200","clicks":"10","actions":[{"action_type":"lead","value":"2"}]},{"ad_id":"missing-ad","spend":"99.99","impressions":"1","clicks":"1"}]}');
    }

    private static MetaMock leadDetailMock() {
        return new MetaMock()
            .withResponse('/leadgen-detail', '{"id":"leadgen-detail","campaign_id":"camp-lead","ad_id":"ad-lead","adset_id":"adset-lead","form_id":"form-lead","field_data":[{"name":"email","values":["buyer@example.com"]},{"name":"phone_number","values":["5551112222"]},{"name":"full_name","values":["Ada Buyer"]}]}');
    }

    private class MetaMock implements HttpCalloutMock {
        private Map<String, MockResponse> responsesByPattern = new Map<String, MockResponse>();

        MetaMock withResponse(String pattern, String body) {
            responsesByPattern.put(pattern, new MockResponse(200, body));
            return this;
        }

        MetaMock withStatus(String pattern, Integer statusCode, String body) {
            responsesByPattern.put(pattern, new MockResponse(statusCode, body));
            return this;
        }

        public HttpResponse respond(HttpRequest request) {
            String endpoint = request.getEndpoint();
            String bestPattern;
            for (String pattern : responsesByPattern.keySet()) {
                if (endpoint.contains(pattern)) {
                    if (bestPattern == null || pattern.length() > bestPattern.length()) {
                        bestPattern = pattern;
                    }
                }
            }
            if (bestPattern != null) {
                return toHttpResponse(responsesByPattern.get(bestPattern));
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(404);
            response.setBody('{"error":{"message":"No mock for ' + endpoint + '"}}');
            return response;
        }

        private HttpResponse toHttpResponse(MockResponse mockResponse) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(mockResponse.statusCode);
            response.setBody(mockResponse.body);
            return response;
        }
    }

    private class MockResponse {
        Integer statusCode;
        String body;

        MockResponse(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
    }
}