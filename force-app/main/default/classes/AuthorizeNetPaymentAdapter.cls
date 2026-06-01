public with sharing class AuthorizeNetPaymentAdapter implements PaymentProviderAdapter {
    public PaymentCheckoutController.ProviderDescriptor describe(ConnectorRegistryService.ConnectorDescriptor connector, Set<String> activeGatewayNames) {
        AuthorizeNetPaymentService.ClientConfigResponse config = AuthorizeNetPaymentService.getClientConfig();
        PaymentCheckoutController.ProviderDescriptor descriptor = baseDescriptor(connector, config.active == true && activeGatewayNames.contains('authorizenet'), config.configured, config.message, 'acceptJs', new List<String>{ 'cardName', 'cardNumber', 'securityCode', 'cardMonth', 'cardYear', 'billingAddress' });
        descriptor.clientScriptUrl = config.acceptJsUrl;
        descriptor.config.put('apiLoginId', config.apiLoginId);
        descriptor.config.put('publicClientKey', config.publicClientKey);
        descriptor.config.put('useSandbox', config.useSandbox);
        descriptor.config.put('acceptJsUrl', config.acceptJsUrl);
        return descriptor;
    }

    public PaymentCheckoutController.PaymentResponse initializePayment(PaymentCheckoutController.PaymentRequest request) {
        return ok('Authorize.Net is initialized by Accept.js.');
    }

    public PaymentCheckoutController.PaymentResponse executePayment(PaymentCheckoutController.PaymentRequest request) {
        AuthorizeNetPaymentService.PaymentRequest authRequest = new AuthorizeNetPaymentService.PaymentRequest();
        authRequest.amount = request.amount;
        authRequest.allowPlatformSession = request.allowPlatformSession;
        authRequest.orderId = request.orderId;
        authRequest.sessionToken = request.sessionToken;
        authRequest.dataDescriptor = request.dataDescriptor;
        authRequest.dataValue = request.dataValue;
        authRequest.fullName = request.fullName;
        authRequest.address = request.address;
        authRequest.city = request.city;
        authRequest.state = request.state;
        authRequest.zip = request.zip;
        authRequest.country = request.country;
        authRequest.transactionType = String.isBlank(request.transactionType) ? 'authCaptureTransaction' : request.transactionType;
        AuthorizeNetPaymentService.PaymentResponse response = AuthorizeNetPaymentService.processOpaquePayment(authRequest);
        return copyResponse(response.success, response.message, response.transId, response.resultCode, response.authCode, null, null, null, null);
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