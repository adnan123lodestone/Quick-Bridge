public without sharing class ErrorLogUtility {
    private static final Integer ERROR_MESSAGE_MAX_LENGTH = 32000;
    private static final Integer STACK_TRACE_MAX_LENGTH = 32768;
    
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
        
        List<LogContext> contexts = new List<LogContext>();
        Integer limitSize = records.size() < results.size() ? records.size() : results.size();
        for (Integer index = 0; index < limitSize; index++) {
            if (results[index] == null || results[index].isSuccess()) {
                continue;
            }
            
            SObject failedRecord = records[index];
            Id failedRecordId = failedRecord == null ? null : (Id) failedRecord.get('Id');
            String objectApiName = failedRecord == null ? null : failedRecord.getSObjectType().getDescribe().getName();
            String message = buildDmlErrorMessage(results[index].getErrors());
            contexts.add(buildDmlFailureContext(
                gatewayName,
                classMethodName,
                dmlOperation,
                objectApiName,
                failedRecordId,
                message,
                actionSourceObjectApiName,
                actionSourceRecordId
            ));
        }
        logErrors(contexts);
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
        
        List<LogContext> contexts = new List<LogContext>();
        Integer limitSize = records.size() < results.size() ? records.size() : results.size();
        for (Integer index = 0; index < limitSize; index++) {
            if (results[index] == null || results[index].isSuccess()) {
                continue;
            }
            
            SObject failedRecord = records[index];
            Id failedRecordId = failedRecord == null ? null : (Id) failedRecord.get('Id');
            String objectApiName = failedRecord == null ? null : failedRecord.getSObjectType().getDescribe().getName();
            String message = buildDmlErrorMessage(results[index].getErrors());
            contexts.add(buildDmlFailureContext(
                gatewayName,
                classMethodName,
                dmlOperation,
                objectApiName,
                failedRecordId,
                message,
                actionSourceObjectApiName,
                actionSourceRecordId
            ));
        }
        logErrors(contexts);
    }
    
    public static void logError(LogContext context) {
        if (context == null) {
            return;
        }
        logErrors(new List<LogContext>{ context });
    }

    /**
     * Persists a collection of errors with a fixed number of DML statements.
     * The input index is retained through the partial-success insert so links
     * and usage events are only created for Error Logs that were saved.
     */
    public static void logErrors(List<LogContext> contexts) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }

        try {
            List<Error_Log__c> errorRecords = new List<Error_Log__c>();
            List<LogContext> alignedContexts = new List<LogContext>();
            for (LogContext context : contexts) {
                if (context == null) {
                    continue;
                }
                errorRecords.add(buildErrorRecord(context));
                alignedContexts.add(context);
            }
            if (errorRecords.isEmpty()) {
                return;
            }

            Database.SaveResult[] results = Database.insert(errorRecords, false);
            List<Error_Log_Link__c> links = new List<Error_Log_Link__c>();
            List<String> successfulGateways = new List<String>();
            for (Integer index = 0; index < results.size(); index++) {
                Database.SaveResult result = results[index];
                if (result != null && result.isSuccess()) {
                    LogContext context = alignedContexts[index];
                    addGenericLinks(links, result.getId(), context);
                    successfulGateways.add(context.gatewayName);
                } else if (result != null) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'Error Log Insert Failed: ' + buildDmlErrorMessage(result.getErrors())
                    );
                }
            }
            if (!links.isEmpty()) {
                Database.insert(links, false);
            }
            if (!successfulGateways.isEmpty()) {
                IntegrationUsageService.incrementErrors(successfulGateways);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error Log Insert Failed: ' + e.getMessage());
        }
    }

    private static Error_Log__c buildErrorRecord(LogContext context) {
        Error_Log__c errorRecord = new Error_Log__c();
        errorRecord.Gateway_Name__c = context.gatewayName;
        errorRecord.Class_Method_Name__c = context.classMethodName;
        errorRecord.Error_Message__c = abbreviate(context.errorMessage, ERROR_MESSAGE_MAX_LENGTH);
        errorRecord.Order_Id__c = context.sourceObjectApiName == 'Order'
            ? firstNonBlank(context.sourceRecordIdText, context.sourceRecordId == null ? null : String.valueOf(context.sourceRecordId))
            : null;
        errorRecord.Is_Retryable__c = isRetryableError(context);
        errorRecord.Retry_Status__c = 'Pending';
        errorRecord.Retry_Count__c = 0;
        putIfPresent(errorRecord, 'Source_Object__c', context.sourceObjectApiName);
        putIfPresent(errorRecord, 'Source_Record_Id__c', firstNonBlank(context.sourceRecordIdText, context.sourceRecordId == null ? null : String.valueOf(context.sourceRecordId)));
        putIfPresent(errorRecord, 'Action_Source_Object__c', context.actionSourceObjectApiName);
        putIfPresent(errorRecord, 'Action_Source_Record_Id__c', firstNonBlank(context.actionSourceRecordIdText, context.actionSourceRecordId == null ? null : String.valueOf(context.actionSourceRecordId)));
        putIfPresent(errorRecord, 'Error_Category__c', context.errorCategory);
        putIfPresent(errorRecord, 'Dml_Operation__c', context.dmlOperation);
        putIfPresent(errorRecord, 'Http_Status_Code__c', context.httpStatusCode);
        putIfPresent(errorRecord, 'External_Reference__c', context.externalReference);
        putIfPresent(errorRecord, 'Stack_Trace__c', abbreviate(context.stackTrace, STACK_TRACE_MAX_LENGTH));
        if (context.sourceObjectApiName == 'Account') {
            putIfPresent(errorRecord, 'Account__c', context.sourceRecordId);
        }
        return errorRecord;
    }

    private static LogContext buildDmlFailureContext(
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
        return context;
    }

    private static void addGenericLinks(List<Error_Log_Link__c> links, Id errorLogId, LogContext context) {
        if (errorLogId == null || context == null) {
            return;
        }
        addLink(links, errorLogId, context.sourceObjectApiName, context.sourceRecordIdText, context.sourceRecordId, 'Source');
        addLink(links, errorLogId, context.actionSourceObjectApiName, context.actionSourceRecordIdText, context.actionSourceRecordId, 'Action Source');
    }

    private static void addLink(List<Error_Log_Link__c> links, Id errorLogId, String objectApiName, String recordIdText, Id recordId, String role) {
        String resolvedRecordId = firstNonBlank(recordIdText, recordId == null ? null : String.valueOf(recordId));
        if (String.isBlank(objectApiName) || String.isBlank(resolvedRecordId)) {
            return;
        }
        links.add(new Error_Log_Link__c(
            Error_Log__c = errorLogId,
            Linked_Object_API_Name__c = objectApiName,
            Linked_Record_Id__c = resolvedRecordId,
            Relationship_Role__c = role
        ));
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
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDynamicLogs(String gatewayName) {
        Map<String, Object> result = new Map<String, Object>();
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        List<String> queryFields = new List<String>{'Id', 'Name'};
        
        try {
            // 1. Get object
            String objectName = getErrorLogObjectName();
            if (String.isBlank(objectName)) {
                result.put('columns', columns);
                result.put('records', new List<SObject>());
                return result;
            }
            
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectName);
            if (sObjType == null) {
                result.put('columns', columns);
                result.put('records', new List<SObject>());
                return result;
            }
            
            // 2. Get field set - SIMPLE APPROACH
            Schema.FieldSet fieldSet = getErrorLogFieldSet(sObjType);
            if (fieldSet == null) {
                result.put('columns', columns);
                result.put('records', new List<SObject>());
                return result;
            }
            
            // 3. Build columns (same as before)
            for (Schema.FieldSetMember fsm : fieldSet.getFields()) {
                String fieldPath = fsm.getFieldPath();
                
                if (!queryFields.contains(fieldPath)) {
                    queryFields.add(fieldPath);
                }
                
                Map<String, Object> col = new Map<String, Object>();
                col.put('label', fsm.getLabel());
                col.put('fieldName', fieldPath);
                
                Schema.DisplayType sfType = fsm.getType();
                
                if (sfType == Schema.DisplayType.DATETIME || sfType == Schema.DisplayType.DATE) {
                    col.put('type', 'date');
                    col.put('typeAttributes', new Map<String, Object>{
                        'year' => 'numeric', 'month' => 'short', 'day' => '2-digit',
                        'hour' => '2-digit', 'minute' => '2-digit'
                    });
                }
                else if (sfType == Schema.DisplayType.REFERENCE) {
                    col.put('type', 'url');
                    col.put('fieldName', fieldPath + '_Url');
                    col.put('typeAttributes', new Map<String, Object>{
                        'label' => new Map<String, String>{ 'fieldName' => fieldPath + '_Name' },
                        'target' => '_blank'
                    });
                    
                    String relationName = fieldPath.endsWith('__c') ? fieldPath.replace('__c', '__r') : fieldPath.replace('Id', '');
                    if (!queryFields.contains(relationName + '.Name')) {
                        queryFields.add(relationName + '.Name');
                    }
                }
                else {
                    col.put('type', 'text');
                    col.put('wrapText', true);
                }
                
                columns.add(col);
            }
            
            // 4. Add required fields
            String namespace = getNamespace();
            addRequiredFields(queryFields, namespace);
            
            // 5. Build SOQL
            String gatewayField = addNamespace('Gateway_Name__c', namespace);
            String errorMsgField = addNamespace('Error_Message__c', namespace);
            
            String query = 'SELECT ' + String.join(queryFields, ', ') +
                ' FROM ' + objectName +
                ' WHERE ' + gatewayField + ' = :gatewayName ' +
                ' ORDER BY CreatedDate DESC LIMIT 500';
            
            List<SObject> records = Database.query(query);
            
            // 6. Redact
            for (SObject rec : records) {
                String raw = (String) rec.get(errorMsgField);
                if (raw != null) {
                    rec.put(errorMsgField, redactSensitive(raw));
                }
            }
            
            result.put('columns', columns);
            result.put('records', records);
            
        } catch (Exception e) {
            result.put('columns', columns);
            result.put('records', new List<SObject>());
        }
        
        return result;
    }

    // ============ SIMPLE HELPER METHODS ============

    private static String getErrorLogObjectName() {
        // Try common patterns
        String namespace = getNamespace();
        List<String> possibleNames = new List<String>();
        
        if (String.isNotBlank(namespace)) {
            possibleNames.add(namespace + '__Error_Log__c');
        }
        possibleNames.add('Error_Log__c');
        
        for (String name : possibleNames) {
            if (Schema.getGlobalDescribe().containsKey(name)) {
                return name;
            }
        }
        
        // Search for it
        for (String key : Schema.getGlobalDescribe().keySet()) {
            if (key.endsWith('Error_Log__c')) {
                return key;
            }
        }
        
        return null;
    }

    private static String getNamespace() {
        try {
            String className = ErrorLogUtility.class.getName();
            if (className.contains('.')) {
                String ns = className.substringBefore('.');
                if (String.isNotBlank(ns) && !ns.equals('ErrorLogUtility')) {
                    return ns;
                }
            }
        } catch (Exception e) {}
        return null;
    }

    private static Schema.FieldSet getErrorLogFieldSet(Schema.SObjectType sObjType) {
        if (sObjType == null) return null;
        
        Map<String, Schema.FieldSet> fieldSetMap = sObjType.getDescribe().fieldSets.getMap();
        String namespace = getNamespace();
        
        // Try all possible names
        List<String> possibleNames = new List<String>();
        
        if (String.isNotBlank(namespace)) {
            possibleNames.add(namespace + '__Default_Error_Logs');
            possibleNames.add(namespace + '__DefaultErrorLogs');
            possibleNames.add(namespace + '__Error_Log_Field_Set');
        }
        possibleNames.add('Default_Error_Logs');
        possibleNames.add('DefaultErrorLogs');
        possibleNames.add('Error_Log_Field_Set');
        possibleNames.add('Default Error Logs');
        
        for (String name : possibleNames) {
            if (fieldSetMap.containsKey(name)) {
                return fieldSetMap.get(name);
            }
        }
        
        // Search by pattern
        for (String key : fieldSetMap.keySet()) {
            if (key.contains('Default') && key.contains('Error')) {
                return fieldSetMap.get(key);
            }
        }
        
        return null;
    }

    private static String addNamespace(String fieldName, String namespace) {
        if (String.isBlank(fieldName)) return fieldName;
        if (String.isNotBlank(namespace) && fieldName.endsWith('__c')) {
            return namespace + '__' + fieldName;
        }
        return fieldName;
    }

    private static void addRequiredFields(List<String> queryFields, String namespace) {
        if (queryFields == null) return;
        
        List<String> required = new List<String>{
            'Gateway_Name__c',
            'Error_Message__c',
            'Is_Retryable__c',
            'Retry_Count__c',
            'Retry_Status__c',
            'CreatedDate'
        };
        
        for (String field : required) {
            String fieldWithNs = addNamespace(field, namespace);
            if (!queryFields.contains(fieldWithNs)) {
                queryFields.add(fieldWithNs);
            }
        }
    }
    
    private static Boolean isRetryableError(LogContext ctx) {
        if (ctx == null) {
            return false;
        }

        if (ctx.httpStatusCode != null) {
            return IntegrationRetryPolicy.classify(ctx.httpStatusCode).retryable;
        }

        String msg = ctx.errorMessage?.toLowerCase();
        if (msg != null) {
            Integer parsedStatusCode = IntegrationRetryPolicy.httpStatusCodeFromMessage(msg);
            if (parsedStatusCode != null) {
                return IntegrationRetryPolicy.classify(parsedStatusCode).retryable;
            }
            if (IntegrationRetryPolicy.isRetryableMessage(msg) ||
                msg.contains('connection reset') ||
                msg.contains('rate limit')) {
                return true;
            }
            if (msg.contains('invalid') ||
                msg.contains('required field') ||
                msg.contains('mismatch') ||
                msg.contains('not found') ||
                msg.contains('duplicate')) {
                return false;
            }
        }

        return false;
    }
    
    @AuraEnabled
    public static void updateRetryCount(Id errorLogId) {
        Error_Log__c log = [SELECT Id, Retry_Count__c FROM Error_Log__c WHERE Id = :errorLogId LIMIT 1];
        Integer newCount = (Integer) (log.Retry_Count__c == null ? 0 : log.Retry_Count__c) + 1;
        log.Retry_Count__c = newCount;
        update log;
    }

    // Redacts common secret patterns (passwords, tokens, API keys) from a log message
    // before the message is surfaced to the UI via getDynamicLogs.
    public static String redactSensitive(String message) {
        if (String.isBlank(message)) {
            return message;
        }
        String result = message;
        // key=value patterns: password=X, token=X, secret=X, key=X, apikey=X
        result = result.replaceAll('(?i)(password|passwd|pwd|token|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)\\s*[:=]\\s*\\S+', '$1=[REDACTED]');
        // Authorization header values: Bearer <token>, Basic <creds>
        result = result.replaceAll('(?i)(Authorization:\\s*(?:Bearer|Basic))\\s+\\S+', '$1 [REDACTED]');
        return result;
    }
}