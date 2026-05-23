public with sharing class KlaviyoCampaignMembersAsync implements Queueable {
    private Id campaignId;

    public KlaviyoCampaignMembersAsync(Id campaignId) {
        this.campaignId = campaignId;
    }

    public void execute(QueueableContext context) {
        Database.executeBatch(new KlaviyoCampaignMembersBatch(campaignId), 1);
    }
}
