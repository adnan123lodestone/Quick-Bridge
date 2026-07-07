public with sharing class MetaMessengerMessageProcessor {
  public static Social_Interaction__c process(MetaPayloadNormalizer.NormalizedEvent eventRecord) {
    if (eventRecord == null) {
      throw new MetaMessengerMessageException('Meta Messenger event is required.');
    }
    if (String.isBlank(eventRecord.messageId)) {
      throw new MetaMessengerMessageException('Meta Messenger message ID is required.');
    }

    String externalKey = 'Facebook|messenger|' + eventRecord.messageId.trim();
    List<Social_Interaction__c> existing = [
      SELECT Id
      FROM Social_Interaction__c
      WHERE External_Key__c = :externalKey
      LIMIT 1
    ];
    Social_Interaction__c interaction = existing.isEmpty()
      ? new Social_Interaction__c()
      : existing[0];
    interaction.Name = eventRecord.messageId.left(80);
    interaction.External_Key__c = externalKey;
    interaction.Platform__c = 'Facebook';
    interaction.Interaction_Type__c = 'Messenger Message';
    interaction.Comment_Text__c = eventRecord.messageText;
    interaction.Commenter_Profile_Id__c = eventRecord.senderProfileId;
    interaction.Meta_Post_Id__c = eventRecord.recipientPageId;
    interaction.Processing_Status__c = 'Processed';
    interaction.Attribution_Status__c = 'Unattributed';
    interaction.Raw_Payload__c = eventRecord.rawPayload;
    upsert interaction External_Key__c;
    return interaction;
  }

  public class MetaMessengerMessageException extends Exception {}
}