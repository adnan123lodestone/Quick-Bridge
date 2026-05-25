public with sharing class QuickBridgeRuntimeGatewayService {
  @AuraEnabled
  public static String getActiveGatewaysForCheckout() {
    return PaymentGatewayService.getActiveGatewaysForCheckout();
  }

  @AuraEnabled
  public static Boolean isClientAuthorized(String gatewayName) {
    return PaymentGatewayService.isClientAuthorized(gatewayName);
  }
}