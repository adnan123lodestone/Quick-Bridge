public without sharing class AuthorizeNetPaymentService {

    private static final String AUTHORIZE_NET_API_ENDPOINT = 'callout:AuthorizeNet/xml/v1/request.api';
    private static final String AUTHORIZE_NET_API_LOGIN_ID_MERGE_FIELD = '{!$Credential.AuthorizeNet_Credentials.APILoginID}';
    private static final String AUTHORIZE_NET_TRANSACTION_KEY_MERGE_FIELD = '{!$Credential.AuthorizeNet_Credentials.TransactionKey}';
    private static final String SANDBOX_ACCEPT_JS_URL = 'https://jstest.authorize.net/v1/Accept.js';
    private static final String PRODUCTION_ACCEPT_JS_URL = 'https://js.authorize.net/v1/Accept.js';

    public class ClientConfigResponse {
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Boolean configured { get; set; }
        @AuraEnabled public String apiLoginId { get; set; }
        @AuraEnabled public String publicClientKey { get; set; }
        @AuraEnabled public Boolean useSandbox { get; set; }
        @AuraEnabled public String acceptJsUrl { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    public class PaymentRequest {
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Boolean allowPlatformSession { get; set; }
        @AuraEnabled public String orderId { get; set; }
        @AuraEnabled public String sessionToken { get; set; }
        @AuraEnabled public String dataDescriptor { get; set; }
        @AuraEnabled public String dataValue { get; set; }
        @AuraEnabled public String fullName { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String zip { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String transactionType { get; set; }
    }

    public class PaymentResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String transId { get; set; }
        @AuraEnabled public String resultCode { get; set; }
        @AuraEnabled public String authCode { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static ClientConfigResponse getClientConfig() {
        ClientConfigResponse response = new ClientConfigResponse();
        try {
            AuthorizeNet_Config__mdt config = getConfig();

            String availabilityMessage = getAvailabilityMessage(config);
            response.active = availabilityMessage == null;
            response.apiLoginId = config.APILoginId__c;
            response.publicClientKey = config.PublicClientKey__c;
            response.useSandbox = config.UseSandbox__c;
            response.acceptJsUrl = config.UseSandbox__c ? SANDBOX_ACCEPT_JS_URL : PRODUCTION_ACCEPT_JS_URL;

            List<String> missingItems = new List<String>();
            if (String.isBlank(config.APILoginId__c)) {
                missingItems.add('API Login ID');
            }
            if (String.isBlank(config.PublicClientKey__c)) {
                missingItems.add('Public Client Key');
            }

            response.configured = response.active && missingItems.isEmpty();
            if (availabilityMessage != null) {
                response.message = availabilityMessage;
            } else if (!missingItems.isEmpty()) {
                response.message = 'Authorize.Net is not fully configured. Missing: ' + String.join(missingItems, ', ');
            } else {
                response.message = 'Authorize.Net client configuration loaded.';
            }
        } catch (Exception e) {
            response.active = false;
            response.configured = false;
            response.message = 'Unable to load Authorize.Net client configuration.';
            System.debug(LoggingLevel.ERROR,
                'AuthorizeNetPaymentService.getClientConfig exception: ' +
                e.getTypeName() + ' line=' + e.getLineNumber() + ' message=' + e.getMessage()
            );
        }

        return response;
    }

    @AuraEnabled
    public static PaymentResponse processOpaquePayment(PaymentRequest request) {
        PaymentResponse response = new PaymentResponse();
        try {
            Savepoint pendingWorkSavepoint = Database.setSavepoint();
            validateRequest(request);

            AuthorizeNet_Config__mdt config = getConfig();
            String availabilityMessage = getAvailabilityMessage(config);
            if (availabilityMessage != null) {
                throw new AuraHandledException(availabilityMessage);
            }

            String requestBody = buildTransactionPayload(request);
            Database.rollback(pendingWorkSavepoint);
            Database.releaseSavepoint(pendingWorkSavepoint);

            HttpRequest httpRequest = new HttpRequest();
            httpRequest.setEndpoint(AUTHORIZE_NET_API_ENDPOINT);
            httpRequest.setMethod('POST');
            httpRequest.setHeader('Content-Type', 'application/json');
            httpRequest.setTimeout(20000);
            httpRequest.setBody(requestBody);

            Http http = new Http();
            HttpResponse httpResponse = http.send(httpRequest);
            String responseBody = sanitizeJsonBody(httpResponse.getBody());

            if (httpResponse.getStatusCode() < 200 || httpResponse.getStatusCode() >= 300) {
                response.success = false;
                response.message = 'Authorize.Net transaction call failed with HTTP ' + httpResponse.getStatusCode() + '.';
                return response;
            }

            if (String.isBlank(responseBody) || (!responseBody.startsWith('{') && !responseBody.startsWith('['))) {
                response.success = false;
                response.message = 'Authorize.Net returned an invalid response.';
                return response;
            }

            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Map<String, Object> messages = (Map<String, Object>) parsed.get('messages');
            Map<String, Object> transactionResponse = (Map<String, Object>) parsed.get('transactionResponse');

            response.resultCode = messages == null ? null : String.valueOf(messages.get('resultCode'));
            response.transId = transactionResponse == null ? null : String.valueOf(transactionResponse.get('transId'));
            response.authCode = transactionResponse == null ? null : String.valueOf(transactionResponse.get('authCode'));

            String transactionResponseCode = transactionResponse == null ? null : String.valueOf(transactionResponse.get('responseCode'));
            if (response.resultCode == 'Ok' && transactionResponseCode == '1' && !String.isBlank(response.transId)) {
                response.success = true;
                response.message = 'Transaction Successful';
                return response;
            }

            response.success = false;
            response.message = extractErrorMessage(parsed);
            if (String.isBlank(response.message)) {
                response.message = 'Transaction Unsuccessful';
            }
        } catch (AuraHandledException e) {
            response.success = false;
            response.message = e.getMessage();
        } catch (Exception e) {
            response.success = false;
            String debugMsg = e.getTypeName() + ': ' + e.getMessage();
            response.message = debugMsg;
            System.debug(LoggingLevel.ERROR,
                'AuthorizeNetPaymentService.processOpaquePayment exception: ' +
                e.getTypeName() + ' line=' + e.getLineNumber() + ' message=' + e.getMessage()
            );
        }

        return response;
    }

    private static AuthorizeNet_Config__mdt getConfig() {
        AuthorizeNet_Config__mdt config = AuthorizeNet_Config__mdt.getInstance('Default');
        if (Test.isRunningTest()) {
            AuthorizeNet_Config__mdt testConfig = new AuthorizeNet_Config__mdt();
            testConfig.Active__c = config == null || config.Active__c == null
                ? true
                : config.Active__c;
            testConfig.StartDate__c = config == null ? null : config.StartDate__c;
            testConfig.EndDate__c = config == null ? null : config.EndDate__c;
            testConfig.APILoginId__c = config == null || String.isBlank(config.APILoginId__c)
                ? 'api_login_test'
                : config.APILoginId__c;
            testConfig.PublicClientKey__c = config == null || String.isBlank(config.PublicClientKey__c)
                ? 'public_client_key_test'
                : config.PublicClientKey__c;
            testConfig.UseSandbox__c = config == null || config.UseSandbox__c == null
                ? true
                : config.UseSandbox__c;
            return testConfig;
        }

        if (config == null) {
            throw new AuraHandledException('Authorize.Net configuration record was not found.');
        }
        return config;
    }

    private static void validateRequest(PaymentRequest request) {
        if (request == null) {
            throw new AuraHandledException('Missing payment request.');
        }
        if (!isInternalUserContext()) {
            throw new AuraHandledException('This payment action is only available to authenticated internal users.');
        }
        if (request.amount == null || request.amount <= 0) {
            throw new AuraHandledException('Payment amount must be greater than zero.');
        }
        if (String.isBlank(request.dataDescriptor) || String.isBlank(request.dataValue)) {
            throw new AuraHandledException('Payment tokenization failed. Please try again.');
        }
        if (String.isBlank(request.transactionType)) {
            request.transactionType = 'authCaptureTransaction';
        }
    }

    private static Boolean isInternalUserContext() {
        return Network.getNetworkId() == null
            && UserInfo.getUserType() != 'Guest';
    }

    private static String buildTransactionPayload(PaymentRequest request) {
        JSONGenerator generator = JSON.createGenerator(false);
        generator.writeStartObject();
            generator.writeFieldName('createTransactionRequest');
            generator.writeStartObject();
                generator.writeFieldName('merchantAuthentication');
                generator.writeStartObject();
                    generator.writeStringField('name', AUTHORIZE_NET_API_LOGIN_ID_MERGE_FIELD);
                    generator.writeStringField('transactionKey', AUTHORIZE_NET_TRANSACTION_KEY_MERGE_FIELD);
                generator.writeEndObject();
                if (!String.isBlank(request.orderId)) {
                    generator.writeStringField('refId', request.orderId);
                }

                generator.writeFieldName('transactionRequest');
                generator.writeStartObject();
                    generator.writeStringField('transactionType', request.transactionType);
                    generator.writeStringField('amount', String.valueOf(request.amount.setScale(2)));
                    generator.writeFieldName('payment');
                    generator.writeStartObject();
                        generator.writeFieldName('opaqueData');
                        generator.writeStartObject();
                            generator.writeStringField('dataDescriptor', request.dataDescriptor);
                            generator.writeStringField('dataValue', request.dataValue);
                        generator.writeEndObject();
                    generator.writeEndObject();

                    if (hasBillToData(request)) {
                        generator.writeFieldName('billTo');
                        generator.writeStartObject();
                            Map<String, String> splitName = splitName(request.fullName);
                            if (!String.isBlank(splitName.get('firstName'))) {
                                generator.writeStringField('firstName', splitName.get('firstName'));
                            }
                            if (!String.isBlank(splitName.get('lastName'))) {
                                generator.writeStringField('lastName', splitName.get('lastName'));
                            }
                            if (!String.isBlank(request.address)) {
                                generator.writeStringField('address', request.address);
                            }
                            if (!String.isBlank(request.city)) {
                                generator.writeStringField('city', request.city);
                            }
                            if (!String.isBlank(request.state)) {
                                generator.writeStringField('state', request.state);
                            }
                            if (!String.isBlank(request.zip)) {
                                generator.writeStringField('zip', request.zip);
                            }
                            if (!String.isBlank(request.country)) {
                                generator.writeStringField('country', request.country);
                            }
                        generator.writeEndObject();
                    }
                generator.writeEndObject();
            generator.writeEndObject();
        generator.writeEndObject();

        return generator.getAsString();
    }

    private static Boolean hasBillToData(PaymentRequest request) {
        return !String.isBlank(request.fullName) ||
            !String.isBlank(request.address) ||
            !String.isBlank(request.city) ||
            !String.isBlank(request.state) ||
            !String.isBlank(request.zip) ||
            !String.isBlank(request.country);
    }

    private static Map<String, String> splitName(String fullName) {
        Map<String, String> result = new Map<String, String>{ 'firstName' => null, 'lastName' => null };
        if (String.isBlank(fullName)) {
            return result;
        }

        List<String> parts = fullName.trim().split('\\s+');
        if (parts.isEmpty()) {
            return result;
        }

        result.put('firstName', parts[0]);
        if (parts.size() > 1) {
            List<String> lastNameParts = new List<String>();
            for (Integer index = 1; index < parts.size(); index++) {
                lastNameParts.add(parts[index]);
            }
            result.put('lastName', String.join(lastNameParts, ' '));
        }

        return result;
    }

    private static String extractErrorMessage(Map<String, Object> parsed) {
        Map<String, Object> transactionResponse = (Map<String, Object>) parsed.get('transactionResponse');
        if (transactionResponse != null && transactionResponse.containsKey('errors')) {
            Object errors = transactionResponse.get('errors');
            if (errors instanceof List<Object> && !((List<Object>) errors).isEmpty()) {
                Map<String, Object> firstError = (Map<String, Object>) ((List<Object>) errors)[0];
                return String.valueOf(firstError.get('errorText'));
            }
        }

        Map<String, Object> messages = (Map<String, Object>) parsed.get('messages');
        if (messages != null && messages.containsKey('message')) {
            Object messageObject = messages.get('message');
            if (messageObject instanceof List<Object> && !((List<Object>) messageObject).isEmpty()) {
                Map<String, Object> firstMessage = (Map<String, Object>) ((List<Object>) messageObject)[0];
                return String.valueOf(firstMessage.get('text'));
            }
        }

        return null;
    }

    private static String sanitizeJsonBody(String body) {
        if (body == null) {
            return null;
        }
        return body.trim().replaceFirst('^\\uFEFF', '');
    }

    private static Boolean isConfigActive(Boolean activeFlag) {
        return activeFlag == null ? true : activeFlag;
    }

    private static String getAvailabilityMessage(AuthorizeNet_Config__mdt config) {
        if (config == null) {
            return 'Authorize.Net configuration record was not found.';
        }

        if (!isConfigActive(config.Active__c)) {
            return 'Authorize.Net is currently inactive.';
        }

        Date today = Date.today();
        if (config.StartDate__c != null && config.StartDate__c > today) {
            return 'Authorize.Net is not active yet.';
        }
        if (config.EndDate__c != null && config.EndDate__c < today) {
            return 'Authorize.Net contract has expired.';
        }

        return null;
    }
}