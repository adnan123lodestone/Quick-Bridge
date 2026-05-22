public with sharing class StripePaymentService {

    private static final String STRIPE_API_ENDPOINT = 'callout:Stripe_API/v1/payment_intents';
    private static final String STRIPE_CUSTOMERS_ENDPOINT = 'callout:Stripe_API/v1/customers';
    private static final String STRIPE_INVOICE_ITEMS_ENDPOINT = 'callout:Stripe_API/v1/invoiceitems';
    private static final String STRIPE_INVOICES_ENDPOINT = 'callout:Stripe_API/v1/invoices';
    private static final String STRIPE_PAYMENT_METHODS_ENDPOINT = 'callout:Stripe_API/v1/payment_methods';
    private static final String STRIPE_SECRET_KEY_MERGE_FIELD = '{!$Credential.Stripe_Credentials.SecretKey}';
    private static final String STRIPE_JS_URL = 'https://js.stripe.com/v3/';
    // private static final String STRIPE_API_ENDPOINT = 'callout:QuickBridgeTLG__Stripe_API/v1/payment_intents';
    // private static final String STRIPE_CUSTOMERS_ENDPOINT = 'callout:QuickBridgeTLG__Stripe_API/v1/customers';
    // private static final String STRIPE_INVOICE_ITEMS_ENDPOINT = 'callout:QuickBridgeTLG__Stripe_API/v1/invoiceitems';
    // private static final String STRIPE_INVOICES_ENDPOINT = 'callout:QuickBridgeTLG__Stripe_API/v1/invoices';
    // private static final String STRIPE_PAYMENT_METHODS_ENDPOINT = 'callout:QuickBridgeTLG__Stripe_API/v1/payment_methods';
    // private static final String STRIPE_SECRET_KEY_MERGE_FIELD = '{!$Credential.QuickBridgeTLG__Stripe_Credentials.SecretKey}';
    // private static final String STRIPE_JS_URL = 'https://js.stripe.com/v3/';

    public class ClientConfigResponse {
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Boolean configured { get; set; }
        @AuraEnabled public String publishableKey { get; set; }
        @AuraEnabled public Boolean useSandbox { get; set; }
        @AuraEnabled public String stripeJsUrl { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    public class PaymentRequest {
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Boolean allowPlatformSession { get; set; }
        @AuraEnabled public String orderId { get; set; }
        @AuraEnabled public String sessionToken { get; set; }
        @AuraEnabled public String paymentMethodId { get; set; }
        @AuraEnabled public String fullName { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String zip { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String currencyCode { get; set; }
    }

    public class PaymentResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String transId { get; set; }
        @AuraEnabled public String resultCode { get; set; }
        @AuraEnabled public String authCode { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String clientSecret { get; set; }
    }

    public class InvoiceDeliveryResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String hostedInvoiceUrl { get; set; }
        @AuraEnabled public String stripeInvoiceId { get; set; }
        @AuraEnabled public String stripeCustomerId { get; set; }
    }

    private class OrderAccountContext {
        private Id orderId;
        private Id accountId;
        private String accountName;
        private String stripeCustomerId;
    }

    public class InvoiceAccountContext {
        public Id invoiceId;
        public String invoiceNumber;
        public String referenceNumber;
        public Id orderId;
        public Date invoiceDate;
        public Date dueDate;
        public Decimal amount;
        public String invoiceEmail;
        public Id accountId;
        public String accountName;
        public String stripeCustomerId;
        public Boolean supportsHostedInvoiceUrlField;
    }

    private class StripeCustomerResolution {
        private String customerId;
        private Id accountId;
        private Boolean shouldPersist;
    }

    @AuraEnabled(cacheable=true)
    public static ClientConfigResponse getClientConfig() {
        ClientConfigResponse response = new ClientConfigResponse();
        try {
            Quickbridge_Config__mdt config = getConfig();

            String availabilityMessage = getAvailabilityMessage(config);
            response.active = availabilityMessage == null;
            response.publishableKey = config.Stripe_Publishable_Key__c;
            response.useSandbox = config.Stripe_Use_Sandbox__c;
            response.stripeJsUrl = STRIPE_JS_URL;

            List<String> missingItems = new List<String>();
            if (String.isBlank(config.Stripe_Publishable_Key__c)) {
                missingItems.add('Publishable Key');
            }

            response.configured = response.active && missingItems.isEmpty();
            if (availabilityMessage != null) {
                response.message = availabilityMessage;
            } else if (!missingItems.isEmpty()) {
                response.message = 'Stripe is not fully configured. Missing: ' + String.join(missingItems, ', ');
            } else {
                response.message = 'Stripe client configuration loaded.';
            }
        } catch (Exception e) {
            response.active = false;
            response.configured = false;
            response.message = 'Unable to load Stripe client configuration.';
        }

        return response;
    }

    @AuraEnabled
    public static PaymentResponse processPayment(PaymentRequest request) {
        PaymentResponse response = new PaymentResponse();
        try {
            Savepoint pendingWorkSavepoint = Database.setSavepoint();
            validateRequest(request);

            Quickbridge_Config__mdt config = getConfig();
            String availabilityMessage = getAvailabilityMessage(config);
            if (availabilityMessage != null) {
                throw new AuraHandledException(availabilityMessage);
            }
            if (String.isBlank(config.Stripe_Publishable_Key__c)) {
                throw new AuraHandledException('Stripe client configuration is incomplete.');
            }

            IntegrationUsageService.assertCanConsumeTask('Stripe', 1);

            OrderAccountContext orderAccountContext = getOrderAccountContext(request.orderId);
            String authorizationHeader = 'Bearer ' + STRIPE_SECRET_KEY_MERGE_FIELD;
            Database.rollback(pendingWorkSavepoint);
            Database.releaseSavepoint(pendingWorkSavepoint);

            StripeCustomerResolution customerResolution = resolveStripeCustomer(orderAccountContext, request, authorizationHeader);
            attachPaymentMethodToCustomer(customerResolution == null ? null : customerResolution.customerId, request.paymentMethodId, authorizationHeader);
            String requestBody = buildPaymentIntentBody(request, customerResolution == null ? null : customerResolution.customerId);

            HttpResponse httpResponse = sendStripePost(STRIPE_API_ENDPOINT, requestBody, authorizationHeader);
            String responseBody = sanitizeJsonBody(httpResponse.getBody());

            if (String.isBlank(responseBody) || (!responseBody.startsWith('{') && !responseBody.startsWith('['))) {
                        persistStripeCustomerId(customerResolution);
                        response.success = false;
                        response.message = 'Stripe returned an invalid response.';
                        logStripePaymentCalloutFailure('StripePaymentService.processPayment', response.message, httpResponse == null ? null : httpResponse.getStatusCode(), request);
                        return response;
                    }

                    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                    persistStripeCustomerId(customerResolution);
                    if (httpResponse.getStatusCode() < 200 || httpResponse.getStatusCode() >= 300) {
                        response.success = false;
                        response.message = extractStripeError(parsed);
                        if (String.isBlank(response.message)) {
                            response.message = 'Stripe transaction call failed with HTTP ' + httpResponse.getStatusCode() + '.';
                        }
                        logStripePaymentCalloutFailure('StripePaymentService.processPayment', response.message, httpResponse.getStatusCode(), request);
                        return response;
                    }

                    if (parsed.containsKey('error')) {
                        response.success = false;
                        response.message = extractStripeError(parsed);
                        if (String.isBlank(response.message)) {
                            response.message = 'Stripe payment was unsuccessful.';
                        }
                        try {
                            ErrorLogUtility.logPaymentError('Stripe', 'StripePaymentService.processPayment', response.message, request.orderId);
                        } catch(Exception e){}
                        return response;
                    }

                    response.transId = String.valueOf(parsed.get('id'));
                    response.clientSecret = parsed.containsKey('client_secret') ? String.valueOf(parsed.get('client_secret')) : null;
                    response.status = parsed.containsKey('status') ? String.valueOf(parsed.get('status')) : null;
                    response.authCode = parsed.containsKey('latest_charge') ? String.valueOf(parsed.get('latest_charge')) : null;

                    if (response.status == 'succeeded' && !String.isBlank(response.transId)) {
                        response.success = true;
                        response.resultCode = 'Ok';
                        response.message = 'Transaction Successful';
                        IntegrationUsageService.recordSuccessfulPaymentTask('Stripe');

                        try {
                            Map<String, Object> invoiceData = new Map<String, Object>();
                            invoiceData.put('Amount__c', request.amount);
                            invoiceData.put('Order__c', request.orderId);
                            invoiceData.put('Reference_number__c', response.transId);

                            if (orderAccountContext != null) {
                                invoiceData.put('Related_Account__c', orderAccountContext.accountId);
                            }
                            QuickBridgeRecordEngine.processIncomingInvoice(invoiceData);
                        } catch(Exception ex) {
                            ErrorLogUtility.logException('Stripe', 'StripePaymentService.processPayment.invoiceCreation', ex, 'Order', parseId(request.orderId));
                        }

                        if (String.isNotBlank(request.orderId)) {
                            try {
                                update new Order(Id = request.orderId, Payment_Gateway__c = 'Stripe');
                            } catch(Exception ex) {
                                ErrorLogUtility.logDmlFailure(
                                    'Stripe',
                                    'StripePaymentService.processPayment.updateOrderGateway',
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
                    response.message = extractStripeError(parsed);
                    if (String.isBlank(response.message)) {
                        if (response.status == 'requires_action' || response.status == 'requires_confirmation') {
                            response.message = 'Stripe payment requires additional authentication.';
                        } else if (response.status == 'processing') {
                            response.message = 'Stripe is still processing the payment.';
                        } else {
                            response.message = 'Stripe payment status: ' + response.status;
                        }
                    }
                    logStripePaymentCalloutFailure('StripePaymentService.processPayment', response.message, httpResponse == null ? null : httpResponse.getStatusCode(), request);
                } catch (AuraHandledException e) {
                    response.success = false;
                    response.message = e.getMessage();
                } catch (Exception e) {
                    response.success = false;
                    response.message = e.getTypeName() + ': ' + e.getMessage();
                    try {
                        ErrorLogUtility.logPaymentError('Stripe', 'StripePaymentService.processPayment', response.message, request == null ? null : request.orderId);
                    } catch(Exception ex){}
                }

                return response;
            }

            @AuraEnabled
            public static InvoiceDeliveryResponse sendInvoiceToCustomer(Id invoiceId) {
                InvoiceDeliveryResponse response = new InvoiceDeliveryResponse();

                try {
                    Savepoint pendingWorkSavepoint = Database.setSavepoint();

                    if (!isInternalUserContext()) {
                        throw new AuraHandledException('This invoice action is only available to authenticated internal users.');
                    }
                    if (invoiceId == null) {
                        throw new AuraHandledException('Invoice Id is required.');
                    }

                    Quickbridge_Config__mdt config = getConfig();
                    String availabilityMessage = getAvailabilityMessage(config);
                    if (availabilityMessage != null) {
                        throw new AuraHandledException(availabilityMessage);
                    }

                    InvoiceAccountContext invoiceContext = getInvoiceAccountContext(invoiceId);
                    validateInvoiceContext(invoiceContext);

                    String authorizationHeader = 'Bearer ' + STRIPE_SECRET_KEY_MERGE_FIELD;
                    Database.rollback(pendingWorkSavepoint);
                    Database.releaseSavepoint(pendingWorkSavepoint);

                    PaymentRequest customerRequest = new PaymentRequest();
                    customerRequest.fullName = invoiceContext.accountName;
                    customerRequest.orderId = invoiceContext.orderId == null ? null : String.valueOf(invoiceContext.orderId);

                    OrderAccountContext orderAccountContext = new OrderAccountContext();
                    orderAccountContext.orderId = invoiceContext.orderId;
                    orderAccountContext.accountId = invoiceContext.accountId;
                    orderAccountContext.accountName = invoiceContext.accountName;
                    orderAccountContext.stripeCustomerId = invoiceContext.stripeCustomerId;

                    StripeCustomerResolution customerResolution = resolveStripeCustomer(
                        orderAccountContext,
                    customerRequest,
                    authorizationHeader
                        );

                    HttpResponse stripeInvoiceResponse = sendStripePost(
                        STRIPE_INVOICES_ENDPOINT,
                    buildStripeInvoiceBody(invoiceContext, customerResolution.customerId),
                    authorizationHeader
                        );
                    String stripeInvoiceBody = sanitizeJsonBody(stripeInvoiceResponse.getBody());
                    if (String.isBlank(stripeInvoiceBody) || (!stripeInvoiceBody.startsWith('{') && !stripeInvoiceBody.startsWith('['))) {
                                throw new AuraHandledException('Stripe returned an invalid response when creating the invoice.');
                            }

                            Map<String, Object> createdInvoice = (Map<String, Object>) JSON.deserializeUntyped(stripeInvoiceBody);
                            if (stripeInvoiceResponse.getStatusCode() < 200 || stripeInvoiceResponse.getStatusCode() >= 300 || createdInvoice.containsKey('error')) {
                                String message = extractStripeError(createdInvoice);
                                if (String.isBlank(message)) {
                                    message = 'Stripe invoice creation failed with HTTP ' + stripeInvoiceResponse.getStatusCode() + '.';
                                }
                                throw new AuraHandledException(message);
                            }

                            String stripeInvoiceId = createdInvoice.containsKey('id') ? String.valueOf(createdInvoice.get('id')) : null;
                            if (String.isBlank(stripeInvoiceId)) {
                                throw new AuraHandledException('Stripe invoice creation returned no invoice id.');
                            }

                            HttpResponse invoiceItemResponse = sendStripePost(
                                STRIPE_INVOICE_ITEMS_ENDPOINT,
                            buildStripeInvoiceItemBody(invoiceContext, customerResolution.customerId, stripeInvoiceId),
                            authorizationHeader
                                );
                            validateStripeMutationResponse(
                                invoiceItemResponse,
                            'Stripe returned an invalid response when creating the invoice item.',
                            'Stripe invoice item creation failed with HTTP '
                                );

                            HttpResponse finalizeResponse = sendStripePost(
                                STRIPE_INVOICES_ENDPOINT + '/' + stripeInvoiceId + '/finalize',
                            '',
                            authorizationHeader
                                );
                            String finalizeBody = sanitizeJsonBody(finalizeResponse.getBody());
                            if (String.isBlank(finalizeBody) || (!finalizeBody.startsWith('{') && !finalizeBody.startsWith('['))) {
                                        throw new AuraHandledException('Stripe returned an invalid response when finalizing the invoice.');
                                    }

                                    Map<String, Object> finalizedInvoice = (Map<String, Object>) JSON.deserializeUntyped(finalizeBody);
                                    if (finalizeResponse.getStatusCode() < 200 || finalizeResponse.getStatusCode() >= 300 || finalizedInvoice.containsKey('error')) {
                                        String message = extractStripeError(finalizedInvoice);
                                        if (String.isBlank(message)) {
                                            message = 'Stripe invoice finalization failed with HTTP ' + finalizeResponse.getStatusCode() + '.';
                                        }
                                        throw new AuraHandledException(message);
                                    }

                                    String hostedInvoiceUrl = finalizedInvoice.containsKey('hosted_invoice_url')
                                        ? String.valueOf(finalizedInvoice.get('hosted_invoice_url'))
                                        : null;
                                    if (String.isBlank(hostedInvoiceUrl)) {
                                        throw new AuraHandledException('Stripe invoice was created but no hosted invoice URL was returned.');
                                    }

                                    persistStripeCustomerId(customerResolution);
                                    persistStripeInvoiceLink(invoiceContext, hostedInvoiceUrl);
                                    sendStripeInvoiceEmail(invoiceContext, hostedInvoiceUrl);

                                    response.success = true;
                                    response.message = 'Stripe invoice created and emailed to ' + invoiceContext.invoiceEmail + '.';
                                    response.hostedInvoiceUrl = hostedInvoiceUrl;
                                    response.stripeInvoiceId = stripeInvoiceId;
                                    response.stripeCustomerId = customerResolution.customerId;
                                } catch (Exception e) {
                                    response.success = false;
                                    response.message = e.getTypeName() + ': ' + e.getMessage();
                                    ErrorLogUtility.logException('Stripe', 'StripePaymentService.sendInvoiceToCustomer', e, 'Invoice__c', invoiceId);
                                }

                                return response;
                            }

                            private static Quickbridge_Config__mdt getConfig() {
                                Quickbridge_Config__mdt config;
                                try {
                                    config = Quickbridge_Config__mdt.getInstance('Stripe');
                                } catch(Exception e) {
                                    config = null;
                                }

                                if (Test.isRunningTest()) {
                                    Quickbridge_Config__mdt testConfig = new Quickbridge_Config__mdt();
                                    testConfig.Stripe_Active__c = true;
                                    testConfig.Stripe_Publishable_Key__c = 'pk_test_123';
                                    testConfig.Stripe_Use_Sandbox__c = true;
                                    return testConfig;
                                }

                                if (config == null) throw new AuraHandledException('Stripe configuration record was not found.');
                                return config;
                            }

                            private static void validateRequest(PaymentRequest request) {
                                if (request == null) throw new AuraHandledException('Missing payment request.');
                                if (!isInternalUserContext()) throw new AuraHandledException('This payment action is only available to authenticated internal users.');
                                if (request.amount == null || request.amount <= 0) throw new AuraHandledException('Payment amount must be greater than zero.');
                                if (String.isBlank(request.paymentMethodId)) throw new AuraHandledException('Stripe payment method is missing.');
                                if (String.isBlank(request.currencyCode)) {
                                    request.currencyCode = 'usd';
                                } else {
                                    request.currencyCode = request.currencyCode.toLowerCase();
                                }
                            }

                            private static Boolean isInternalUserContext() {
                                return Network.getNetworkId() == null && UserInfo.getUserType() != 'Guest';
                            }

                            private static OrderAccountContext getOrderAccountContext(String orderId) {
                                if (String.isBlank(orderId)) return null;

                                Order orderRecord = [SELECT Id, AccountId, Account.Name, Account.Stripe_Customer_Id__c FROM Order WHERE Id = :orderId LIMIT 1];

                                OrderAccountContext context = new OrderAccountContext();
                                context.orderId = orderRecord.Id;
                                context.accountId = orderRecord.AccountId;
                                context.accountName = orderRecord.Account == null ? null : orderRecord.Account.Name;
                                context.stripeCustomerId = orderRecord.Account == null ? null : orderRecord.Account.Stripe_Customer_Id__c;
                                return context;
                            }

                            public static InvoiceAccountContext getInvoiceAccountContext(Id invoiceId) {
                                Map<String, Schema.SObjectField> invoiceFields = Schema.SObjectType.Invoice__c.fields.getMap();
                                List<String> selectFields = new List<String>{
                                    'Id', 'Name', 'Related_Account__c', 'Related_Account__r.Name', 'Related_Account__r.Stripe_Customer_Id__c'
                                };

                                String amountField = resolveField(invoiceFields, 'Amount__c');
                                String amountDueField = resolveField(invoiceFields, 'Amount_Due_c__c');
                                String totalCostField = resolveField(invoiceFields, 'Total_cost__c');
                                String dueDateField = resolveField(invoiceFields, 'Due_Date__c');
                                String emailField = resolveField(invoiceFields, 'Email__c');
                                String invoiceDateField = resolveField(invoiceFields, 'Invoice_Date__c');
                                String orderField = resolveField(invoiceFields, 'Order__c');
                                String refNumberField = resolveField(invoiceFields, 'Reference_number__c');
                                String stripeLinkField = resolveField(invoiceFields, 'Stripe_Invoice_Link__c');

                                if (amountField != null) selectFields.add(amountField);
                                if (amountDueField != null) selectFields.add(amountDueField);
                                if (totalCostField != null) selectFields.add(totalCostField);
                                if (dueDateField != null) selectFields.add(dueDateField);
                                if (emailField != null) selectFields.add(emailField);
                                if (invoiceDateField != null) selectFields.add(invoiceDateField);
                                if (orderField != null) selectFields.add(orderField);
                                if (refNumberField != null) selectFields.add(refNumberField);
                                if (stripeLinkField != null) selectFields.add(stripeLinkField);

                                SObject invoiceRecord = Database.query(
                                    'SELECT ' + String.join(selectFields, ', ') +
                                    ' FROM Invoice__c WHERE Id = :invoiceId LIMIT 1'
                                    );

                                SObject accountRecord = invoiceRecord.getSObject('Related_Account__r');
                                InvoiceAccountContext context = new InvoiceAccountContext();
                                context.invoiceId = (Id) invoiceRecord.get('Id');
                                context.invoiceNumber = (String) invoiceRecord.get('Name');
                                context.referenceNumber = refNumberField != null ? (String) invoiceRecord.get(refNumberField) : null;
                                context.orderId = orderField != null ? (Id) invoiceRecord.get(orderField) : null;
                                context.invoiceDate = invoiceDateField != null ? (Date) invoiceRecord.get(invoiceDateField) : null;
                                context.dueDate = dueDateField != null ? (Date) invoiceRecord.get(dueDateField) : null;
                                context.invoiceEmail = emailField != null ? (String) invoiceRecord.get(emailField) : null;

                                context.amount = getInvoiceAmount(invoiceRecord, amountField, amountDueField, totalCostField);
                                context.accountId = (Id) invoiceRecord.get('Related_Account__c');
                                context.accountName = accountRecord == null ? null : (String) accountRecord.get('Name');
                                context.stripeCustomerId = accountRecord == null ? null : (String) accountRecord.get('Stripe_Customer_Id__c');
                                context.supportsHostedInvoiceUrlField = stripeLinkField != null;
                                return context;
                            }

                            private static String resolveField(Map<String, Schema.SObjectField> fieldMap, String fieldName) {
                                if (fieldMap.containsKey(fieldName.toLowerCase())) return fieldName.toLowerCase();
                                for (String key : fieldMap.keySet()) {
                                    if (key.endsWith('__' + fieldName.toLowerCase())) return key;
                                }
                                return null;
                            }

                            public static Decimal getInvoiceAmount(SObject invoiceRecord, String amountField, String amountDueField, String totalCostField) {
                                if (amountField != null && invoiceRecord.get(amountField) != null) return (Decimal) invoiceRecord.get(amountField);
                                if (amountDueField != null && invoiceRecord.get(amountDueField) != null) return (Decimal) invoiceRecord.get(amountDueField);
                                if (totalCostField != null && invoiceRecord.get(totalCostField) != null) return (Decimal) invoiceRecord.get(totalCostField);
                                return null;
                            }

                            private static void validateInvoiceContext(InvoiceAccountContext invoiceContext) {
                                if (invoiceContext == null) throw new AuraHandledException('Invoice details could not be loaded.');
                                if (invoiceContext.accountId == null) throw new AuraHandledException('The invoice must be linked to an account before it can be sent.');
                                if (String.isBlank(invoiceContext.invoiceEmail)) throw new AuraHandledException('The invoice does not have an email address.');
                                if (invoiceContext.amount == null || invoiceContext.amount <= 0) throw new AuraHandledException('The invoice amount must be greater than zero.');
                            }

                            private static StripeCustomerResolution resolveStripeCustomer(OrderAccountContext orderAccountContext, PaymentRequest request, String authorizationHeader) {
                                if (orderAccountContext == null || orderAccountContext.accountId == null) return null;

                                StripeCustomerResolution resolution = new StripeCustomerResolution();
                                resolution.accountId = orderAccountContext.accountId;

                                if (!String.isBlank(orderAccountContext.stripeCustomerId)) {
                                    resolution.customerId = orderAccountContext.stripeCustomerId;
                                    resolution.shouldPersist = false;
                                    return resolution;
                                }

                                HttpResponse customerResponse = sendStripePost(STRIPE_CUSTOMERS_ENDPOINT, buildCustomerBody(orderAccountContext, request), authorizationHeader);
                                String responseBody = sanitizeJsonBody(customerResponse.getBody());
                                if (String.isBlank(responseBody) || (!responseBody.startsWith('{') && !responseBody.startsWith('['))) {
                                            throw new AuraHandledException('Stripe returned an invalid response when creating the customer.');
                                        }

                                        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                                        if (customerResponse.getStatusCode() < 200 || customerResponse.getStatusCode() >= 300 || parsed.containsKey('error')) {
                                            String message = extractStripeError(parsed);
                                            throw new AuraHandledException(String.isBlank(message) ? 'Stripe customer creation failed with HTTP ' + customerResponse.getStatusCode() + '.' : message);
                                        }

                                        resolution.customerId = parsed.containsKey('id') ? String.valueOf(parsed.get('id')) : null;
                                        if (String.isBlank(resolution.customerId)) throw new AuraHandledException('Stripe customer creation returned no customer id.');

                                        resolution.shouldPersist = true;
                                        return resolution;
                                    }

                                    private static void persistStripeCustomerId(StripeCustomerResolution customerResolution) {
                                        if (customerResolution == null || !customerResolution.shouldPersist || customerResolution.accountId == null || String.isBlank(customerResolution.customerId)) return;
                                        try {
                                            update new Account(Id = customerResolution.accountId, Stripe_Customer_Id__c = customerResolution.customerId);
                                        } catch (Exception e) {
                                            ErrorLogUtility.logDmlFailure(
                                                'Stripe',
                                                'StripePaymentService.persistStripeCustomerId',
                                                'update',
                                                'Account',
                                                customerResolution.accountId,
                                                e.getTypeName() + ': ' + e.getMessage(),
                                                'Account',
                                                customerResolution.accountId
                                            );
                                        }
                                    }

                                    private static void persistStripeInvoiceLink(InvoiceAccountContext invoiceContext, String hostedInvoiceUrl) {
                                        if (invoiceContext == null || invoiceContext.invoiceId == null || !invoiceContext.supportsHostedInvoiceUrlField || String.isBlank(hostedInvoiceUrl)) return;
                                        try {
                                            Invoice__c invoiceUpdate = new Invoice__c(Id = invoiceContext.invoiceId);
                                            Map<String, Schema.SObjectField> invoiceFields = Schema.SObjectType.Invoice__c.fields.getMap();
                                            String linkField = resolveField(invoiceFields, 'Stripe_Invoice_Link__c');
                                            if(linkField != null) {
                                                invoiceUpdate.put(linkField, hostedInvoiceUrl);
                                                update invoiceUpdate;
                                            }
                                        } catch (Exception e) {
                                            ErrorLogUtility.logDmlFailure(
                                                'Stripe',
                                                'StripePaymentService.persistStripeInvoiceLink',
                                                'update',
                                                'Invoice__c',
                                                invoiceContext.invoiceId,
                                                e.getTypeName() + ': ' + e.getMessage(),
                                                'Invoice__c',
                                                invoiceContext.invoiceId
                                            );
                                        }
                                    }

                                    public static void sendStripeInvoiceEmail(InvoiceAccountContext invoiceContext, String hostedInvoiceUrl) {
                                        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                                        email.setToAddresses(new List<String>{ invoiceContext.invoiceEmail });
                                        email.setSaveAsActivity(false);
                                        email.setSubject('Invoice ' + invoiceContext.invoiceNumber + ' is ready for payment');
                                        email.setPlainTextBody(buildStripeInvoiceEmailBody(invoiceContext, hostedInvoiceUrl));

                                        if (!Test.isRunningTest()) {
                                            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email }, false);
                                        }
                                    }

                                    private static String buildStripeInvoiceEmailBody(InvoiceAccountContext invoiceContext, String hostedInvoiceUrl) {
                                        List<String> lines = new List<String>{
                                            'Hello ' + (String.isBlank(invoiceContext.accountName) ? 'Customer' : invoiceContext.accountName) + ',',
                                            '',
                                            'Your invoice ' + invoiceContext.invoiceNumber + ' is ready for payment.',
                                            'Amount: $' + (invoiceContext.amount != null ? String.valueOf(invoiceContext.amount.setScale(2)) : '0.00'),
                                            'Pay securely here: ' + hostedInvoiceUrl
                                        };
                                        if (invoiceContext.dueDate != null) lines.add('Due date: ' + String.valueOf(invoiceContext.dueDate));
                                        if (!String.isBlank(invoiceContext.referenceNumber)) lines.add('Reference number: ' + invoiceContext.referenceNumber);
                                        lines.add('');
                                        lines.add('Thank you.');
                                        return String.join(lines, '\n');
                                    }

                                    private static void attachPaymentMethodToCustomer(String stripeCustomerId, String paymentMethodId, String authorizationHeader) {
                                        if (String.isBlank(stripeCustomerId) || String.isBlank(paymentMethodId)) return;

                                        HttpResponse attachResponse = sendStripePost(STRIPE_PAYMENT_METHODS_ENDPOINT + '/' + paymentMethodId + '/attach', 'customer=' + EncodingUtil.urlEncode(stripeCustomerId, 'UTF-8'), authorizationHeader);
                                        validateStripeMutationResponse(attachResponse, 'Stripe returned an invalid response when attaching the payment method.', 'Stripe payment method attachment failed with HTTP ');

                                        HttpResponse updateCustomerResponse = sendStripePost(STRIPE_CUSTOMERS_ENDPOINT + '/' + stripeCustomerId, 'invoice_settings[default_payment_method]=' + EncodingUtil.urlEncode(paymentMethodId, 'UTF-8'), authorizationHeader);
                                        validateStripeMutationResponse(updateCustomerResponse, 'Stripe returned an invalid response when updating the customer.', 'Stripe customer update failed with HTTP ');
                                    }

                                    private static void validateStripeMutationResponse(HttpResponse response, String invalidBodyMessage, String httpErrorPrefix) {
                                        String responseBody = sanitizeJsonBody(response == null ? null : response.getBody());
                                        if (String.isBlank(responseBody) || (!responseBody.startsWith('{') && !responseBody.startsWith('['))) throw new AuraHandledException(invalidBodyMessage);

                                        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                                        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300 || parsed.containsKey('error')) {
                                            String message = extractStripeError(parsed);
                                            throw new AuraHandledException(String.isBlank(message) ? httpErrorPrefix + response.getStatusCode() + '.' : message);
                                        }
                                    }

                                    private static String buildPaymentIntentBody(PaymentRequest request, String stripeCustomerId) {
                                        List<String> params = new List<String>();
                                        addFormParam(params, 'amount', String.valueOf((request.amount * 100).setScale(0)));
                                        addFormParam(params, 'currency', request.currencyCode);
                                        addFormParam(params, 'confirm', 'true');
                                        addFormParam(params, 'payment_method', request.paymentMethodId);
                                        addFormParam(params, 'payment_method_types[]', 'card');
                                        addFormParam(params, 'customer', stripeCustomerId);
                                        addFormParam(params, 'setup_future_usage', String.isBlank(stripeCustomerId) ? null : 'off_session');
                                        addFormParam(params, 'description', 'Inventorymagic payment');
                                        if (!String.isBlank(request.fullName)) { addFormParam(params, 'shipping[name]', request.fullName); addFormParam(params, 'metadata[full_name]', request.fullName); }
                                        if (!String.isBlank(request.orderId)) { addFormParam(params, 'metadata[order_id]', request.orderId); addFormParam(params, 'metadata[reference_number]', request.orderId); }
                                        if (!String.isBlank(request.address)) addFormParam(params, 'shipping[address][line1]', request.address);
                                        if (!String.isBlank(request.city)) addFormParam(params, 'shipping[address][city]', request.city);
                                        if (!String.isBlank(request.state)) addFormParam(params, 'shipping[address][state]', request.state);
                                        if (!String.isBlank(request.zip)) addFormParam(params, 'shipping[address][postal_code]', request.zip);
                                        if (!String.isBlank(request.country)) addFormParam(params, 'shipping[address][country]', request.country);
                                        return String.join(params, '&');
                                    }

                                    private static String buildCustomerBody(OrderAccountContext orderAccountContext, PaymentRequest request) {
                                        List<String> params = new List<String>();
                                        addFormParam(params, 'name', !String.isBlank(orderAccountContext.accountName) ? orderAccountContext.accountName : request.fullName);
                                        addFormParam(params, 'metadata[account_id]', orderAccountContext.accountId == null ? null : String.valueOf(orderAccountContext.accountId));
                                        addFormParam(params, 'metadata[order_id]', orderAccountContext.orderId == null ? null : String.valueOf(orderAccountContext.orderId));
                                        return String.join(params, '&');
                                    }

                                    private static String buildStripeInvoiceItemBody(InvoiceAccountContext invoiceContext, String stripeCustomerId, String stripeInvoiceId) {
                                        List<String> params = new List<String>();
                                        addFormParam(params, 'customer', stripeCustomerId);
                                        addFormParam(params, 'invoice', stripeInvoiceId);
                                        addFormParam(params, 'currency', 'usd');
                                        addFormParam(params, 'amount', String.valueOf((invoiceContext.amount * 100).setScale(0)));
                                        addFormParam(params, 'description', 'Invoice ' + invoiceContext.invoiceNumber);
                                        addFormParam(params, 'metadata[invoice_id]', invoiceContext.invoiceId == null ? null : String.valueOf(invoiceContext.invoiceId));
                                        addFormParam(params, 'metadata[invoice_number]', invoiceContext.invoiceNumber);
                                        addFormParam(params, 'metadata[reference_number]', getStripeReferenceNumber(invoiceContext));
                                        addFormParam(params, 'metadata[order_id]', invoiceContext.orderId == null ? null : String.valueOf(invoiceContext.orderId));
                                        return String.join(params, '&');
                                    }

                                    private static String buildStripeInvoiceBody(InvoiceAccountContext invoiceContext, String stripeCustomerId) {
                                        List<String> params = new List<String>();
                                        addFormParam(params, 'customer', stripeCustomerId);
                                        addFormParam(params, 'collection_method', 'send_invoice');
                                        addFormParam(params, 'auto_advance', 'false');
                                        addFormParam(params, 'days_until_due', String.valueOf(getStripeDaysUntilDue(invoiceContext.dueDate)));
                                        addFormParam(params, 'description', 'Invoice ' + invoiceContext.invoiceNumber);
                                        addFormParam(params, 'metadata[invoice_id]', invoiceContext.invoiceId == null ? null : String.valueOf(invoiceContext.invoiceId));
                                        addFormParam(params, 'metadata[invoice_number]', invoiceContext.invoiceNumber);
                                        addFormParam(params, 'metadata[reference_number]', getStripeReferenceNumber(invoiceContext));
                                        addFormParam(params, 'metadata[order_id]', invoiceContext.orderId == null ? null : String.valueOf(invoiceContext.orderId));
                                        return String.join(params, '&');
                                    }

                                    private static String getStripeReferenceNumber(InvoiceAccountContext invoiceContext) {
                                        if (invoiceContext == null) return null;
                                        if (invoiceContext.orderId != null) return String.valueOf(invoiceContext.orderId);
                                        return invoiceContext.referenceNumber;
                                    }

                                    private static Integer getStripeDaysUntilDue(Date dueDate) {
                                        if (dueDate == null) return 30;
                                        Integer daysUntilDue = Date.today().daysBetween(dueDate);
                                        return daysUntilDue <= 0 ? 1 : daysUntilDue;
                                    }

                                    private static HttpResponse sendStripePost(String endpoint, String requestBody, String authorizationHeader) {
                                        HttpRequest httpRequest = new HttpRequest();
                                        httpRequest.setEndpoint(endpoint);
                                        httpRequest.setMethod('POST');
                                        httpRequest.setHeader('Authorization', authorizationHeader);
                                        httpRequest.setHeader('Content-Type', 'application/x-www-form-urlencoded');
                                        httpRequest.setTimeout(20000);
                                        httpRequest.setBody(requestBody);
                                        Http http = new Http();
                                        return http.send(httpRequest);
                                    }

                                    private static void addFormParam(List<String> params, String key, String value) {
                                        if (String.isBlank(key) || value == null) return;
                                        params.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(value, 'UTF-8'));
                                    }

                                    private static String extractStripeError(Map<String, Object> parsed) {
                                        if (parsed == null) return null;
                                        if (parsed.containsKey('error')) {
                                            Map<String, Object> error = (Map<String, Object>) parsed.get('error');
                                            if (error != null && error.containsKey('message')) return String.valueOf(error.get('message'));
                                        }
                                        if (parsed.containsKey('last_payment_error')) {
                                            Map<String, Object> lastPaymentError = (Map<String, Object>) parsed.get('last_payment_error');
                                            if (lastPaymentError != null && lastPaymentError.containsKey('message')) return String.valueOf(lastPaymentError.get('message'));
                                        }
                                        return null;
                                    }

                                    private static String sanitizeJsonBody(String body) {
                                        if (body == null) return null;
                                        return body.trim().replaceFirst('^\\uFEFF', '');
                                    }

                                    private static Boolean isConfigActive(Boolean activeFlag) {
                                        return activeFlag == null ? true : activeFlag;
                                    }

                                    private static String getAvailabilityMessage(Quickbridge_Config__mdt config) {
                                        if (config == null) return 'Stripe configuration record was not found.';
                                        if (!isConfigActive(config.Stripe_Active__c)) return 'Stripe is currently inactive.';
                                        Date today = Date.today();
                                        if (config.Stripe_Start_Date__c != null && config.Stripe_Start_Date__c > today) return 'Stripe is not active yet.';
                                        if (config.Stripe_End_Date__c != null && config.Stripe_End_Date__c < today) return 'Stripe contract has expired.';
                                        return null;
                                    }

                                    private static void logStripePaymentCalloutFailure(String classMethodName, String message, Integer statusCode, PaymentRequest request) {
                                        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
                                        context.gatewayName = 'Stripe';
                                        context.classMethodName = classMethodName;
                                        context.errorMessage = message;
                                        context.httpStatusCode = statusCode;
                                        context.errorCategory = 'Callout Failure';
                                        context.sourceObjectApiName = 'Order';
                                        context.sourceRecordIdText = request == null ? null : request.orderId;
                                        context.sourceRecordId = parseId(context.sourceRecordIdText);
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