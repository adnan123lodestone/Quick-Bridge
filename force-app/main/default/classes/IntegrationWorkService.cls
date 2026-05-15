public with sharing class IntegrationWorkService {
    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_PROCESSING = 'Processing';
    public static final String STATUS_RETRY = 'Retry';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_FAILED = 'Failed';
    public static final String STATUS_CANCELLED = 'Cancelled';

    private static Boolean dispatchRequested = false;

    public static Id enqueue(IntegrationWorkRequest request) {
        List<Id> ids = enqueue(new List<IntegrationWorkRequest>{ request });
        return ids.isEmpty() ? null : ids[0];
    }

    public static List<Id> enqueue(List<IntegrationWorkRequest> requests) {
        List<Id> resultIds = new List<Id>();
        if (requests == null || requests.isEmpty()) {
            return resultIds;
        }

        List<Integration_Work_Item__c> upserts = new List<Integration_Work_Item__c>();
        Map<String, IntegrationWorkRequest> requestsByKey = new Map<String, IntegrationWorkRequest>();
        for (IntegrationWorkRequest request : requests) {
            normalizeAndValidate(request);
            String uniqueKey = buildUniqueKey(request);
            requestsByKey.put(uniqueKey, request);
        }

        Map<String, Integration_Work_Item__c> existingByKey = new Map<String, Integration_Work_Item__c>();
        for (Integration_Work_Item__c existing : [
            SELECT Id, Unique_Key__c, Status__c, Coalesced_Count__c, Attempt_Count__c, Max_Attempts__c,
                Needs_Reprocess__c, Payload_Hash__c
            FROM Integration_Work_Item__c
            WHERE Unique_Key__c IN :requestsByKey.keySet()
        ]) {
            existingByKey.put(existing.Unique_Key__c, existing);
        }

        Datetime nowValue = System.now();
        for (String uniqueKey : requestsByKey.keySet()) {
            IntegrationWorkRequest request = requestsByKey.get(uniqueKey);
            Integration_Work_Item__c existing = existingByKey.get(uniqueKey);
            Integration_Work_Item__c item = existing == null
                ? new Integration_Work_Item__c(Unique_Key__c = uniqueKey)
                : new Integration_Work_Item__c(Id = existing.Id, Unique_Key__c = uniqueKey);

            item.Integration__c = request.integration;
            item.Operation__c = request.operation;
            item.Source_Object__c = request.sourceObject;
            item.Source_Record_Id__c = request.sourceRecordId;
            item.Source_Salesforce_Id__c = request.sourceSalesforceId == null ? null : String.valueOf(request.sourceSalesforceId);
            item.Source_External_Id__c = request.sourceExternalId;
            item.Lock_Key__c = request.lockKey;
            item.Additional_Lock_Keys__c = request.additionalLockKeys == null ? null : JSON.serialize(request.additionalLockKeys);
            item.Payload__c = request.payloadJson;
            item.Payload_Hash__c = payloadHash(request.payloadJson);
            item.Last_Enqueued_At__c = nowValue;
            item.Max_Attempts__c = request.maxAttempts == null ? IntegrationRetryPolicy.DEFAULT_MAX_ATTEMPTS : request.maxAttempts;

            if (existing == null) {
                item.Status__c = STATUS_PENDING;
                item.Attempt_Count__c = 0;
                item.Coalesced_Count__c = 0;
                item.Next_Attempt_At__c = request.nextAttemptAt;
            } else if (existing.Status__c == STATUS_PROCESSING) {
                item.Needs_Reprocess__c = true;
                item.Coalesced_Count__c = (existing.Coalesced_Count__c == null ? 0 : existing.Coalesced_Count__c) + 1;
            } else if (existing.Status__c == STATUS_PENDING || existing.Status__c == STATUS_RETRY) {
                item.Status__c = STATUS_PENDING;
                item.Needs_Reprocess__c = false;
                item.Coalesced_Count__c = (existing.Coalesced_Count__c == null ? 0 : existing.Coalesced_Count__c) + 1;
                item.Next_Attempt_At__c = request.nextAttemptAt;
            } else if (existing.Status__c == STATUS_COMPLETED || existing.Status__c == STATUS_FAILED || existing.Status__c == STATUS_CANCELLED) {
                item.Status__c = STATUS_PENDING;
                item.Attempt_Count__c = 0;
                item.Needs_Reprocess__c = false;
                item.Completed_At__c = null;
                item.Last_Error__c = null;
                item.Next_Attempt_At__c = request.nextAttemptAt;
            }

            upserts.add(item);
        }

        if (!upserts.isEmpty()) {
            upsert upserts Integration_Work_Item__c.Unique_Key__c;
            for (Integration_Work_Item__c item : upserts) {
                resultIds.add(item.Id);
            }
            requestDispatch(upserts);
        }

        return resultIds;
    }

    public static Boolean isEnabled(String integration, String operation) {
        try {
            Integration_Work_Setting__mdt exact = Integration_Work_Setting__mdt.getInstance(settingName(integration, operation));
            if (exact != null && exact.Enabled__c != null) {
                return exact.Enabled__c;
            }
            Integration_Work_Setting__mdt integrationDefault = Integration_Work_Setting__mdt.getInstance(settingName(integration, 'Default'));
            if (integrationDefault != null && integrationDefault.Enabled__c != null) {
                return integrationDefault.Enabled__c;
            }
            Integration_Work_Setting__mdt globalDefault = Integration_Work_Setting__mdt.getInstance('Global_Default');
            if (globalDefault != null && globalDefault.Enabled__c != null) {
                return globalDefault.Enabled__c;
            }
        } catch (Exception ignored) {
        }
        return true;
    }

    public static Integer dispatchBatchSize() {
        try {
            Integration_Work_Setting__mdt globalDefault = Integration_Work_Setting__mdt.getInstance('Global_Default');
            if (globalDefault != null && globalDefault.Dispatch_Batch_Size__c != null && globalDefault.Dispatch_Batch_Size__c > 0) {
                return Math.min(50, Integer.valueOf(globalDefault.Dispatch_Batch_Size__c));
            }
        } catch (Exception ignored) {
        }
        return 25;
    }

    public static Integer leaseMinutes() {
        try {
            Integration_Work_Setting__mdt globalDefault = Integration_Work_Setting__mdt.getInstance('Global_Default');
            if (globalDefault != null && globalDefault.Lease_Minutes__c != null && globalDefault.Lease_Minutes__c > 0) {
                return Integer.valueOf(globalDefault.Lease_Minutes__c);
            }
        } catch (Exception ignored) {
        }
        return 10;
    }

    public static String buildUniqueKey(IntegrationWorkRequest request) {
        return String.join(new List<String>{
            safeKeyPart(request.integration),
            safeKeyPart(request.operation),
            safeKeyPart(request.sourceObject),
            safeKeyPart(request.sourceRecordId)
        }, '|');
    }

    public static String payloadHash(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            return null;
        }
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(payloadJson)));
    }

    public static Map<String, Object> parsePayload(Integration_Work_Item__c item) {
        if (item == null || String.isBlank(item.Payload__c)) {
            return new Map<String, Object>();
        }
        Object parsed = JSON.deserializeUntyped(item.Payload__c);
        return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : new Map<String, Object>();
    }

    public static void enqueueQuickBooksWork(String operation, String sourceObject, Id sourceId, String lockKey, Boolean isInitialSync) {
        if (!isEnabled('QuickBooks', operation)) {
            return;
        }
        enqueue(IntegrationWorkRequest.quickBooks(
            operation,
            sourceObject,
            sourceId,
            lockKey,
            new Map<String, Object>{ 'isInitialSync' => isInitialSync == true }
        ));
    }

    public static void requestDispatch(List<Integration_Work_Item__c> items) {
        if (Test.isRunningTest()) {
            return;
        }
        if (dispatchRequested || System.isBatch() || System.isFuture()) {
            return;
        }
        dispatchRequested = true;
        try {
            System.enqueueJob(new IntegrationWorkDispatcher());
        } catch (Exception e) {
            for (Integration_Work_Item__c item : items) {
                item.Last_Dispatch_Requested_At__c = System.now();
            }
            try {
                update items;
            } catch (Exception ignored) {
            }
        }
    }

    private static void normalizeAndValidate(IntegrationWorkRequest request) {
        if (request == null) {
            throw new IntegrationWorkException('Integration work request is required.');
        }
        if (String.isBlank(request.integration) || String.isBlank(request.operation)) {
            throw new IntegrationWorkException('Integration and operation are required.');
        }
        if (String.isBlank(request.sourceObject)) {
            throw new IntegrationWorkException('Source object is required.');
        }
        if (String.isBlank(request.sourceRecordId) && request.sourceSalesforceId != null) {
            request.sourceRecordId = String.valueOf(request.sourceSalesforceId);
        }
        if (String.isBlank(request.sourceRecordId)) {
            throw new IntegrationWorkException('Source record id is required.');
        }
        if (String.isBlank(request.lockKey)) {
            request.lockKey = request.sourceObject + ':' + request.sourceRecordId;
        }
    }

    private static String settingName(String integration, String operation) {
        return (safeDeveloperName(integration) + '_' + safeDeveloperName(operation)).left(40);
    }

    private static String safeDeveloperName(String value) {
        if (String.isBlank(value)) {
            return 'Default';
        }
        String cleaned = value.replaceAll('[^A-Za-z0-9_]', '_');
        cleaned = cleaned.replaceAll('_+', '_');
        return cleaned.left(40);
    }

    private static String safeKeyPart(String value) {
        return String.isBlank(value) ? '' : value.trim();
    }

    public class IntegrationWorkException extends Exception {}
}