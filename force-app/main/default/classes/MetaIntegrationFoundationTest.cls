@IsTest
private class MetaIntegrationFoundationTest {
    private static final String CONNECTOR_KEY = 'meta';
    private static final String TEST_SECRET = 'meta-test-secret';

    @IsTest
    static void webhookVerifierAcceptsChallengeAndValidSignature() {
        seedMetaConfig();
        String body = '{"object":"page","entry":[]}';
        String signature = 'sha256=' + EncodingUtil.convertToHex(
            Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(TEST_SECRET))
        ).toLowerCase();

        System.assertEquals('challenge-123', MetaWebhookVerifier.verifyChallenge('subscribe', 'verify-token', 'challenge-123'));
        System.assertEquals(true, MetaWebhookVerifier.isValidSignature(body, signature, TEST_SECRET));
        System.assertEquals(false, MetaWebhookVerifier.isValidSignature(body, 'sha256=bad', TEST_SECRET));
    }

    @IsTest
    static void payloadNormalizerExtractsLeadgenAndCommentEvents() {
        String leadPayload = '{"object":"page","entry":[{"id":"page-1","changes":[{"field":"leadgen","value":{"leadgen_id":"leadgen-1","ad_id":"ad-1","adgroup_id":"adset-1","campaign_id":"camp-1","form_id":"form-1","page_id":"page-1"}}]}]}';
        MetaPayloadNormalizer.NormalizedEvent leadEvent = MetaPayloadNormalizer.firstEvent(leadPayload);

        System.assertEquals('Meta Lead Ad', leadEvent.interactionType);
        System.assertEquals('leadgen-1', leadEvent.leadgenId);
        System.assertEquals('ad-1', leadEvent.adId);
        System.assertEquals('adset-1', leadEvent.adSetId);
        System.assertEquals('camp-1', leadEvent.campaignId);

        String commentPayload = '{"object":"instagram","entry":[{"id":"ig-1","changes":[{"field":"comments","value":{"id":"comment-1","media_id":"media-1","from":{"id":"profile-1","username":"buyer"},"text":"Need pricing"}}]}]}';
        MetaPayloadNormalizer.NormalizedEvent commentEvent = MetaPayloadNormalizer.firstEvent(commentPayload);

        System.assertEquals('Instagram', commentEvent.platform);
        System.assertEquals('Comment', commentEvent.interactionType);
        System.assertEquals('comment-1', commentEvent.commentId);
        System.assertEquals('media-1', commentEvent.instagramMediaId);
        System.assertEquals('Need pricing', commentEvent.commentText);
    }

    @IsTest
    static void attributionResolvesByAdIdAndCampaignMemberIsIdempotent() {
        Campaign campaignRecord = new Campaign(
            Name = 'Meta Campaign',
            IsActive = true,
            Meta_Campaign_Id__c = 'camp-1',
            Platform__c = 'Meta',
            Campaign_Source__c = 'Meta Ads'
        );
        insert campaignRecord;

        Meta_Ad_Set__c adSetRecord = new Meta_Ad_Set__c(
            Name = 'Meta Ad Set',
            Meta_Ad_Set_Id__c = 'adset-1',
            Meta_Campaign_Id__c = 'camp-1',
            Campaign__c = campaignRecord.Id
        );
        insert adSetRecord;

        Meta_Ad__c adRecord = new Meta_Ad__c(
            Name = 'Meta Ad',
            Meta_Ad_Id__c = 'ad-1',
            Meta_Ad_Set__c = adSetRecord.Id,
            Campaign__c = campaignRecord.Id,
            Meta_Campaign_Id__c = 'camp-1',
            Meta_Ad_Set_Id__c = 'adset-1',
            Post_Id__c = 'post-1'
        );
        insert adRecord;

        Lead leadRecord = new Lead(LastName = 'Buyer', Company = 'Meta Lead', Email = 'buyer@example.com');
        insert leadRecord;

        MetaPayloadNormalizer.NormalizedEvent eventRecord = new MetaPayloadNormalizer.NormalizedEvent();
        eventRecord.platform = 'Facebook';
        eventRecord.interactionType = 'Meta Lead Ad';
        eventRecord.adId = 'ad-1';
        eventRecord.adSetId = 'adset-1';
        eventRecord.campaignId = 'camp-1';
        eventRecord.leadgenId = 'leadgen-1';

        MetaAttributionService.AttributionResult result = MetaAttributionService.resolve(eventRecord);

        System.assertEquals(campaignRecord.Id, result.campaignId);
        System.assertEquals(adSetRecord.Id, result.adSetId);
        System.assertEquals(adRecord.Id, result.adId);
        System.assertEquals('Attributed', result.status);

        Social_Interaction__c interactionRecord = MetaSocialInteractionService.upsertInteraction(eventRecord, result, leadRecord.Id);
        CampaignMember firstMember = MetaCampaignMemberService.ensureCampaignMember(result, leadRecord.Id, interactionRecord.Id, 'Responded');
        CampaignMember secondMember = MetaCampaignMemberService.ensureCampaignMember(result, leadRecord.Id, interactionRecord.Id, 'Responded');

        System.assertEquals(firstMember.Id, secondMember.Id, 'Repeated processing should reuse the existing CampaignMember.');
        System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campaignRecord.Id AND LeadId = :leadRecord.Id]);
    }

    @IsTest
    static void integrationWorkerProcessesLeadAdWorkItemIdempotently() {
        seedMetaConfig();
        Campaign campaignRecord = new Campaign(
            Name = 'Lead Ads Campaign',
            IsActive = true,
            Meta_Campaign_Id__c = 'camp-2',
            Platform__c = 'Meta',
            Campaign_Source__c = 'Meta Ads'
        );
        insert campaignRecord;

        MetaPayloadNormalizer.NormalizedEvent eventRecord = new MetaPayloadNormalizer.NormalizedEvent();
        eventRecord.platform = 'Facebook';
        eventRecord.interactionType = 'Meta Lead Ad';
        eventRecord.campaignId = 'camp-2';
        eventRecord.leadgenId = 'leadgen-2';
        eventRecord.email = 'lead@example.com';
        eventRecord.phone = '5551230000';
        eventRecord.commenterName = 'Lead Buyer';
        eventRecord.rawPayload = JSON.serialize(new Map<String, Object>{ 'leadgen_id' => 'leadgen-2' });

        IntegrationWorkRequest request = new IntegrationWorkRequest();
        request.integration = 'Meta';
        request.operation = 'LeadAd';
        request.sourceObject = 'MetaLeadgen';
        request.sourceRecordId = 'leadgen-2';
        request.lockKey = 'MetaLeadgen:leadgen-2';
        request.payloadJson = JSON.serialize(eventRecord);
        Id itemId = IntegrationWorkService.enqueue(request);

        Integration_Work_Item__c item = [
            SELECT Id, Integration__c, Operation__c, Payload__c, Source_Record_Id__c
            FROM Integration_Work_Item__c
            WHERE Id = :itemId
        ];

        Test.startTest();
        new MetaIntegrationWorker().handle(item);
        new MetaIntegrationWorker().handle(item);
        Test.stopTest();

        Lead leadRecord = [
            SELECT Id, Email, Meta_Leadgen_Id__c, Primary_Campaign__c
            FROM Lead
            WHERE Meta_Leadgen_Id__c = 'leadgen-2'
            LIMIT 1
        ];
        System.assertEquals('lead@example.com', leadRecord.Email);
        System.assertEquals(campaignRecord.Id, leadRecord.Primary_Campaign__c);
        System.assertEquals(1, [SELECT COUNT() FROM Social_Interaction__c WHERE Meta_Leadgen_Id__c = 'leadgen-2']);
        System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campaignRecord.Id AND LeadId = :leadRecord.Id]);
    }

    @IsTest
    static void configServiceHandlesDefaultsAndValidation() {
        System.assertEquals(false, MetaConfigService.isActive());
        System.assertEquals(false, MetaConfigService.isEnabled(null));
        System.assertEquals('Meta Lead Ad', MetaConfigService.defaultLeadSource());
        System.assertEquals('Responded', MetaConfigService.defaultCampaignMemberStatus());
        System.assertEquals(30, MetaConfigService.attributionWindowDays());
        try {
            MetaConfigService.requireConfiguredForWebhook();
            System.assert(false, 'Expected missing webhook configuration to fail.');
        } catch (MetaConfigService.MetaConfigException expected) {
            System.assert(expected.getMessage().contains('verify token'));
        }
        try {
            MetaConfigService.requireConfiguredForApiSync();
            System.assert(false, 'Expected inactive Meta API configuration to fail.');
        } catch (MetaConfigService.MetaConfigException expected) {
            System.assert(expected.getMessage().contains('inactive'));
        }

        seedMetaConfig(new Map<String, String>{
            'campaignSyncEnabled' => 'yes',
            'attributionWindowDays' => '14',
            'pageId' => 'page-123',
            'instagramBusinessAccountId' => 'ig-123',
            'graphApiVersion' => 'v21.0'
        });

        System.assertEquals(true, MetaConfigService.isActive());
        System.assertEquals(true, MetaConfigService.isEnabled('campaignSyncEnabled'));
        System.assertEquals(14, MetaConfigService.attributionWindowDays());
        System.assertEquals('Meta_Graph_API', MetaConfigService.namedCredential());
        System.assertEquals('v21.0', MetaConfigService.graphApiVersion());
        System.assertEquals('act_123', MetaConfigService.adAccountId());
        System.assertEquals('page-123', MetaConfigService.pageId());
        System.assertEquals('ig-123', MetaConfigService.instagramBusinessAccountId());
        MetaConfigService.requireConfiguredForWebhook();
        MetaConfigService.requireConfiguredForApiSync();
    }

    @IsTest
    static void commentProcessorSupportsManualReviewAndKeywordLeadCreation() {
        seedMetaConfig(new Map<String, String>{
            'leadCreationMode' => 'Manual Review',
            'keywordRulesJson' => '["pricing"]'
        });
        Campaign campaignRecord = new Campaign(
            Name = 'Comment Campaign',
            IsActive = true,
            Meta_Campaign_Id__c = 'comment-camp',
            Platform__c = 'Meta',
            Campaign_Source__c = 'Meta Ads'
        );
        insert campaignRecord;
        Meta_Ad__c adRecord = new Meta_Ad__c(
            Name = 'Comment Ad',
            Meta_Ad_Id__c = 'comment-ad',
            Campaign__c = campaignRecord.Id,
            Meta_Campaign_Id__c = 'comment-camp',
            Instagram_Media_Id__c = 'media-comment'
        );
        insert adRecord;

        MetaPayloadNormalizer.NormalizedEvent manualEvent = commentEvent('comment-manual', 'media-comment', 'What is this?');
        MetaCommentAttributionProcessor.process(manualEvent);

        Social_Interaction__c manualInteraction = [
            SELECT Lead__c, Campaign__c, Attribution_Status__c
            FROM Social_Interaction__c
            WHERE Meta_Comment_Id__c = 'comment-manual'
            LIMIT 1
        ];
        System.assertEquals(null, manualInteraction.Lead__c);
        System.assertEquals(campaignRecord.Id, manualInteraction.Campaign__c);

        Connector_Config_Value__c modeValue = [
            SELECT Id, Value__c
            FROM Connector_Config_Value__c
            WHERE Field_Key__c = 'leadCreationMode'
            LIMIT 1
        ];
        modeValue.Value__c = 'Keyword Match';
        update modeValue;

        MetaPayloadNormalizer.NormalizedEvent keywordEvent = commentEvent('comment-keyword', 'media-comment', 'Need PRICING today');
        MetaCommentAttributionProcessor.process(keywordEvent);

        Social_Interaction__c keywordInteraction = [
            SELECT Lead__c, Campaign__c
            FROM Social_Interaction__c
            WHERE Meta_Comment_Id__c = 'comment-keyword'
            LIMIT 1
        ];
        System.assertNotEquals(null, keywordInteraction.Lead__c);
        System.assertEquals(campaignRecord.Id, keywordInteraction.Campaign__c);
    }

    @IsTest
    static void webhookControllerHandlesVerificationPostAndFailurePaths() {
        seedMetaConfig();
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.params.put('hub.mode', 'subscribe');
        RestContext.request.params.put('hub.verify_token', 'verify-token');
        RestContext.request.params.put('hub.challenge', 'challenge-ok');

        MetaWebhookController.verify();
        System.assertEquals('challenge-ok', RestContext.response.responseBody.toString());
        System.assertEquals(200, RestContext.response.statusCode);

        RestContext.request.params.put('hub.verify_token', 'wrong-token');
        MetaWebhookController.verify();
        System.assertEquals('Forbidden', RestContext.response.responseBody.toString());
        System.assertEquals(403, RestContext.response.statusCode);

        String body = '{"object":"page","entry":[{"id":"page-1","changes":[{"field":"leadgen","value":{"leadgen_id":"webhook-lead","campaign_id":"webhook-camp"}}]}]}';
        String signature = 'sha256=' + EncodingUtil.convertToHex(
            Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(TEST_SECRET))
        ).toLowerCase();

        RestRequest postRequest = new RestRequest();
        postRequest.requestBody = Blob.valueOf(body);
        postRequest.headers.put('X-Hub-Signature-256', signature);
        RestContext.request = postRequest;
        RestContext.response = new RestResponse();

        MetaWebhookController.MetaWebhookResponse accepted = MetaWebhookController.receive();
        System.assertEquals(true, accepted.success);
        System.assertNotEquals(null, accepted.workItemId);
        System.assertEquals(200, RestContext.response.statusCode);

        postRequest.headers.put('X-Hub-Signature-256', 'sha256=bad');
        RestContext.response = new RestResponse();
        MetaWebhookController.MetaWebhookResponse rejected = MetaWebhookController.receive();
        System.assertEquals(false, rejected.success);
        System.assertEquals(401, RestContext.response.statusCode);

        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        MetaWebhookController.MetaWebhookResponse empty = MetaWebhookController.receive();
        System.assertEquals(false, empty.success);
        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void schedulerAllowlistAndWorkerFailureBranchesAreCovered() {
        ConnectorAdapterAllowlist.assertAllowed(null);
        ConnectorAdapterAllowlist.assertAllowed('quickbridge.MetaIntegrationWorker');
        ConnectorAdapterAllowlist.assertAllowed('MetaScheduledOperationAdapter');
        try {
            ConnectorAdapterAllowlist.assertAllowed('NotApprovedAdapter');
            System.assert(false, 'Expected unapproved adapter to fail.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected.getMessage());
        }

        seedMetaConfig();
        Scheduled_Integration_Job__c campaignJob = new Scheduled_Integration_Job__c(
            Integration_Type__c = 'Meta',
            Source_Object__c = 'Campaign',
            Direction__c = 'In'
        );
        new MetaScheduledOperationAdapter().execute(campaignJob);
        Scheduled_Integration_Job__c insightsJob = new Scheduled_Integration_Job__c(
            Integration_Type__c = 'Meta',
            Source_Object__c = 'Insights',
            Direction__c = 'In'
        );
        new MetaScheduledOperationAdapter().execute(insightsJob);

        System.assertEquals(2, [SELECT COUNT() FROM Integration_Work_Item__c WHERE Integration__c = 'Meta']);

        try {
            new MetaIntegrationWorker().handle(null);
            System.assert(false, 'Expected null work item to fail.');
        } catch (MetaIntegrationWorker.MetaIntegrationWorkerException expected) {
            System.assert(expected.getMessage().contains('required'));
        }

        try {
            new MetaIntegrationWorker().handle(new Integration_Work_Item__c(Operation__c = 'Unsupported', Payload__c = '{}'));
            System.assert(false, 'Expected unsupported operation to fail.');
        } catch (MetaIntegrationWorker.MetaIntegrationWorkerException expected) {
            System.assert(expected.getMessage().contains('Unsupported'));
        }

        new MetaIntegrationWorker().handle(new Integration_Work_Item__c(Operation__c = 'CampaignSync', Payload__c = '{}'));
    }

    @IsTest
    static void integrationWorkerRoutesCommentWebhookAndReportingOperations() {
        seedMetaConfig();
        Campaign campaignRecord = new Campaign(
            Name = 'Worker Webhook Campaign',
            IsActive = true,
            Meta_Campaign_Id__c = 'worker-camp',
            Platform__c = 'Meta',
            Campaign_Source__c = 'Meta Ads'
        );
        insert campaignRecord;
        insert new Meta_Ad__c(
            Name = 'Worker Media Ad',
            Meta_Ad_Id__c = 'worker-ad',
            Campaign__c = campaignRecord.Id,
            Meta_Campaign_Id__c = 'worker-camp',
            Instagram_Media_Id__c = 'worker-media'
        );

        MetaPayloadNormalizer.NormalizedEvent directComment = commentEvent(
            'worker-direct-comment',
            'worker-media',
            'Need details'
        );
        new MetaIntegrationWorker().handle(new Integration_Work_Item__c(
            Operation__c = 'CommentAttribution',
            Payload__c = JSON.serialize(directComment)
        ));

        String webhookPayload = '{"object":"page","entry":[{"id":"page-1","changes":[' +
            '{"field":"leadgen","value":{"leadgen_id":"worker-lead","campaign_id":"worker-camp","ad_id":"worker-ad","email":"worker@example.com","full_name":"Worker Lead"}},' +
            '{"field":"feed","value":{"comment_id":"worker-webhook-comment","post_id":"worker-post","message":"Need quote","from":{"id":"worker-profile","name":"Webhook Buyer"}}}' +
            ']}]}';
        new MetaIntegrationWorker().handle(new Integration_Work_Item__c(
            Operation__c = 'WebhookEvent',
            Payload__c = webhookPayload
        ));
        new MetaIntegrationWorker().handle(new Integration_Work_Item__c(Operation__c = 'InsightsSync', Payload__c = '{}'));
        new MetaIntegrationWorker().handle(new Integration_Work_Item__c(Operation__c = 'Reconciliation', Payload__c = '{}'));

        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Meta_Leadgen_Id__c = 'worker-lead']);
        System.assertEquals(1, [SELECT COUNT() FROM Social_Interaction__c WHERE Meta_Comment_Id__c = 'worker-direct-comment']);
        System.assertEquals(1, [SELECT COUNT() FROM Social_Interaction__c WHERE Meta_Comment_Id__c = 'worker-webhook-comment']);
    }

    @IsTest
    static void attributionAndVerifierFallbackBranchesAreCovered() {
        MetaAttributionService.AttributionResult nullResult = MetaAttributionService.resolve(null);
        System.assertEquals('Unattributed', nullResult.status);

        MetaPayloadNormalizer.NormalizedEvent none = new MetaPayloadNormalizer.NormalizedEvent();
        none.campaignId = 'missing-campaign';
        System.assertEquals('Needs Review', MetaAttributionService.resolve(none).status);

        Campaign campaignRecord = new Campaign(
            Name = 'Fallback Campaign',
            IsActive = true,
            Meta_Campaign_Id__c = 'fallback-camp',
            Platform__c = 'Meta'
        );
        insert campaignRecord;
        Meta_Ad_Set__c adSetRecord = new Meta_Ad_Set__c(
            Name = 'Fallback Ad Set',
            Meta_Ad_Set_Id__c = 'fallback-adset',
            Campaign__c = campaignRecord.Id,
            Meta_Campaign_Id__c = 'fallback-camp'
        );
        insert adSetRecord;
        Meta_Ad__c adRecord = new Meta_Ad__c(
            Name = 'Fallback Ad',
            Meta_Ad_Id__c = 'fallback-ad',
            Meta_Ad_Set__c = adSetRecord.Id,
            Campaign__c = campaignRecord.Id,
            Post_Id__c = 'fallback-post',
            Instagram_Media_Id__c = 'fallback-media'
        );
        insert adRecord;

        MetaPayloadNormalizer.NormalizedEvent campaignEvent = new MetaPayloadNormalizer.NormalizedEvent();
        campaignEvent.campaignId = 'fallback-camp';
        System.assertEquals(campaignRecord.Id, MetaAttributionService.resolve(campaignEvent).campaignId);

        MetaPayloadNormalizer.NormalizedEvent adSetEvent = new MetaPayloadNormalizer.NormalizedEvent();
        adSetEvent.adSetId = 'fallback-adset';
        System.assertEquals(adSetRecord.Id, MetaAttributionService.resolve(adSetEvent).adSetId);

        MetaPayloadNormalizer.NormalizedEvent postEvent = new MetaPayloadNormalizer.NormalizedEvent();
        postEvent.postId = 'fallback-post';
        System.assertEquals(adRecord.Id, MetaAttributionService.resolve(postEvent).adId);

        MetaPayloadNormalizer.NormalizedEvent mediaEvent = new MetaPayloadNormalizer.NormalizedEvent();
        mediaEvent.instagramMediaId = 'fallback-media';
        System.assertEquals(adRecord.Id, MetaAttributionService.resolve(mediaEvent).adId);

        System.assertEquals(false, MetaWebhookVerifier.isValidSignature('', '', ''));
        System.assertEquals(false, MetaWebhookVerifier.isValidSignature('body', 'sha1=bad', TEST_SECRET));
        RestRequest request = new RestRequest();
        request.requestBody = Blob.valueOf('body');
        request.headers.put('x-hub-signature-256', 'sha256=bad');
        try {
            MetaWebhookVerifier.requireValidSignature('body', request);
            System.assert(false, 'Expected bad signature to fail.');
        } catch (MetaWebhookVerifier.MetaWebhookVerificationException expected) {
            System.assert(expected.getMessage().contains('failed'));
        }
    }

    private static void seedMetaConfig() {
        seedMetaConfig(new Map<String, String>());
    }

    private static void seedMetaConfig(Map<String, String> overrides) {
        Connector_Instance__c instanceRecord = new Connector_Instance__c(
            Name = 'Meta',
            Connector_Key__c = CONNECTOR_KEY,
            Connector_Label__c = 'Meta',
            Active__c = true,
            Health_Status__c = 'Unknown',
            Entitlement_Status__c = 'Active',
            Named_Credential__c = 'Meta_Graph_API'
        );
        insert instanceRecord;

        List<Connector_Config_Value__c> values = new List<Connector_Config_Value__c>{
            configValue(instanceRecord.Id, 'webhookVerifyTokenRef', 'verify-token', true),
            configValue(instanceRecord.Id, 'appSecretRef', TEST_SECRET, true),
            configValue(instanceRecord.Id, 'accessTokenRef', 'Meta_Access_Token_QA', true),
            configValue(instanceRecord.Id, 'adAccountId', 'act_123', false),
            configValue(instanceRecord.Id, 'leadAdsEnabled', 'true', false),
            configValue(instanceRecord.Id, 'defaultLeadSource', 'Meta Lead Ad', false),
            configValue(instanceRecord.Id, 'defaultCampaignMemberStatus', 'Responded', false),
            configValue(instanceRecord.Id, 'autoCreateCampaignMember', 'true', false)
        };
        if (overrides != null) {
            for (String fieldKey : overrides.keySet()) {
                values.add(configValue(instanceRecord.Id, fieldKey, overrides.get(fieldKey), false));
            }
        }
        insert values;
    }

    private static MetaPayloadNormalizer.NormalizedEvent commentEvent(String commentId, String mediaId, String text) {
        MetaPayloadNormalizer.NormalizedEvent eventRecord = new MetaPayloadNormalizer.NormalizedEvent();
        eventRecord.platform = 'Instagram';
        eventRecord.interactionType = 'Comment';
        eventRecord.commentId = commentId;
        eventRecord.instagramMediaId = mediaId;
        eventRecord.commenterName = 'Comment Buyer';
        eventRecord.commenterProfileId = 'profile-' + commentId;
        eventRecord.commentText = text;
        eventRecord.rawPayload = JSON.serialize(new Map<String, Object>{ 'id' => commentId, 'text' => text });
        return eventRecord;
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
}