public with sharing class KlaviyoCampaignMembersAsync implements Queueable {
    private Id campaignId;

    public KlaviyoCampaignMembersAsync(Id campaignId) {
        this.campaignId = campaignId;
    }

    public void execute(QueueableContext context) {
        Database.executeBatch(
            new ConnectorInboundBatch(buildSharedRequest(campaignId)),
            1
        );
    }

    @TestVisible
    private static ConnectorExecutionRequest buildSharedRequest(Id campaignId) {
        if (campaignId == null || campaignId.getSObjectType() != Campaign.SObjectType) {
            throw new KlaviyoCampaignMembersAsyncException(
                'A Campaign record ID is required for campaign member synchronization.'
            );
        }
        ConnectorExecutionRequest request = new ConnectorExecutionRequest();
        request.connectorKey = 'Klaviyo';
        request.operationKey = 'CampaignMemberSync';
        request.direction = ConnectorExecutionRequest.DIRECTION_INBOUND;
        request.salesforceObject = 'Campaign';
        request.externalEntity = 'CampaignMember';
        request.recordIds.add(campaignId);
        request.correlationKey = String.valueOf(campaignId);
        request.scopeSize = 1;
        return request;
    }

    public class KlaviyoCampaignMembersAsyncException extends Exception {}
}