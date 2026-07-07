@IsTest
private class MetaInstagramScopeTest {
  @IsTest
  static void instagramAliasResolvesToMetaWithoutStandaloneConnector() {
    ConnectorRegistryService.ConnectorDescriptor instagram = ConnectorRegistryService.byKey('instagram');

    System.assertEquals('meta', instagram.connectorKey);
    System.assertEquals('Facebook / Instagram', instagram.label);
    System.assertEquals('MetaIntegrationWorker', IntegrationWorkRouter.handlerClassFor('instagram', 'CommentAttribution'));
  }

  @IsTest
  static void instagramCommentPayloadNormalizesCommentOnly() {
    String payload = '{"object":"instagram","entry":[{"id":"ig-1","changes":[{"field":"comments","value":{"id":"comment-1","media_id":"media-1","from":{"id":"profile-1","username":"buyer"},"text":"Need pricing"}}]}]}';

    MetaPayloadNormalizer.NormalizedEvent eventRecord = MetaPayloadNormalizer.firstEvent(payload);

    System.assertEquals('Instagram', eventRecord.platform);
    System.assertEquals('Comment', eventRecord.interactionType);
    System.assertEquals('comment-1', eventRecord.commentId);
    System.assertEquals('media-1', eventRecord.instagramMediaId);
  }

  @IsTest
  static void instagramMediaIdAttributionResolvesExistingMetaAd() {
    Campaign campaignRecord = new Campaign(
      Name = 'Instagram Attribution Campaign',
      IsActive = true,
      Meta_Campaign_Id__c = 'camp-instagram',
      Platform__c = 'Meta'
    );
    insert campaignRecord;
    Meta_Ad__c adRecord = new Meta_Ad__c(
      Name = 'Instagram Attribution Ad',
      Meta_Ad_Id__c = 'ad-instagram',
      Campaign__c = campaignRecord.Id,
      Meta_Campaign_Id__c = 'camp-instagram',
      Instagram_Media_Id__c = 'media-instagram'
    );
    insert adRecord;

    MetaPayloadNormalizer.NormalizedEvent eventRecord = new MetaPayloadNormalizer.NormalizedEvent();
    eventRecord.platform = 'Instagram';
    eventRecord.interactionType = 'Comment';
    eventRecord.instagramMediaId = 'media-instagram';

    MetaAttributionService.AttributionResult result = MetaAttributionService.resolve(eventRecord);

    System.assertEquals(adRecord.Id, result.adId);
    System.assertEquals(campaignRecord.Id, result.campaignId);
  }

  @IsTest
  static void unsupportedInstagramWebhookFieldIsIgnored() {
    String payload = '{"object":"instagram","entry":[{"id":"ig-1","changes":[{"field":"messages","value":{"id":"message-1","text":"DM text"}}]}]}';

    List<MetaPayloadNormalizer.NormalizedEvent> events = MetaPayloadNormalizer.fromWebhookPayload(payload);

    System.assertEquals(0, events.size(), 'Unsupported Instagram webhook fields should not be normalized as comments.');
  }
}
