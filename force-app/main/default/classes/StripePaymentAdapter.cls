public with sharing class StripePaymentAdapter implements PaymentProviderAdapter {
    public PaymentCheckoutController.ProviderDescriptor describe(ConnectorRegistryService.ConnectorDescriptor connector, Set<String> activeGatewayNames) {
        StripePaymentService.ClientConfigResponse config = StripePaymentService.getClientConfig();
        PaymentCheckoutController.ProviderDescriptor descriptor = baseDescriptor(connector, config.active == true && activeGatewayNames.contains('stripe'), config.configured, config.message, 'stripeElements', new List<String>{ 'cardName', 'billingAddress' });
        descriptor.clientScriptUrl = config.stripeJsUrl;
        descriptor.config.put('publishableKey', config.publishableKey);
        descriptor.config.put('useSandbox', config.useSandbox);
        descriptor.config.put('stripeJsUrl', config.stripeJsUrl);
        return descriptor;
    }

    public PaymentCheckoutController.PaymentResponse initializePayment(PaymentCheckoutController.PaymentRequest request) {
        return ok('Stripe is initialized by Stripe.js.');
    }

    public PaymentCheckoutController.PaymentResponse executePayment(PaymentCheckoutController.PaymentRequest request) {
        StripePaymentService.PaymentRequest stripeRequest = new StripePaymentService.PaymentRequest();
        stripeRequest.amount = request.amount;
        stripeRequest.allowPlatformSession = request.allowPlatformSession;
        stripeRequest.orderId = request.orderId;
        stripeRequest.sessionToken = request.sessionToken;
        stripeRequest.paymentMethodId = request.paymentMethodId;
        stripeRequest.fullName = request.fullName;
        stripeRequest.address = request.address;
        stripeRequest.city = request.city;
        stripeRequest.state = request.state;
        stripeRequest.zip = request.zip;
        stripeRequest.country = request.country;
        stripeRequest.currencyCode = String.isBlank(request.currencyCode) ? 'usd' : request.currencyCode;
        StripePaymentService.PaymentResponse response = StripePaymentService.processPayment(stripeRequest);
        return copyResponse(response.success, response.message, response.transId, response.resultCode, response.authCode, response.status, response.clientSecret, null, null);
    }

    private static PaymentCheckoutController.ProviderDescriptor baseDescriptor(ConnectorRegistryService.ConnectorDescriptor connector, Boolean active, Boolean configured, String message, String actionType, List<String> requiredInputFields) {
        PaymentCheckoutController.ProviderDescriptor descriptor = new PaymentCheckoutController.ProviderDescriptor();
        descriptor.connectorKey = connector.connectorKey;
        descriptor.label = connector.label;
        descriptor.active = active;
        descriptor.configured = configured;
        descriptor.message = message;
        descriptor.config = new Map<String, Object>();
        descriptor.displayOrder = connector.sortOrder;
        descriptor.capabilities = connector.capabilities == null ? new List<String>() : new List<String>(connector.capabilities);
        descriptor.requiredInputFields = requiredInputFields == null ? new List<String>() : requiredInputFields;
        descriptor.actionType = actionType;
        return descriptor;
    }

    private static PaymentCheckoutController.PaymentResponse ok(String message) {
        return copyResponse(true, message, null, 'Ok', null, null, null, null, null);
    }

    private static PaymentCheckoutController.PaymentResponse copyResponse(Boolean success, String message, String transId, String resultCode, String authCode, String status, String clientSecret, String paypalOrderId, String approveLink) {
        PaymentCheckoutController.PaymentResponse response = new PaymentCheckoutController.PaymentResponse();
        response.success = success;
        response.message = message;
        response.transId = transId;
        response.resultCode = resultCode;
        response.authCode = authCode;
        response.status = status;
        response.clientSecret = clientSecret;
        response.paypalOrderId = paypalOrderId;
        response.approveLink = approveLink;
        return response;
    }
}
