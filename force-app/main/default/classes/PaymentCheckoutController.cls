public with sharing class PaymentCheckoutController {
    public class ProviderDescriptor {
        @AuraEnabled public String connectorKey { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Boolean configured { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String clientScriptUrl { get; set; }
        @AuraEnabled public Map<String, Object> config { get; set; }
    }

    public class PaymentRequest {
        @AuraEnabled public String providerKey { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Boolean allowPlatformSession { get; set; }
        @AuraEnabled public String orderId { get; set; }
        @AuraEnabled public String sessionToken { get; set; }
        @AuraEnabled public String paymentMethodId { get; set; }
        @AuraEnabled public String paypalOrderId { get; set; }
        @AuraEnabled public String dataDescriptor { get; set; }
        @AuraEnabled public String dataValue { get; set; }
        @AuraEnabled public String fullName { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String zip { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String currencyCode { get; set; }
        @AuraEnabled public String transactionType { get; set; }
    }

    public class PaymentResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String transId { get; set; }
        @AuraEnabled public String resultCode { get; set; }
        @AuraEnabled public String authCode { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String clientSecret { get; set; }
        @AuraEnabled public String paypalOrderId { get; set; }
        @AuraEnabled public String approveLink { get; set; }
    }

    @AuraEnabled
    public static List<ProviderDescriptor> getCheckoutProviders() {
        Set<String> activeGateways = activeGatewaysForCheckout();
        List<ProviderDescriptor> result = new List<ProviderDescriptor>();
        for (ConnectorRegistryService.ConnectorDescriptor connector : ConnectorRegistryService.byCapability('payment.checkout')) {
            PaymentProviderAdapter adapter = PaymentProviderRouter.adapterFor(connector.connectorKey);
            if (adapter != null) {
                result.add(adapter.describe(connector, activeGateways));
            }
        }
        return result;
    }

    @AuraEnabled
    public static PaymentResponse initializePayment(PaymentRequest request) {
        return PaymentProviderRouter.route(request == null ? null : request.providerKey).initializePayment(request);
    }

    @AuraEnabled
    public static PaymentResponse executePayment(PaymentRequest request) {
        return PaymentProviderRouter.route(request == null ? null : request.providerKey).executePayment(request);
    }

    private static Set<String> activeGatewaysForCheckout() {
        Set<String> activeGateways = new Set<String>();
        try {
            String raw = PaymentGatewayService.getActiveGatewaysForCheckout();
            Map<String, Object> payload = (Map<String, Object>)JSON.deserializeUntyped(raw);
            if (String.valueOf(payload.get('status')) != 'Success') {
                return activeGateways;
            }
            for (Object gateway : (List<Object>)payload.get('activeGateways')) {
                activeGateways.add(String.valueOf(gateway).toLowerCase().trim());
            }
        } catch (Exception ignored) {
        }
        return activeGateways;
    }
}