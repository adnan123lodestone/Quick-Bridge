@IsTest
private class MetaSocialInteractionServiceTest {
    @IsTest
    static void upsertInteractionRejectsEventsWithoutStableExternalKey() {
        MetaPayloadNormalizer.NormalizedEvent eventRecord = new MetaPayloadNormalizer.NormalizedEvent();
        eventRecord.platform = 'Facebook';
        eventRecord.interactionType = 'Comment';
        eventRecord.commentText = 'No stable Meta identifier';

        try {
            MetaSocialInteractionService.upsertInteraction(eventRecord, null, null);
            System.assert(false, 'Expected Meta events without leadgenId or commentId to fail before DML.');
        } catch (MetaSocialInteractionService.MetaSocialInteractionException expected) {
            System.assert(
                expected.getMessage().contains('leadgenId or commentId'),
                'Exception should explain which Meta identifiers are required.'
            );
        }
    }

    @IsTest
    static void upsertInteractionKeepsLeadgenIdempotency() {
        MetaPayloadNormalizer.NormalizedEvent eventRecord = new MetaPayloadNormalizer.NormalizedEvent();
        eventRecord.platform = 'Meta';
        eventRecord.interactionType = 'Meta Lead Ad';
        eventRecord.leadgenId = 'leadgen-service-test';
        eventRecord.rawPayload = '{"leadgen_id":"leadgen-service-test"}';

        Test.startTest();
        Social_Interaction__c firstInteraction = MetaSocialInteractionService.upsertInteraction(eventRecord, null, null);
        Social_Interaction__c secondInteraction = MetaSocialInteractionService.upsertInteraction(eventRecord, null, null);
        Test.stopTest();

        System.assertEquals(firstInteraction.Id, secondInteraction.Id, 'Repeated leadgen events should update one interaction.');
        System.assertEquals('Meta|leadgen|leadgen-service-test', secondInteraction.External_Key__c);
        System.assertEquals(1, [SELECT COUNT() FROM Social_Interaction__c WHERE Meta_Leadgen_Id__c = 'leadgen-service-test']);
    }
}
