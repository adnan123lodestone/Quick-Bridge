public with sharing class QuickBridgeAdminControlPlaneService {
  @AuraEnabled
  public static String verifyCredentialsAndGetGateways(String username, String password) {
    return PaymentAdminService.verifyCredentialsAndGetGateways(username, password);
  }

  @AuraEnabled
  public static Boolean revokeAdminSession(String sessionToken) {
    return PaymentAdminService.revokeAdminSession(sessionToken);
  }

  @AuraEnabled
  public static String recoverPin(String username) {
    return PaymentAdminService.recoverPin(username);
  }

  @AuraEnabled
  public static String refreshLicenses(String sessionToken) {
    return PaymentAdminService.refreshLicenses(sessionToken);
  }

  @AuraEnabled
  public static String reseedSystemManagedProducts(String sessionToken) {
    QuickBridgeAdminSessionService.requireValidSession(sessionToken);
    return IntegrationProductSeedService.reseedSystemManagedProducts();
  }
}