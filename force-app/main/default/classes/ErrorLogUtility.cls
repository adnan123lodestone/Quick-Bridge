public without sharing class ErrorLogUtility {
    private static final Integer ERROR_MESSAGE_MAX_LENGTH = 32000;
    private static final Integer STACK_TRACE_MAX_LENGTH = 32768;
    private static final Map<String, String> PARENT_LOOKUP_FIELD_BY_OBJECT = new Map<String, String>{
        'Order' => 'Order__c',
        'Invoice__c' => 'Invoice__c',
        'Account' => 'Account__c',
        'Portal_Payment_Transaction__c' => 'Portal_Payment_Transaction__c',
        'QuickBridgeTLG__Carrier_Shipment__c' => 'QuickBridgeTLG__Carrier_Shipment__c',
        'Carrier_Package__c' => 'Carrier_Package__c',
        'Carrier_Rate_Quote__c' => 'Carrier_Rate_Quote__c',
        'Carrier_Tracking_Event__c' => 'Carrier_Tracking_Event__c',
        'Shipment' => 'Shipment__c',
        'Case' => 'Case__c',
        'Product2' => 'Product__c',
        'Contact' => 'Contact__c',
        'OrderItem' => 'Order_Item__c',
        'Credit_Memo__c' => 'Credit_Memo__c',
        'Purchase_Order__c' => 'Purchase_Order__c',
        'Item_Sales_Tax__c' => 'Item_Sales_Tax__c'
    };

    public class LogContext {
        public String gatewayName;
        public String classMethodName;
        public String errorMessage;
        public String stackTrace;
        public String sourceObjectApiName;
        public Id sourceRecordId;
        public String sourceRecordIdText;
        public String actionSourceObjectApiName;
        public Id actionSourceRecordId;
        public String actionSourceRecordIdText;
        public String errorCategory;
        public String dmlOperation;
        public Integer httpStatusCode;
        public String externalReference;
    }

    public static void logPaymentError(String gatewayName, String classMethodName, String errorMessage, String orderId) {
        LogContext context = new LogContext();
        context.gatewayName = gatewayName;
        context.classMethodName = classMethodName;
        context.errorMessage = errorMessage;
        context.errorCategory = 'Payment Error';
        context.sourceObjectApiName = 'Order';
        context.sourceRecordIdText = orderId;
        context.sourceRecordId = parseId(orderId);
        logError(context);
    }

    public static void logException(
        String gatewayName,
        String classMethodName,
        Exception exceptionRecord,
        String sourceObjectApiName,
        Id sourceRecordId
    ) {
        LogContext context = new LogContext();
        context.gatewayName = gatewayName;
        context.classMethodName = classMethodName;
        context.errorMessage = exceptionRecord == null ? null : exceptionRecord.getTypeName() + ': ' + exceptionRecord.getMessage();
        context.stackTrace = exceptionRecord == null ? null : exceptionRecord.getStackTraceString();
        context.sourceObjectApiName = sourceObjectApiName;
        context.sourceRecordId = sourceRecordId;
        context.sourceRecordIdText = sourceRecordId == null ? null : String.valueOf(sourceRecordId);
        context.errorCategory = 'Code Exception';
        logError(context);
    }

    public static void logCalloutFailure(
        String gatewayName,
        String classMethodName,
        String errorMessage,
        Integer httpStatusCode,
        String sourceObjectApiName,
        Id sourceRecordId
    ) {
        LogContext context = new LogContext();
        context.gatewayName = gatewayName;
        context.classMethodName = classMethodName;
        context.errorMessage = errorMessage;
        context.httpStatusCode = httpStatusCode;
        context.sourceObjectApiName = sourceObjectApiName;
        context.sourceRecordId = sourceRecordId;
        context.sourceRecordIdText = sourceRecordId == null ? null : String.valueOf(sourceRecordId);
        context.errorCategory = 'Callout Failure';
        logError(context);
    }

    public static void logDmlFailure(
        String gatewayName,
        String classMethodName,
        String dmlOperation,
        String sourceObjectApiName,
        Id sourceRecordId,
        String errorMessage,
        String actionSourceObjectApiName,
        Id actionSourceRecordId
    ) {
        LogContext context = new LogContext();
        context.gatewayName = gatewayName;
        context.classMethodName = classMethodName;
        context.errorMessage = errorMessage;
        context.sourceObjectApiName = sourceObjectApiName;
        context.sourceRecordId = sourceRecordId;
        context.sourceRecordIdText = sourceRecordId == null ? null : String.valueOf(sourceRecordId);
        context.actionSourceObjectApiName = actionSourceObjectApiName;
        context.actionSourceRecordId = actionSourceRecordId;
        context.actionSourceRecordIdText = actionSourceRecordId == null ? null : String.valueOf(actionSourceRecordId);
        context.errorCategory = 'DML Failure';
        context.dmlOperation = dmlOperation;
        logError(context);
    }

    public static void logDmlResults(
        String gatewayName,
        String classMethodName,
        String dmlOperation,
        List<SObject> records,
        List<Database.SaveResult> results,
        String actionSourceObjectApiName,
        Id actionSourceRecordId
    ) {
        if (records == null || results == null) {
            return;
        }

        Integer limitSize = records.size() < results.size() ? records.size() : results.size();
        for (Integer index = 0; index < limitSize; index++) {
            if (results[index] == null || results[index].isSuccess()) {
                continue;
            }

            SObject failedRecord = records[index];
            Id failedRecordId = failedRecord == null ? null : (Id) failedRecord.get('Id');
            String objectApiName = failedRecord == null ? null : failedRecord.getSObjectType().getDescribe().getName();
            String message = buildDmlErrorMessage(results[index].getErrors());
            logDmlFailure(
                gatewayName,
                classMethodName,
                dmlOperation,
                objectApiName,
                failedRecordId,
                message,
                actionSourceObjectApiName,
                actionSourceRecordId
            );
        }
    }

    public static void logUpsertResults(
        String gatewayName,
        String classMethodName,
        String dmlOperation,
        List<SObject> records,
        List<Database.UpsertResult> results,
        String actionSourceObjectApiName,
        Id actionSourceRecordId
    ) {
        if (records == null || results == null) {
            return;
        }

        Integer limitSize = records.size() < results.size() ? records.size() : results.size();
        for (Integer index = 0; index < limitSize; index++) {
            if (results[index] == null || results[index].isSuccess()) {
                continue;
            }

            SObject failedRecord = records[index];
            Id failedRecordId = failedRecord == null ? null : (Id) failedRecord.get('Id');
            String objectApiName = failedRecord == null ? null : failedRecord.getSObjectType().getDescribe().getName();
            String message = buildDmlErrorMessage(results[index].getErrors());
            logDmlFailure(
                gatewayName,
                classMethodName,
                dmlOperation,
                objectApiName,
                failedRecordId,
                message,
                actionSourceObjectApiName,
                actionSourceRecordId
            );
        }
    }

    public static void logError(LogContext context) {
        if (context == null) {
            return;
        }

        try {
            Error_Log__c errorRecord = new Error_Log__c();
            errorRecord.Gateway_Name__c = context.gatewayName;
            errorRecord.Class_Method_Name__c = context.classMethodName;
            errorRecord.Error_Message__c = abbreviate(context.errorMessage, ERROR_MESSAGE_MAX_LENGTH);
            errorRecord.Order_Id__c = context.sourceObjectApiName == 'Order'
                ? firstNonBlank(context.sourceRecordIdText, context.sourceRecordId == null ? null : String.valueOf(context.sourceRecordId))
                : null;

            putIfPresent(errorRecord, 'Source_Object__c', context.sourceObjectApiName);
            putIfPresent(errorRecord, 'Source_Record_Id__c', firstNonBlank(context.sourceRecordIdText, context.sourceRecordId == null ? null : String.valueOf(context.sourceRecordId)));
            putIfPresent(errorRecord, 'Action_Source_Object__c', context.actionSourceObjectApiName);
            putIfPresent(errorRecord, 'Action_Source_Record_Id__c', firstNonBlank(context.actionSourceRecordIdText, context.actionSourceRecordId == null ? null : String.valueOf(context.actionSourceRecordId)));
            putIfPresent(errorRecord, 'Error_Category__c', context.errorCategory);
            putIfPresent(errorRecord, 'Dml_Operation__c', context.dmlOperation);
            putIfPresent(errorRecord, 'Http_Status_Code__c', context.httpStatusCode);
            putIfPresent(errorRecord, 'External_Reference__c', context.externalReference);
            putIfPresent(errorRecord, 'Stack_Trace__c', abbreviate(context.stackTrace, STACK_TRACE_MAX_LENGTH));

            assignParentLookup(errorRecord, context);

            Database.SaveResult result = Database.insert(errorRecord, false);
            if (result != null && result.isSuccess()) {
                IntegrationUsageService.incrementError(context.gatewayName, 1);
            } else if (result != null) {
                System.debug(LoggingLevel.ERROR, 'Error Log Insert Failed: ' + buildDmlErrorMessage(result.getErrors()));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error Log Insert Failed: ' + e.getMessage());
        }
    }

    private static void assignParentLookup(Error_Log__c errorRecord, LogContext context) {
        Id parentId = context.sourceRecordId;
        String objectApiName = context.sourceObjectApiName;

        if (parentId == null && context.actionSourceRecordId != null) {
            parentId = context.actionSourceRecordId;
            objectApiName = context.actionSourceObjectApiName;
        }
        if (parentId == null) {
            return;
        }

        try {
            String describedObjectApiName = parentId.getSObjectType().getDescribe().getName();
            for (String supportedObjectApiName : PARENT_LOOKUP_FIELD_BY_OBJECT.keySet()) {
                if (objectApiNameMatches(objectApiName, supportedObjectApiName) ||
                    objectApiNameMatches(describedObjectApiName, supportedObjectApiName)) {
                    putIfPresent(errorRecord, PARENT_LOOKUP_FIELD_BY_OBJECT.get(supportedObjectApiName), parentId);
                    return;
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error Log parent lookup assignment skipped: ' + e.getMessage());
        }
    }

    private static Boolean objectApiNameMatches(String actualObjectApiName, String supportedObjectApiName) {
        if (String.isBlank(actualObjectApiName) || String.isBlank(supportedObjectApiName)) {
            return false;
        }
        return actualObjectApiName == supportedObjectApiName ||
            actualObjectApiName.endsWith('__' + supportedObjectApiName);
    }

    private static Id parseId(String rawId) {
        if (String.isBlank(rawId)) {
            return null;
        }
        try {
            return (Id) rawId;
        } catch (Exception e) {
            return null;
        }
    }

    private static void putIfPresent(SObject targetRecord, String fieldApiName, Object value) {
        if (targetRecord == null || String.isBlank(fieldApiName) || value == null) {
            return;
        }
        try {
            targetRecord.put(fieldApiName, value);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error Log field skipped: ' + fieldApiName + ' - ' + e.getMessage());
        }
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isBlank(firstValue) ? secondValue : firstValue;
    }

    private static String abbreviate(String value, Integer maxLength) {
        if (value == null || maxLength == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    private static String buildDmlErrorMessage(Database.Error[] errors) {
        if (errors == null || errors.size() == 0) {
            return 'Unknown DML error.';
        }

        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            if (error == null) {
                continue;
            }
            messages.add(error.getStatusCode() + ': ' + error.getMessage());
        }
        return messages.isEmpty() ? 'Unknown DML error.' : String.join(messages, ' | ');
    }
}