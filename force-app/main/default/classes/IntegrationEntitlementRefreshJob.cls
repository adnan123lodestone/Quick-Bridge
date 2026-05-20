public with sharing class IntegrationEntitlementRefreshJob implements Queueable, Database.AllowsCallouts {
  private String cacheKey;

  public IntegrationEntitlementRefreshJob(String cacheKey) {
    this.cacheKey = cacheKey;
  }

  public void execute(QueueableContext context) {
    if (String.isBlank(cacheKey) || cacheKey == 'checkout') {
      IntegrationEntitlementService.refreshCheckoutEntitlement(
        null,
        null,
        false
      );
    }
  }
}