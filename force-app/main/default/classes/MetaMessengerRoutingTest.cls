@IsTest
private class MetaMessengerRoutingTest {
  @IsTest
  static void messengerWebhookNormalizesInboundTextMessage() {
    MetaPayloadNormalizer.NormalizedEvent eventRecord = MetaPayloadNormalizer.firstEvent(messengerPayload('mid-1', 'Hello from Messenger'));

    System.assertEquals('Facebook', eventRecord.platform);
    System.assertEquals('Messenger Message', eventRecord.interactionType);
    System.assertEquals('mid-1', eventRecord.messageId);
    System.assertEquals('sender-1', eventRecord.senderProfileId);
    System.assertEquals('page-1', eventRecord.recipientPageId);
    System.assertEquals('Hello from Messenger', eventRecord.messageText);
    System.assertNotEquals(null, eventRecord.messageTimestamp);
  }

  @IsTest
  static void messengerWebhookIgnoresReadDeliveryEchoAndPostbackEvents() {
    String payload = '{"object":"page","entry":[{"id":"page-1","messaging":[' +
      '{"sender":{"id":"sender-1"},"recipient":{"id":"page-1"},"timestamp":1710000000000,"read":{"watermark":1710000000000}},' +
      '{"sender":{"id":"sender-1"},"recipient":{"id":"page-1"},"timestamp":1710000000000,"delivery":{"mids":["mid-delivered"]}},' +
      '{"sender":{"id":"sender-1"},"recipient":{"id":"page-1"},"timestamp":1710000000000,"postback":{"payload":"GET_STARTED"}},' +
      '{"sender":{"id":"page-1"},"recipient":{"id":"sender-1"},"timestamp":1710000000000,"message":{"mid":"mid-echo","text":"Echo","is_echo":true}},' +
      '{"sender":{"id":"sender-1"},"recipient":{"id":"page-1"},"timestamp":1710000000000,"message":{"mid":"mid-attachment","attachments":[{"type":"image"}]}}' +
      ']}]}';

    List<MetaPayloadNormalizer.NormalizedEvent> events = MetaPayloadNormalizer.fromWebhookPayload(payload);

    System.assertEquals(0, events.size());
  }

  @IsTest
  static void messengerWebhookRoutesThroughIntegrationWorkRouter() {
    Integration_Work_Item__c item = new Integration_Work_Item__c(
      Integration__c = 'Meta',
      Operation__c = 'WebhookEvent',
      Status__c = 'Pending',
      Lock_Key__c = 'MetaMessenger:mid-router',
      Unique_Key__c = 'MetaMessenger:mid-router',
      Payload__c = messengerPayload('mid-router', 'Route this DM')
    );
    insert item;

    Test.startTest();
    IntegrationWorkRouter.process(item);
    Test.stopTest();

    Social_Interaction__c interaction = [
      SELECT Platform__c, Interaction_Type__c, External_Key__c, Comment_Text__c, Commenter_Profile_Id__c, Meta_Post_Id__c
      FROM Social_Interaction__c
      WHERE External_Key__c = 'Facebook|messenger|mid-router'
      LIMIT 1
    ];
    System.assertEquals('Facebook', interaction.Platform__c);
    System.assertEquals('Messenger Message', interaction.Interaction_Type__c);
    System.assertEquals('Route this DM', interaction.Comment_Text__c);
    System.assertEquals('sender-1', interaction.Commenter_Profile_Id__c);
    System.assertEquals('page-1', interaction.Meta_Post_Id__c);
  }

  @IsTest
  static void messengerMessageUpsertsStableSocialInteraction() {
    MetaPayloadNormalizer.NormalizedEvent eventRecord = messengerEvent('mid-direct', 'First message');

    Test.startTest();
    Social_Interaction__c interaction = MetaMessengerMessageProcessor.process(eventRecord);
    Test.stopTest();

    System.assertEquals('Facebook|messenger|mid-direct', interaction.External_Key__c);
    System.assertEquals(1, [SELECT COUNT() FROM Social_Interaction__c WHERE External_Key__c = 'Facebook|messenger|mid-direct']);
  }

  @IsTest
  static void messengerDuplicateMessageCoalescesOrUpsertsIdempotently() {
    MetaPayloadNormalizer.NormalizedEvent firstEvent = messengerEvent('mid-duplicate', 'Original');
    MetaPayloadNormalizer.NormalizedEvent secondEvent = messengerEvent('mid-duplicate', 'Updated text');

    Test.startTest();
    MetaMessengerMessageProcessor.process(firstEvent);
    MetaMessengerMessageProcessor.process(secondEvent);
    Test.stopTest();

    Social_Interaction__c interaction = [
      SELECT Comment_Text__c
      FROM Social_Interaction__c
      WHERE External_Key__c = 'Facebook|messenger|mid-duplicate'
      LIMIT 1
    ];
    System.assertEquals('Updated text', interaction.Comment_Text__c);
    System.assertEquals(1, [SELECT COUNT() FROM Social_Interaction__c WHERE External_Key__c = 'Facebook|messenger|mid-duplicate']);
  }

  @IsTest
  static void instagramDmPayloadIsIgnored() {
    String payload = '{"object":"instagram","entry":[{"id":"ig-1","messaging":[{"sender":{"id":"sender-ig"},"recipient":{"id":"ig-1"},"timestamp":1710000000000,"message":{"mid":"ig-mid","text":"Instagram DM"}}]}]}';

    List<MetaPayloadNormalizer.NormalizedEvent> events = MetaPayloadNormalizer.fromWebhookPayload(payload);

    System.assertEquals(0, events.size());
  }

  private static MetaPayloadNormalizer.NormalizedEvent messengerEvent(String messageId, String messageText) {
    return MetaPayloadNormalizer.firstEvent(messengerPayload(messageId, messageText));
  }

  private static String messengerPayload(String messageId, String messageText) {
    return '{"object":"page","entry":[{"id":"page-1","messaging":[{"sender":{"id":"sender-1"},"recipient":{"id":"page-1"},"timestamp":1710000000000,"message":{"mid":"' +
      messageId +
      '","text":"' +
      messageText +
      '"}}]}]}';
  }
}
