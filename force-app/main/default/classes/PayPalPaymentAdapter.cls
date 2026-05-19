public with sharing class PayPalPaymentAdapter implements PaymentProviderAdapter {
    public PaymentCheckoutController.ProviderDescriptor describe(ConnectorRegistryService.ConnectorDescriptor connector, Set<String> activeGatewayNames) {
        PayPalPaymentService.ClientConfigResponse config = PayPalPaymentService.getClientConfig();
        PaymentCheckoutController.ProviderDescriptor descriptor = baseDescriptor(connector, config.active == true && activeGatewayNames.contains('paypal'), config.configured, config.message);
        descriptor.clientScriptUrl = config.payPalJsUrl;
        descriptor.config.put('clientId', config.clientId);
        descriptor.config.put('useSandbox', config.useSandbox);
        descriptor.config.put('payPalJsUrl', config.payPalJsUrl);
        return descriptor;
    }

    public PaymentCheckoutController.PaymentResponse initializePayment(PaymentCheckoutController.PaymentRequest request) {
        PayPalPaymentService.PaymentRequest paypalRequest = new PayPalPaymentService.PaymentRequest();
        paypalRequest.amount = request.amount;
        paypalRequest.allowPlatformSession = request.allowPlatformSession;
        paypalRequest.orderId = request.orderId;
        paypalRequest.sessionToken = request.sessionToken;
        paypalRequest.fullName = request.fullName;
        paypalRequest.address = request.address;
        paypalRequest.city = request.city;
        paypalRequest.state = request.state;
        paypalRequest.zip = request.zip;
        paypalRequest.country = request.country;
        paypalRequest.currencyCode = String.isBlank(request.currencyCode) ? 'USD' : request.currencyCode;
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.createOrder(paypalRequest);
        return copyResponse(response.success, response.message, response.transId, response.resultCode, response.authCode, response.status, null, response.paypalOrderId, response.approveLink);
    }

    public PaymentCheckoutController.PaymentResponse executePayment(PaymentCheckoutController.PaymentRequest request) {
        PayPalPaymentService.CaptureRequest captureRequest = new PayPalPaymentService.CaptureRequest();
        captureRequest.paypalOrderId = request.paypalOrderId;
        captureRequest.allowPlatformSession = request.allowPlatformSession;
        captureRequest.orderId = request.orderId;
        captureRequest.sessionToken = request.sessionToken;
        PayPalPaymentService.PaymentResponse response = PayPalPaymentService.captureOrder(captureRequest);
        return copyResponse(response.success, response.message, response.transId, response.resultCode, response.authCode, response.status, null, response.paypalOrderId, response.approveLink);
    }

    private static PaymentCheckoutController.ProviderDescriptor baseDescriptor(ConnectorRegistryService.ConnectorDescriptor connector, Boolean active, Boolean configured, String message) {
        PaymentCheckoutController.ProviderDescriptor descriptor = new PaymentCheckoutController.ProviderDescriptor();
        descriptor.connectorKey = connector.connectorKey;
        descriptor.label = connector.label;
        descriptor.active = active;
        descriptor.configured = configured;
        descriptor.message = message;
        descriptor.config = new Map<String, Object>();
        return descriptor;
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
