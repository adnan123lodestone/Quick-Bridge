public interface PaymentProviderAdapter {
    PaymentCheckoutController.ProviderDescriptor describe(ConnectorRegistryService.ConnectorDescriptor connector, Set<String> activeGatewayNames);
    PaymentCheckoutController.PaymentResponse initializePayment(PaymentCheckoutController.PaymentRequest request);
    PaymentCheckoutController.PaymentResponse executePayment(PaymentCheckoutController.PaymentRequest request);
}