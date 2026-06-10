public with sharing class PaymentCheckoutGateway {

    public class ProviderDescriptor {
        @AuraEnabled public String connectorKey { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Boolean configured { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String clientScriptUrl { get; set; }
        @AuraEnabled public Map<String, Object> config { get; set; }
        @AuraEnabled public Integer displayOrder { get; set; }
        @AuraEnabled public List<String> capabilities { get; set; }
        @AuraEnabled public List<String> requiredInputFields { get; set; }
        @AuraEnabled public String actionType { get; set; }
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
        try {
            List<PaymentCheckoutController.ProviderDescriptor> source = PaymentCheckoutController.getCheckoutProviders();
            List<ProviderDescriptor> result = new List<ProviderDescriptor>();
            for (PaymentCheckoutController.ProviderDescriptor src : source) {
                ProviderDescriptor d = new ProviderDescriptor();
                d.connectorKey = src.connectorKey;
                d.label = src.label;
                d.active = src.active;
                d.configured = src.configured;
                d.message = src.message;
                d.clientScriptUrl = src.clientScriptUrl;
                d.config = src.config;
                d.displayOrder = src.displayOrder;
                d.capabilities = src.capabilities;
                d.requiredInputFields = src.requiredInputFields;
                d.actionType = src.actionType;
                result.add(d);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static PaymentResponse initializePayment(PaymentRequest request) {
        try {
            PaymentCheckoutController.PaymentRequest ctrlReq = toControllerRequest(request);
            PaymentCheckoutController.PaymentResponse resp = PaymentCheckoutController.initializePayment(ctrlReq);
            return toGatewayResponse(resp);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String initializePaymentJson(String requestJson) {
        try {
            PaymentCheckoutController.PaymentRequest ctrlReq = toControllerRequest(requestJson);
            PaymentCheckoutController.PaymentResponse resp = PaymentCheckoutController.initializePayment(ctrlReq);
            return JSON.serialize(toGatewayResponse(resp));
        } catch (Exception e) {
            return JSON.serialize(errorResponse(e));
        }
    }

    @AuraEnabled
    public static PaymentResponse executePayment(PaymentRequest request) {
        try {
            PaymentCheckoutController.PaymentRequest ctrlReq = toControllerRequest(request);
            PaymentCheckoutController.PaymentResponse resp = PaymentCheckoutController.executePayment(ctrlReq);
            return toGatewayResponse(resp);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String executePaymentJson(String requestJson) {
        try {
            PaymentCheckoutController.PaymentRequest ctrlReq = toControllerRequest(requestJson);
            PaymentCheckoutController.PaymentResponse resp = PaymentCheckoutController.executePayment(ctrlReq);
            return JSON.serialize(toGatewayResponse(resp));
        } catch (Exception e) {
            return JSON.serialize(errorResponse(e));
        }
    }

    private static PaymentCheckoutController.PaymentRequest toControllerRequest(String requestJson) {
        PaymentCheckoutController.PaymentRequest ctrlReq = new PaymentCheckoutController.PaymentRequest();
        if (String.isBlank(requestJson)) return ctrlReq;

        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(requestJson);
        ctrlReq.providerKey = stringValue(raw.get('providerKey'));
        ctrlReq.amount = decimalValue(raw.get('amount'));
        ctrlReq.allowPlatformSession = booleanValue(raw.get('allowPlatformSession'));
        ctrlReq.orderId = stringValue(raw.get('orderId'));
        ctrlReq.sessionToken = stringValue(raw.get('sessionToken'));
        ctrlReq.paymentMethodId = stringValue(raw.get('paymentMethodId'));
        ctrlReq.paypalOrderId = stringValue(raw.get('paypalOrderId'));
        ctrlReq.dataDescriptor = stringValue(raw.get('dataDescriptor'));
        ctrlReq.dataValue = stringValue(raw.get('dataValue'));
        ctrlReq.fullName = stringValue(raw.get('fullName'));
        ctrlReq.address = stringValue(raw.get('address'));
        ctrlReq.city = stringValue(raw.get('city'));
        ctrlReq.state = stringValue(raw.get('state'));
        ctrlReq.zip = stringValue(raw.get('zip'));
        ctrlReq.country = stringValue(raw.get('country'));
        ctrlReq.currencyCode = stringValue(raw.get('currencyCode'));
        ctrlReq.transactionType = stringValue(raw.get('transactionType'));
        return ctrlReq;
    }

    private static PaymentCheckoutController.PaymentRequest toControllerRequest(PaymentRequest req) {
        PaymentCheckoutController.PaymentRequest ctrlReq = new PaymentCheckoutController.PaymentRequest();
        if (req == null) return ctrlReq;
        ctrlReq.providerKey = req.providerKey;
        ctrlReq.amount = req.amount;
        ctrlReq.allowPlatformSession = req.allowPlatformSession;
        ctrlReq.orderId = req.orderId;
        ctrlReq.sessionToken = req.sessionToken;
        ctrlReq.paymentMethodId = req.paymentMethodId;
        ctrlReq.paypalOrderId = req.paypalOrderId;
        ctrlReq.dataDescriptor = req.dataDescriptor;
        ctrlReq.dataValue = req.dataValue;
        ctrlReq.fullName = req.fullName;
        ctrlReq.address = req.address;
        ctrlReq.city = req.city;
        ctrlReq.state = req.state;
        ctrlReq.zip = req.zip;
        ctrlReq.country = req.country;
        ctrlReq.currencyCode = req.currencyCode;
        ctrlReq.transactionType = req.transactionType;
        return ctrlReq;
    }

    private static PaymentResponse errorResponse(Exception e) {
        PaymentResponse resp = new PaymentResponse();
        resp.success = false;
        resp.resultCode = 'Error';
        resp.message = e == null || String.isBlank(e.getMessage())
            ? 'Payment could not be completed.'
            : e.getMessage();
        return resp;
    }

    private static PaymentResponse toGatewayResponse(PaymentCheckoutController.PaymentResponse src) {
        PaymentResponse resp = new PaymentResponse();
        if (src == null) return resp;
        resp.success = src.success;
        resp.message = src.message;
        resp.transId = src.transId;
        resp.resultCode = src.resultCode;
        resp.authCode = src.authCode;
        resp.status = src.status;
        resp.clientSecret = src.clientSecret;
        resp.paypalOrderId = src.paypalOrderId;
        resp.approveLink = src.approveLink;
        return resp;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal decimalValue(Object value) {
        if (value == null) return null;
        String textValue = String.valueOf(value);
        return String.isBlank(textValue) ? null : Decimal.valueOf(textValue);
    }

    private static Boolean booleanValue(Object value) {
        if (value == null) return null;
        if (value instanceof Boolean) return (Boolean) value;
        return 'true'.equalsIgnoreCase(String.valueOf(value));
    }
}