@IsTest
private class MetaWebhookRoutingTest {
  private static final String TEST_SECRET = 'meta-test-secret';

  @IsTest
  static void signedPostQueuesStableWebhookWorkItemAndCoalescesDuplicates() {
    seedMetaConfig();
    String body = leadgenPayload('leadgen-coalesced', 'camp-webhook');

    Test.startTest();
    MetaWebhookController.MetaWebhookResponse firstResponse = receiveSigned(body);
    MetaWebhookController.MetaWebhookResponse secondResponse = receiveSigned(body);
    Test.stopTest();

    System.assertEquals(true, firstResponse.success);
    System.assertEquals(true, secondResponse.success);
    System.assertEquals(firstResponse.workItemId, secondResponse.workItemId);
    Integration_Work_Item__c item = [
      SELECT Source_Record_Id__c, Lock_Key__c, Operation__c, Coalesced_Count__c
      FROM Integration_Work_Item__c
      WHERE Id = :firstResponse.workItemId
      LIMIT 1
    ];
    System.assertEquals('WebhookEvent', item.Operation__c);
    System.assert(item.Lock_Key__c.startsWith('MetaWebhook:'));
    System.assertEquals(1, Integer.valueOf(item.Coalesced_Count__c));
  }

  @IsTest
  static void queuedLeadgenWebhookRoutesThroughIntegrationWorkRouter() {
    seedMetaConfig();
    Campaign campaignRecord = new Campaign(
      Name = 'Webhook Campaign',
      IsActive = true,
      Meta_Campaign_Id__c = 'camp-webhook',
      Platform__c = 'Meta'
    );
    insert campaignRecord;
    String body = leadgenPayload('leadgen-webhook', 'camp-webhook');
    MetaWebhookController.MetaWebhookResponse response = receiveSigned(body);
    Integration_Work_Item__c item = [
      SELECT Id, Integration__c, Operation__c, Payload__c
      FROM Integration_Work_Item__c
      WHERE Id = :response.workItemId
      LIMIT 1
    ];

    Test.startTest();
    IntegrationWorkRouter.process(item);
    IntegrationWorkRouter.process(item);
    Test.stopTest();

    Lead leadRecord = [
      SELECT Id, Meta_Leadgen_Id__c, Primary_Campaign__c
      FROM Lead
      WHERE Meta_Leadgen_Id__c = 'leadgen-webhook'
      LIMIT 1
    ];
    System.assertEquals(campaignRecord.Id, leadRecord.Primary_Campaign__c);
    System.assertEquals(1, [SELECT COUNT() FROM Social_Interaction__c WHERE Meta_Leadgen_Id__c = 'leadgen-webhook']);
    System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campaignRecord.Id AND LeadId = :leadRecord.Id]);
  }

  @IsTest
  static void queuedInstagramCommentWebhookRoutesThroughIntegrationWorkRouter() {
    seedMetaConfig(new Map<String, String>{ 'leadCreationMode' => 'Manual Review' });
    Campaign campaignRecord = new Campaign(
      Name = 'Instagram Comment Campaign',
      IsActive = true,
      Meta_Campaign_Id__c = 'camp-instagram',
      Platform__c = 'Meta'
    );
    insert campaignRecord;
    insert new Meta_Ad__c(
      Name = 'Instagram Media Ad',
      Meta_Ad_Id__c = 'ad-instagram',
      Campaign__c = campaignRecord.Id,
      Meta_Campaign_Id__c = 'camp-instagram',
      Instagram_Media_Id__c = 'media-instagram'
    );

    MetaWebhookController.MetaWebhookResponse response = receiveSigned(instagramCommentPayload());
    Integration_Work_Item__c item = [
      SELECT Id, Integration__c, Operation__c, Payload__c
      FROM Integration_Work_Item__c
      WHERE Id = :response.workItemId
      LIMIT 1
    ];

    Test.startTest();
    IntegrationWorkRouter.process(item);
    Test.stopTest();

    Social_Interaction__c interaction = [
      SELECT Platform__c, Instagram_Media_Id__c, Meta_Comment_Id__c, Campaign__c
      FROM Social_Interaction__c
      WHERE Meta_Comment_Id__c = 'comment-instagram'
      LIMIT 1
    ];
    System.assertEquals('Instagram', interaction.Platform__c);
    System.assertEquals('media-instagram', interaction.Instagram_Media_Id__c);
    System.assertEquals(campaignRecord.Id, interaction.Campaign__c);
  }

  @IsTest
  static void badSignatureCreatesNoWorkItem() {
    seedMetaConfig();
    RestRequest request = new RestRequest();
    request.requestBody = Blob.valueOf(leadgenPayload('leadgen-bad', 'camp-bad'));
    request.headers.put('X-Hub-Signature-256', 'sha256=bad');
    RestContext.request = request;
    RestContext.response = new RestResponse();

    Test.startTest();
    MetaWebhookController.MetaWebhookResponse response = MetaWebhookController.receive();
    Test.stopTest();

    System.assertEquals(false, response.success);
    System.assertEquals(401, RestContext.response.statusCode);
    System.assertEquals(0, [SELECT COUNT() FROM Integration_Work_Item__c WHERE Integration__c = 'Meta']);
  }

  private static MetaWebhookController.MetaWebhookResponse receiveSigned(String body) {
    RestRequest request = new RestRequest();
    request.requestBody = Blob.valueOf(body);
    request.headers.put('X-Hub-Signature-256', signatureFor(body));
    RestContext.request = request;
    RestContext.response = new RestResponse();
    return MetaWebhookController.receive();
  }

  private static String signatureFor(String body) {
    return 'sha256=' + EncodingUtil.convertToHex(
      Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(TEST_SECRET))
    ).toLowerCase();
  }

  private static String leadgenPayload(String leadgenId, String campaignId) {
    return '{"object":"page","entry":[{"id":"page-1","changes":[{"field":"leadgen","value":{"leadgen_id":"' +
      leadgenId +
      '","campaign_id":"' +
      campaignId +
      '","email":"lead@example.com","full_name":"Webhook Lead"}}]}]}';
  }

  private static String instagramCommentPayload() {
    return '{"object":"instagram","entry":[{"id":"ig-1","changes":[{"field":"comments","value":{"id":"comment-instagram","media_id":"media-instagram","from":{"id":"profile-1","username":"buyer"},"text":"Need pricing"}}]}]}';
  }

  private static void seedMetaConfig() {
    seedMetaConfig(new Map<String, String>());
  }

  private static void seedMetaConfig(Map<String, String> overrides) {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'Meta',
      Connector_Key__c = 'meta',
      Connector_Label__c = 'Meta',
      Active__c = true,
      Health_Status__c = 'Unknown',
      Entitlement_Status__c = 'Active',
      Named_Credential__c = 'Meta_Graph_API'
    );
    insert instanceRecord;

    Map<String, String> values = new Map<String, String>{
      'webhookVerifyTokenRef' => 'verify-token',
      'appSecretRef' => TEST_SECRET,
      'accessTokenRef' => 'Meta_Access_Token_QA',
      'adAccountId' => 'act_123',
      'pageId' => 'page-123',
      'instagramBusinessAccountId' => 'ig-123',
      'leadAdsEnabled' => 'true',
      'commentAttributionEnabled' => 'true',
      'defaultLeadSource' => 'Meta Lead Ad',
      'defaultCampaignMemberStatus' => 'Responded',
      'autoCreateCampaignMember' => 'true'
    };
    if (overrides != null) {
      values.putAll(overrides);
    }
    List<Connector_Config_Value__c> rows = new List<Connector_Config_Value__c>();
    for (String fieldKey : values.keySet()) {
      rows.add(new Connector_Config_Value__c(
        Name = 'meta:' + fieldKey,
        Connector_Instance__c = instanceRecord.Id,
        Connector_Key__c = 'meta',
        Field_Key__c = fieldKey,
        Value__c = values.get(fieldKey),
        Is_Secret_Reference__c = new Set<String>{ 'webhookVerifyTokenRef', 'appSecretRef', 'accessTokenRef' }.contains(fieldKey)
      ));
    }
    insert rows;
  }
}
