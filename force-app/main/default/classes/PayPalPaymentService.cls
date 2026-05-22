public with sharing class PayPalPaymentService {
    @TestVisible private static String testBaseEndpointOverride;
    @TestVisible private static String testAccessTokenOverride;
    
    private static final String PAYPAL_SANDBOX_API_ENDPOINT = 'callout:PayPal_API_Sandbox';
    private static final String PAYPAL_PRODUCTION_API_ENDPOINT = 'callout:PayPal_API_Production';
    private static final String PAYPAL_CLIENT_ID_MERGE_FIELD = '{!$Credential.PayPal_Credentials.ClientId}';
    private static final String PAYPAL_CLIENT_SECRET_MERGE_FIELD = '{!$Credential.PayPal_Credentials.ClientSecret}';
    private static final String PAYPAL_JS_SDK_BASE_URL = 'https://www.paypal.com/sdk/js';
    
    public class ClientConfigResponse {
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Boolean configured { get; set; }
        @AuraEnabled public String clientId { get; set; }
        @AuraEnabled public Boolean useSandbox { get; set; }
        @AuraEnabled public String payPalJsUrl { get; set; }
        @AuraEnabled public String message { get; set; }
    }
    
    public class PaymentRequest {
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Boolean allowPlatformSession { get; set; }
        @AuraEnabled public String orderId { get; set; }
        @AuraEnabled public String sessionToken { get; set; }
        @AuraEnabled public String fullName { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String zip { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String currencyCode { get; set; }
    }
    
    public class CaptureRequest {
        @AuraEnabled public String paypalOrderId { get; set; }
        @AuraEnabled public Boolean allowPlatformSession { get; set; }
        @AuraEnabled public String orderId { get; set; }
        @AuraEnabled public String sessionToken { get; set; }
    }
    
    public class PaymentResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String transId { get; set; }
        @AuraEnabled public String resultCode { get; set; }
        @AuraEnabled public String authCode { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String paypalOrderId { get; set; }
        @AuraEnabled public String approveLink { get; set; }
    }
    
    @AuraEnabled(cacheable=true)
    public static ClientConfigResponse getClientConfig() {
        ClientConfigResponse response = new ClientConfigResponse();
        try {
            Quickbridge_Config__mdt config = getConfig();
            
            String availabilityMessage = getAvailabilityMessage(config);
            response.active = availabilityMessage == null;
            response.clientId = config.PayPal_ClientId__c;
            response.useSandbox = config.PayPal_UseSandbox__c;
            response.payPalJsUrl = buildPayPalJsUrl(config.PayPal_ClientId__c);
            
            List<String> missingItems = new List<String>();
            if (String.isBlank(config.PayPal_ClientId__c)) {
                missingItems.add('Client Id');
            }
            
            response.configured = response.active && missingItems.isEmpty();
            if (availabilityMessage != null) {
                response.message = availabilityMessage;
            } else if (!missingItems.isEmpty()) {
                response.message = 'PayPal is not fully configured. Missing: ' + String.join(missingItems, ', ');
            } else {
                response.message = 'PayPal client configuration loaded.';
            }
        } catch (Exception e) {
            response.active = false;
            response.configured = false;
            response.message = 'Unable to load PayPal client configuration.';
            System.debug(LoggingLevel.ERROR,
            'PayPalPaymentService.getClientConfig exception: ' +
                e.getTypeName() + ' line=' + e.getLineNumber() + ' message=' + e.getMessage()
                );
        }
        
        return response;
    }
    
    @AuraEnabled
    public static PaymentResponse createOrder(PaymentRequest request) {
        PaymentResponse response = new PaymentResponse();
        try {
            Savepoint pendingWorkSavepoint = Database.setSavepoint();
            validateCreateRequest(request);
            
            Quickbridge_Config__mdt config = getConfig();
            String availabilityMessage = getAvailabilityMessage(config);
            if (availabilityMessage != null) {
                throw new AuraHandledException(availabilityMessage);
            }
            if (String.isBlank(config.PayPal_ClientId__c)) {
                throw new AuraHandledException('PayPal client configuration is incomplete.');
            }

            IntegrationUsageService.assertCanConsumeTask('PayPal', 1);

            String baseEndpoint = getBaseEndpoint(config.PayPal_UseSandbox__c);
            Database.rollback(pendingWorkSavepoint);
            Database.releaseSavepoint(pendingWorkSavepoint);
            String accessToken = fetchAccessToken(baseEndpoint);
            String requestBody = buildCreateOrderPayload(request);
            
            HttpRequest httpRequest = new HttpRequest();
            httpRequest.setEndpoint(baseEndpoint + '/v2/checkout/orders');
            httpRequest.setMethod('POST');
            httpRequest.setHeader('Authorization', 'Bearer ' + accessToken);
            httpRequest.setHeader('Content-Type', 'application/json');
            httpRequest.setHeader('Prefer', 'return=representation');
            httpRequest.setTimeout(20000);
            httpRequest.setBody(requestBody);
            
            Http http = new Http();
            HttpResponse httpResponse = http.send(httpRequest);
            String responseBody = sanitizeJsonBody(httpResponse.getBody());
            
            if (String.isBlank(responseBody) || (!responseBody.startsWith('{') && !responseBody.startsWith('['))) {
                response.success = false;
                response.message = 'PayPal returned an invalid response while creating the order.';
                logPayPalPaymentCalloutFailure('PayPalPaymentService.createOrder', response.message, httpResponse == null ? null : httpResponse.getStatusCode(), request == null ? null : request.orderId);
                return response;
            }
            
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            if (httpResponse.getStatusCode() < 200 || httpResponse.getStatusCode() >= 300) {
                response.success = false;
                response.message = extractPayPalError(parsed);
                if (String.isBlank(response.message)) {
                    response.message = 'PayPal order creation failed with HTTP ' + httpResponse.getStatusCode() + '.';
                }
                logPayPalPaymentCalloutFailure('PayPalPaymentService.createOrder', response.message, httpResponse.getStatusCode(), request == null ? null : request.orderId);
                return response;
            }
            
            response.paypalOrderId = parsed.containsKey('id') ? String.valueOf(parsed.get('id')) : null;
            response.status = parsed.containsKey('status') ? String.valueOf(parsed.get('status')) : null;
            response.approveLink = findPayPalLink(parsed, 'approve');
            response.transId = response.paypalOrderId;
            
            if (!String.isBlank(response.paypalOrderId)) {
                response.success = true;
                response.resultCode = 'Ok';
                response.message = 'PayPal order created successfully.';
                IntegrationUsageService.recordSuccessfulPaymentTask('PayPal');
                return response;
            }
            
            response.success = false;
            response.message = 'PayPal order creation did not return an order id.';
            logPayPalPaymentCalloutFailure('PayPalPaymentService.createOrder', response.message, httpResponse == null ? null : httpResponse.getStatusCode(), request == null ? null : request.orderId);
        } catch (AuraHandledException e) {
            response.success = false;
            response.message = e.getMessage();
        } catch (Exception e) {
            response.success = false;
            response.message = e.getTypeName() + ': ' + e.getMessage();
            ErrorLogUtility.logPaymentError('PayPal', 'PayPalPaymentService.createOrder', response.message, request == null ? null : request.orderId);
            System.debug(LoggingLevel.ERROR,
            'PayPalPaymentService.createOrder exception: ' +
                e.getTypeName() + ' line=' + e.getLineNumber() + ' message=' + e.getMessage()
                );
        }
        
        return response;
    }
    
    @AuraEnabled
    public static PaymentResponse captureOrder(CaptureRequest request) {
        PaymentResponse response = new PaymentResponse();
        try {
            Savepoint pendingWorkSavepoint = Database.setSavepoint();
            validateCaptureRequest(request);
            
            Quickbridge_Config__mdt config = getConfig();
            String availabilityMessage = getAvailabilityMessage(config);
            if (availabilityMessage != null) {
                throw new AuraHandledException(availabilityMessage);
            }

            IntegrationUsageService.assertCanConsumeTask('PayPal', 1);

            String baseEndpoint = getBaseEndpoint(config.PayPal_UseSandbox__c);
            Database.rollback(pendingWorkSavepoint);
            Database.releaseSavepoint(pendingWorkSavepoint);
            String accessToken = fetchAccessToken(baseEndpoint);

            HttpRequest httpRequest = new HttpRequest();
            httpRequest.setEndpoint(baseEndpoint + '/v2/checkout/orders/' + EncodingUtil.urlEncode(request.paypalOrderId, 'UTF-8') + '/capture');
            httpRequest.setMethod('POST');
            httpRequest.setHeader('Authorization', 'Bearer ' + accessToken);
            httpRequest.setHeader('Content-Type', 'application/json');
            httpRequest.setHeader('Prefer', 'return=representation');
            httpRequest.setTimeout(20000);
            httpRequest.setBody('{}');
            
            Http http = new Http();
            HttpResponse httpResponse = http.send(httpRequest);
            String responseBody = sanitizeJsonBody(httpResponse.getBody());
            
            if (String.isBlank(responseBody) || (!responseBody.startsWith('{') && !responseBody.startsWith('['))) {
                response.success = false;
                response.message = 'PayPal returned an invalid response while capturing the order.';
                logPayPalPaymentCalloutFailure('PayPalPaymentService.captureOrder', response.message, httpResponse == null ? null : httpResponse.getStatusCode(), request == null ? null : request.orderId);
                return response;
            }
            
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            if (httpResponse.getStatusCode() < 200 || httpResponse.getStatusCode() >= 300) {
                response.success = false;
                response.message = extractPayPalError(parsed);
                if (String.isBlank(response.message)) {
                    response.message = 'PayPal capture failed with HTTP ' + httpResponse.getStatusCode() + '.';
                }
                logPayPalPaymentCalloutFailure('PayPalPaymentService.captureOrder', response.message, httpResponse.getStatusCode(), request == null ? null : request.orderId);
                return response;
            }
            
            response.paypalOrderId = parsed.containsKey('id') ? String.valueOf(parsed.get('id')) : request.paypalOrderId;
            response.status = parsed.containsKey('status') ? String.valueOf(parsed.get('status')) : null;
            response.transId = extractCaptureId(parsed);
            response.authCode = response.paypalOrderId;
            
            if (response.status == 'COMPLETED' && !String.isBlank(response.transId)) {
                response.success = true;
                response.resultCode = 'Ok';
                response.message = 'Transaction Successful';
                IntegrationUsageService.recordSuccessfulPaymentTask('PayPal');

                // --- Invoice Creation ---
                try {
                    Order ord = [SELECT TotalAmount, AccountId FROM Order WHERE Id = :request.orderId LIMIT 1];
                    
                    Map<String, Object> invoiceData = new Map<String, Object>();
                    invoiceData.put('Amount__c', ord.TotalAmount);
                    invoiceData.put('Order__c', request.orderId);
                    invoiceData.put('Related_Account__c', ord.AccountId);
                    invoiceData.put('Reference_number__c', response.transId);
                    
                    QuickBridgeRecordEngine.processIncomingInvoice(invoiceData);
                } catch(Exception ex) {
                    System.debug('Invoice creation failed: ' + ex.getMessage());
                    ErrorLogUtility.logException('PayPal', 'PayPalPaymentService.captureOrder.invoiceCreation', ex, 'Order', parseId(request.orderId));
                }
                // ------

                if (String.isNotBlank(request.orderId)) {
                    try {
                        update new Order(Id = request.orderId, Payment_Gateway__c = 'PayPal');
                    } catch(Exception ex) {
                        System.debug('Gateway update failed: ' + ex.getMessage());
                        ErrorLogUtility.logDmlFailure(
                            'PayPal',
                            'PayPalPaymentService.captureOrder.updateOrderGateway',
                            'update',
                            'Order',
                            parseId(request.orderId),
                            ex.getTypeName() + ': ' + ex.getMessage(),
                            'Order',
                            parseId(request.orderId)
                        );
                    }
                }
                
                return response;
            }
            
            response.success = false;
            response.message = extractPayPalError(parsed);
            if (String.isBlank(response.message)) {
                response.message = 'PayPal capture status: ' + response.status;
            }
            logPayPalPaymentCalloutFailure('PayPalPaymentService.captureOrder', response.message, httpResponse == null ? null : httpResponse.getStatusCode(), request == null ? null : request.orderId);
        } catch (AuraHandledException e) {
            response.success = false;
            response.message = e.getMessage();
        } catch (Exception e) {
            response.success = false;
            response.message = e.getTypeName() + ': ' + e.getMessage();
            ErrorLogUtility.logPaymentError('PayPal', 'PayPalPaymentService.captureOrder', response.message, request == null ? null : request.orderId);
            System.debug(LoggingLevel.ERROR,
            'PayPalPaymentService.captureOrder exception: ' +
                e.getTypeName() + ' line=' + e.getLineNumber() + ' message=' + e.getMessage()
                );
        }
        
        return response;
    }
    
    private static Quickbridge_Config__mdt getConfig() {
        Quickbridge_Config__mdt config;
        try {
            config = Quickbridge_Config__mdt.getInstance('PayPal');
        } catch(Exception e) {
            config = null;
        }
        
        // if (Test.isRunningTest()) {
        //     Quickbridge_Config__mdt testConfig = new Quickbridge_Config__mdt();
        //     testConfig.PayPal_Active__c = config == null || config.PayPal_Active__c == null ? true : config.PayPal_Active__c;
        //     testConfig.PayPal_StartDate__c = config == null ? null : config.PayPal_StartDate__c;
        //     testConfig.PayPal_EndDate__c = config == null ? null : config.PayPal_EndDate__c;
        //     testConfig.PayPal_ClientId__c = config == null || String.isBlank(config.PayPal_ClientId__c)
        //         ? 'paypal-client-id-test'
        //         : config.PayPal_ClientId__c;
        //     testConfig.PayPal_UseSandbox__c = config == null || config.PayPal_UseSandbox__c == null ? true : config.PayPal_UseSandbox__c;
        //     return testConfig;
        // }
        
        if (Test.isRunningTest()) {
            Quickbridge_Config__mdt testConfig = new Quickbridge_Config__mdt();
            testConfig.PayPal_Active__c = true;
            testConfig.PayPal_StartDate__c = null;
            testConfig.PayPal_EndDate__c = null;
            testConfig.PayPal_ClientId__c = 'paypal-client-id-test';
            testConfig.PayPal_UseSandbox__c = true;
            return testConfig;
        }

        if (config == null) {
            throw new AuraHandledException('PayPal configuration record was not found.');
        }
        return config;
    }
    
    private static void validateCreateRequest(PaymentRequest request) {
        if (request == null) {
            throw new AuraHandledException('Missing payment request.');
        }
        if (!isInternalUserContext()) {
            throw new AuraHandledException('This payment action is only available to authenticated internal users.');
        }
        if (request.amount == null || request.amount <= 0) {
            throw new AuraHandledException('Payment amount must be greater than zero.');
        }
        if (String.isBlank(request.currencyCode)) {
            request.currencyCode = 'USD';
        } else {
            request.currencyCode = request.currencyCode.toUpperCase();
        }
    }
    
    private static void validateCaptureRequest(CaptureRequest request) {
        if (request == null) {
            throw new AuraHandledException('Missing capture request.');
        }
        if (!isInternalUserContext()) {
            throw new AuraHandledException('This payment action is only available to authenticated internal users.');
        }
        if (String.isBlank(request.paypalOrderId)) {
            throw new AuraHandledException('PayPal order id is required.');
        }
    }
    
    private static Boolean isInternalUserContext() {
        return Network.getNetworkId() == null
            && UserInfo.getUserType() != 'Guest';
    }
    
    private static String fetchAccessToken(String baseEndpoint) {
        if (Test.isRunningTest() && !String.isBlank(testAccessTokenOverride)) {
            return testAccessTokenOverride;
        }
        
        String credentials = PAYPAL_CLIENT_ID_MERGE_FIELD + ':' + PAYPAL_CLIENT_SECRET_MERGE_FIELD;
        String authorizationHeader = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(credentials));
        
        HttpRequest tokenRequest = new HttpRequest();
        tokenRequest.setEndpoint(baseEndpoint + '/v1/oauth2/token');
        tokenRequest.setMethod('POST');
        tokenRequest.setHeader('Authorization', authorizationHeader);
        tokenRequest.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        tokenRequest.setTimeout(20000);
        tokenRequest.setBody('grant_type=client_credentials');
        
        Http http = new Http();
        HttpResponse tokenResponse = http.send(tokenRequest);
        String responseBody = sanitizeJsonBody(tokenResponse.getBody());
        
        if (String.isBlank(responseBody) || (!responseBody.startsWith('{') && !responseBody.startsWith('['))) {
            throw new AuraHandledException('PayPal returned an invalid OAuth response.');
        }
        
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        if (tokenResponse.getStatusCode() < 200 || tokenResponse.getStatusCode() >= 300) {
            String errorMessage = extractPayPalError(parsed);
            if (String.isBlank(errorMessage)) {
                errorMessage = 'PayPal OAuth token request failed with HTTP ' + tokenResponse.getStatusCode() + '.';
            }
            throw new AuraHandledException(errorMessage);
        }
        
        String accessToken = parsed.containsKey('access_token') ? String.valueOf(parsed.get('access_token')) : null;
        if (String.isBlank(accessToken)) {
            throw new AuraHandledException('PayPal OAuth token response did not include access_token.');
        }
        
        return accessToken;
    }
    
    private static String getBaseEndpoint(Boolean useSandbox) {
        if (Test.isRunningTest() && !String.isBlank(testBaseEndpointOverride)) {
            return testBaseEndpointOverride;
        }
        
        return useSandbox ? PAYPAL_SANDBOX_API_ENDPOINT : PAYPAL_PRODUCTION_API_ENDPOINT;
    }
    
    private static String buildCreateOrderPayload(PaymentRequest request) {
        JSONGenerator generator = JSON.createGenerator(false);
        generator.writeStartObject();
        generator.writeStringField('intent', 'CAPTURE');
        generator.writeFieldName('purchase_units');
        generator.writeStartArray();
        generator.writeStartObject();
        if (!String.isBlank(request.orderId)) {
            generator.writeStringField('reference_id', request.orderId);
            generator.writeStringField('custom_id', request.orderId);
            generator.writeStringField('invoice_id', request.orderId);
        }
        generator.writeStringField('description', 'Inventorymagic payment');
        generator.writeFieldName('amount');
        generator.writeStartObject();
        generator.writeStringField('currency_code', request.currencyCode);
        generator.writeStringField('value', String.valueOf(request.amount.setScale(2)));
        generator.writeEndObject();
        generator.writeEndObject();
        generator.writeEndArray();
        generator.writeEndObject();
        
        return generator.getAsString();
    }
    
    private static String findPayPalLink(Map<String, Object> parsed, String relation) {
        if (parsed == null || String.isBlank(relation) || !parsed.containsKey('links')) {
            return null;
        }
        
        Object linksObject = parsed.get('links');
        if (!(linksObject instanceof List<Object>)) {
            return null;
        }
        
        for (Object linkObject : (List<Object>) linksObject) {
            if (!(linkObject instanceof Map<String, Object>)) {
                continue;
            }
            
            Map<String, Object> linkMap = (Map<String, Object>) linkObject;
            if (String.valueOf(linkMap.get('rel')) == relation) {
                return String.valueOf(linkMap.get('href'));
            }
        }
        
        return null;
    }
    
    private static String extractCaptureId(Map<String, Object> parsed) {
        if (parsed == null) {
            return null;
        }
        
        if (!parsed.containsKey('purchase_units')) {
            return null;
        }
        
        Object purchaseUnitsObject = parsed.get('purchase_units');
        if (!(purchaseUnitsObject instanceof List<Object>) || ((List<Object>) purchaseUnitsObject).isEmpty()) {
            return null;
        }
        
        Map<String, Object> firstPurchaseUnit = (Map<String, Object>) ((List<Object>) purchaseUnitsObject)[0];
        Map<String, Object> payments = firstPurchaseUnit.containsKey('payments')
            ? (Map<String, Object>) firstPurchaseUnit.get('payments')
            : null;
        if (payments == null || !payments.containsKey('captures')) {
            return null;
        }
        
        Object capturesObject = payments.get('captures');
        if (!(capturesObject instanceof List<Object>) || ((List<Object>) capturesObject).isEmpty()) {
            return null;
        }
        
        Map<String, Object> firstCapture = (Map<String, Object>) ((List<Object>) capturesObject)[0];
        return firstCapture == null ? null : String.valueOf(firstCapture.get('id'));
    }
    
    private static String extractPayPalError(Map<String, Object> parsed) {
        if (parsed == null) {
            return null;
        }
        
        if (parsed.containsKey('message') && !String.isBlank(String.valueOf(parsed.get('message')))) {
            return String.valueOf(parsed.get('message'));
        }
        
        if (parsed.containsKey('details')) {
            Object detailsObject = parsed.get('details');
            if (detailsObject instanceof List<Object> && !((List<Object>) detailsObject).isEmpty()) {
                Map<String, Object> firstDetail = (Map<String, Object>) ((List<Object>) detailsObject)[0];
                if (firstDetail != null && firstDetail.containsKey('description')) {
                    return String.valueOf(firstDetail.get('description'));
                }
            }
        }
        
        if (parsed.containsKey('error_description') && !String.isBlank(String.valueOf(parsed.get('error_description')))) {
            return String.valueOf(parsed.get('error_description'));
        }
        
        if (parsed.containsKey('name') && !String.isBlank(String.valueOf(parsed.get('name')))) {
            return String.valueOf(parsed.get('name'));
        }
        
        return null;
    }
    
    private static String sanitizeJsonBody(String body) {
        if (body == null) {
            return null;
        }
        return body.trim().replaceFirst('^\\uFEFF', '');
    }
    
    private static String buildPayPalJsUrl(String clientId) {
        if (String.isBlank(clientId)) {
            return null;
        }
        
        return PAYPAL_JS_SDK_BASE_URL
            + '?client-id=' + EncodingUtil.urlEncode(clientId, 'UTF-8')
            + '&currency=USD&intent=capture&components=buttons';
    }
    
    private static Boolean isConfigActive(Boolean activeFlag) {
        return activeFlag == null ? true : activeFlag;
    }
    
    private static String getAvailabilityMessage(Quickbridge_Config__mdt config) {
        if (config == null) {
            return 'PayPal configuration record was not found.';
        }
        
        if (!isConfigActive(config.PayPal_Active__c)) {
            return 'PayPal is currently inactive.';
        }
        
        Date today = Date.today();
        if (config.PayPal_StartDate__c != null && config.PayPal_StartDate__c > today) {
            return 'PayPal is not active yet.';
        }
        if (config.PayPal_EndDate__c != null && config.PayPal_EndDate__c < today) {
            return 'PayPal contract has expired.';
        }
        
        return null;
    }

    private static void logPayPalPaymentCalloutFailure(String classMethodName, String message, Integer statusCode, String orderId) {
        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = 'PayPal';
        context.classMethodName = classMethodName;
        context.errorMessage = message;
        context.httpStatusCode = statusCode;
        context.errorCategory = 'Callout Failure';
        context.sourceObjectApiName = 'Order';
        context.sourceRecordIdText = orderId;
        context.sourceRecordId = parseId(orderId);
        ErrorLogUtility.logError(context);
    }

    private static Id parseId(String rawId) {
        if (String.isBlank(rawId)) return null;
        try {
            return (Id) rawId;
        } catch (Exception e) {
            return null;
        }
    }
}