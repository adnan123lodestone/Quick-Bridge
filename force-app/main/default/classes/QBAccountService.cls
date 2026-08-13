public inherited sharing class QBAccountService {
    private static final Integer DUPLICATE_NAME_CODE = 6240;
    private static Set<Id> personAccountRecordTypeIds;

    public class SyncResult {
        public Id accountId { get; set; }
        public Boolean created { get; set; }
        public String quickBooksId { get; set; }
    }

    public static void syncAccountsToQuickBooks(List<Account> accounts, Boolean legacyIsInsert) {
        syncAccountsToQuickBooksShared(accounts, legacyIsInsert);
    }

    public static ConnectorExecutionResult syncAccountsToQuickBooksShared(
        List<Account> accounts,
        Boolean legacyIsInsert
    ) {
        ConnectorExecutionResult result = ConnectorExecutionResult.success();
        result.processedCount = accounts == null ? 0 : accounts.size();
        if (accounts == null) {
            return result;
        }
        for (Account accountRecord : accounts) {
            try {
                // legacyIsInsert remains in the signature for queued payload compatibility.
                // The current Salesforce link is the only create/update authority.
                syncAccountToQuickBooksInternal(accountRecord, true);
                result.successfulCount++;
            } catch (Exception exceptionValue) {
                String safeMessage = ConnectorExecutionResult.sanitizeError(exceptionValue.getMessage());
                logAutomaticFailure(safeMessage, accountRecord == null ? null : accountRecord.Id);
                result.failedCount++;
                result.addError(safeMessage);
                if (IntegrationRetryPolicy.isRetryable(exceptionValue)) {
                    result.retryable = true;
                    result.retryDelaySeconds = 60;
                    if (accountRecord != null && accountRecord.Id != null) {
                        result.retryRecordIds.add(accountRecord.Id);
                    }
                }
            }
        }
        return result;
    }

    private static void logAutomaticFailure(String safeMessage, Id accountId) {
        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = 'QuickBooks';
        context.classMethodName = 'QBAccountService.syncAccountsToQuickBooks';
        context.errorMessage = safeMessage;
        context.sourceObjectApiName = 'Account';
        context.sourceRecordId = accountId;
        context.sourceRecordIdText = accountId == null ? null : String.valueOf(accountId);
        context.errorCategory = 'Callout Failure';
        ErrorLogUtility.logError(context);
    }

    public static SyncResult syncAccountToQuickBooks(Account accountRecord, Boolean legacyForceCreate) {
        // legacyForceCreate is intentionally ignored. A populated QuickbookID__c
        // must never be turned into a second create by a stale caller.
        return syncAccountToQuickBooksInternal(accountRecord, false);
    }

    private static SyncResult syncAccountToQuickBooksInternal(
        Account accountRecord,
        Boolean surfaceTypedFailure
    ) {
        if (accountRecord == null) {
            throw new QBIntegrationException('Account is required for QuickBooks sync.');
        }
        SyncResult result = new SyncResult();
        result.accountId = accountRecord.Id;
        if (String.isBlank(accountRecord.QuickbookID__c)) {
            result.created = true;
            result.quickBooksId = createInQuickBooks(accountRecord, surfaceTypedFailure);
            persistQuickBooksId(accountRecord.Id, result.quickBooksId);
        } else {
            result.created = false;
            result.quickBooksId = accountRecord.QuickbookID__c;
            updateInQuickBooks(accountRecord, surfaceTypedFailure);
        }
        return result;
    }

    private static String createInQuickBooks(
        Account accountRecord,
        Boolean surfaceTypedFailure
    ) {
        EntityContext context = resolveEntity(accountRecord);
        Map<String, Object> payload = buildWritablePayload(accountRecord, context);
        String requestBody = serializeCanonical(payload);
        String resource = context.endpoint + '?requestid=' + buildRequestId('C', accountRecord, requestBody);
        HttpResponse response = QuickBooksAuthHandler.makeApiCall('POST', resource, requestBody, false);
        if (response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            Map<String, Object> entity = responseBody == null
                ? null
                : (Map<String, Object>) responseBody.get(context.responseKey);
            String quickBooksId = entity == null ? null : String.valueOf(entity.get('Id'));
            if (String.isBlank(quickBooksId)) {
                throwFailure(502, 'QuickBooks did not return a ' + context.responseKey + ' Id.', surfaceTypedFailure);
            }
            return quickBooksId;
        }
        throwResponseFailure(response, 'create', context.responseKey, surfaceTypedFailure);
        return null;
    }

    private static void updateInQuickBooks(
        Account accountRecord,
        Boolean surfaceTypedFailure
    ) {
        EntityContext context = resolveEntity(accountRecord);
        HttpResponse queryResponse = QuickBooksAuthHandler.makeApiCall(
            'GET',
            context.endpoint + '/' + EncodingUtil.urlEncode(accountRecord.QuickbookID__c, 'UTF-8'),
            null,
            false
        );
        if (queryResponse == null || queryResponse.getStatusCode() < 200 || queryResponse.getStatusCode() >= 300) {
            throwResponseFailure(queryResponse, 'validate linked', context.responseKey, surfaceTypedFailure);
        }

        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(queryResponse.getBody());
        Map<String, Object> existing = responseBody == null
            ? null
            : (Map<String, Object>) responseBody.get(context.responseKey);
        String syncToken = existing == null ? null : String.valueOf(existing.get('SyncToken'));
        String returnedId = existing == null ? null : String.valueOf(existing.get('Id'));
        if (String.isBlank(syncToken) || returnedId != accountRecord.QuickbookID__c) {
            throwFailure(
                400,
                'The Account QuickBooks ID could not be validated. Confirm QuickbookID__c contains the QBO ' +
                context.responseKey + ' Id.',
                surfaceTypedFailure
            );
        }

        Map<String, Object> payload = buildWritablePayload(accountRecord, context);
        payload.put('Id', returnedId);
        payload.put('SyncToken', syncToken);
        payload.put('sparse', true);
        String requestBody = serializeCanonical(payload);
        String resource = context.endpoint + '?requestid=' + buildRequestId('U', accountRecord, requestBody);
        HttpResponse updateResponse = QuickBooksAuthHandler.makeApiCall('POST', resource, requestBody, false);
        if (updateResponse == null || updateResponse.getStatusCode() < 200 || updateResponse.getStatusCode() >= 300) {
            throwResponseFailure(updateResponse, 'update', context.responseKey, surfaceTypedFailure);
        }
    }

    @TestVisible
    private static Map<String, Object> buildWritablePayload(
        Account accountRecord,
        EntityContext context
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        Map<String, String> mappings = context.isVendor
            ? QBVendorFieldCapabilities.filterOutboundMappings(
                QBObjectMappings.getAccountToVendorMapping()
            )
            : QBCustomerFieldCapabilities.filterOutboundMappings(
                QBObjectMappings.getAccountToCustomerMapping()
            );
        for (String salesforceField : mappings.keySet()) {
            String quickBooksField = mappings.get(salesforceField);
            if (
                (context.isVendor && !QBVendorFieldCapabilities.isOutboundWritable(quickBooksField)) ||
                (!context.isVendor && !QBCustomerFieldCapabilities.isOutboundWritable(quickBooksField))
            ) {
                continue;
            }
            Object value = getFieldValue(accountRecord, salesforceField);
            if (value != null) {
                putNestedValue(payload, quickBooksField, value);
            }
        }

        Boolean isPerson = !context.isVendor && isPersonAccount(accountRecord);
        if (isPerson) {
            putIfPopulated(payload, 'GivenName', accountRecord, 'FirstName');
            putIfPopulated(payload, 'MiddleName', accountRecord, 'MiddleName');
            putIfPopulated(payload, 'FamilyName', accountRecord, 'LastName');
            putIfPopulated(payload, 'Suffix', accountRecord, 'Suffix');
            payload.remove('CompanyName');
        } else if (!context.isVendor && !payload.containsKey('CompanyName') && String.isNotBlank(accountRecord.Name)) {
            payload.put('CompanyName', accountRecord.Name);
        }
        if (!payload.containsKey('DisplayName') && String.isNotBlank(accountRecord.Name)) {
            payload.put('DisplayName', accountRecord.Name);
        }
        if (payload.get('DisplayName') == null || String.isBlank(String.valueOf(payload.get('DisplayName')))) {
            throw new QBIntegrationException('Account Name is required for QuickBooks sync.');
        }
        return payload;
    }

    private static void persistQuickBooksId(Id accountId, String quickBooksId) {
        if (accountId == null || String.isBlank(quickBooksId)) {
            return;
        }
        QBTriggerHandler.isAccountProcessing = true;
        try {
            update new Account(Id = accountId, QuickbookID__c = quickBooksId);
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
        }
    }

    private static EntityContext resolveEntity(Account accountRecord) {
        EntityContext context = new EntityContext();
        context.isVendor = false;
        if (accountRecord.RecordTypeId != null) {
            Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosById().get(accountRecord.RecordTypeId);
            context.isVendor = info != null &&
                (info.getName() == 'Vendor' || info.getDeveloperName() == 'Vendor');
        }
        context.endpoint = context.isVendor ? '/vendor' : '/customer';
        context.responseKey = context.isVendor ? 'Vendor' : 'Customer';
        return context;
    }

    private static Boolean isPersonAccount(Account accountRecord) {
        if (accountRecord == null || accountRecord.RecordTypeId == null) {
            return false;
        }
        if (personAccountRecordTypeIds == null) {
            personAccountRecordTypeIds = new Set<Id>();
            for (RecordType recordType : [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Account' AND IsPersonType = true
            ]) {
                personAccountRecordTypeIds.add(recordType.Id);
            }
        }
        return personAccountRecordTypeIds.contains(accountRecord.RecordTypeId);
    }

    private static void putIfPopulated(
        Map<String, Object> payload,
        String quickBooksField,
        Account accountRecord,
        String salesforceField
    ) {
        Object value = getFieldValue(accountRecord, salesforceField);
        if (value != null) {
            payload.put(quickBooksField, value);
        }
    }

    private static void putNestedValue(Map<String, Object> payload, String path, Object value) {
        if (String.isBlank(path) || value == null) {
            return;
        }
        List<String> parts = path.split('\\.');
        Map<String, Object> current = payload;
        for (Integer index = 0; index < parts.size() - 1; index++) {
            if (!(current.get(parts[index]) instanceof Map<String, Object>)) {
                current.put(parts[index], new Map<String, Object>());
            }
            current = (Map<String, Object>) current.get(parts[index]);
        }
        current.put(parts[parts.size() - 1], value);
    }

    private static String buildRequestId(String operation, Account accountRecord, String requestBody) {
        String source = accountRecord.Id == null ? accountRecord.Name : String.valueOf(accountRecord.Id);
        String digest = EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(requestBody))
        ).toLowerCase();
        String requestId = 'QB-' + operation + '-' + source + '-' + digest.substring(0, 20);
        return requestId.length() <= 50 ? requestId : requestId.substring(0, 50);
    }

    private static String serializeCanonical(Object value) {
        if (value instanceof Map<String, Object>) {
            Map<String, Object> valueMap = (Map<String, Object>) value;
            List<String> keys = new List<String>(valueMap.keySet());
            keys.sort();
            List<String> members = new List<String>();
            for (String key : keys) {
                members.add(JSON.serialize(key) + ':' + serializeCanonical(valueMap.get(key)));
            }
            return '{' + String.join(members, ',') + '}';
        }
        if (value instanceof List<Object>) {
            List<String> items = new List<String>();
            for (Object item : (List<Object>) value) {
                items.add(serializeCanonical(item));
            }
            return '[' + String.join(items, ',') + ']';
        }
        return JSON.serialize(value);
    }

    private static void throwResponseFailure(
        HttpResponse response,
        String operation,
        String entityName,
        Boolean surfaceTypedFailure
    ) {
        Integer statusCode = response == null ? 503 : response.getStatusCode();
        String body = response == null ? null : response.getBody();
        Integer providerCode = getProviderErrorCode(body);
        String message = providerCode == DUPLICATE_NAME_CODE
            ? 'A QuickBooks ' + entityName + ' with this display name already exists. Populate Account.QuickbookID__c with the QBO ' + entityName + ' Id or use a unique name.'
            : 'QuickBooks could not ' + operation + ' the ' + entityName +
                '. HTTP ' + statusCode + ': ' + ConnectorExecutionResult.sanitizeError(body);
        throwFailure(statusCode, message, surfaceTypedFailure);
    }

    private static Integer getProviderErrorCode(String body) {
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
            Map<String, Object> fault = parsed == null ? null : (Map<String, Object>) parsed.get('Fault');
            List<Object> errors = fault == null ? null : (List<Object>) fault.get('Error');
            Map<String, Object> first = errors == null || errors.isEmpty()
                ? null
                : (Map<String, Object>) errors[0];
            return first == null || first.get('code') == null
                ? null
                : Integer.valueOf(String.valueOf(first.get('code')));
        } catch (Exception ignored) {
            return null;
        }
    }

    private static void throwFailure(Integer statusCode, String message, Boolean typedFailure) {
        if (typedFailure) {
            throw IntegrationRetryPolicy.exceptionForStatus(statusCode, message);
        }
        throw new QBIntegrationException(message);
    }

    private static Object getFieldValue(SObject recordValue, String fieldPath) {
        try {
            if (recordValue == null || String.isBlank(fieldPath)) {
                return null;
            }
            List<String> parts = fieldPath.split('\\.');
            SObject current = recordValue;
            for (Integer index = 0; index < parts.size() - 1; index++) {
                current = current.getSObject(parts[index]);
                if (current == null) {
                    return null;
                }
            }
            return current.get(parts[parts.size() - 1]);
        } catch (Exception ignored) {
            return null;
        }
    }

    private class EntityContext {
        private Boolean isVendor;
        private String endpoint;
        private String responseKey;
    }
}