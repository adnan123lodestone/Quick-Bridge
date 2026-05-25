public with sharing class QuickBridgeAdminControlPlaneService {
  @AuraEnabled
  public static String verifyCredentialsAndGetGateways(String username, String password) {
    return PaymentGatewayService.verifyCredentialsAndGetGateways(username, password);
  }

  @AuraEnabled
  public static Boolean revokeAdminSession(String sessionToken) {
    return PaymentGatewayService.revokeAdminSession(sessionToken);
  }

  @AuraEnabled
  public static String recoverPin(String username) {
    return PaymentGatewayService.recoverPin(username);
  }

  @AuraEnabled
  public static String refreshLicenses(String sessionToken) {
    return PaymentGatewayService.refreshLicenses(sessionToken);
  }

  @AuraEnabled
  public static String reseedSystemManagedProducts(String sessionToken) {
    QuickBridgeAdminSessionService.requireValidSession(sessionToken);
    return IntegrationProductSeedService.reseedSystemManagedProducts();
  }
}