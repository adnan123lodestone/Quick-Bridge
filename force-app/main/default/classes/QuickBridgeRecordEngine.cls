public with sharing class QuickBridgeRecordEngine {
    @TestVisible private static List<Invoice_Field_Mapping__mdt> testActiveMappings;
    @TestVisible private static String testInvoicePipelineTargetObject;
    @TestVisible private static Boolean forcePipelineFailureForTest = false;
    private static Map<String, Schema.SObjectType> objectTypeByApiName = new Map<String, Schema.SObjectType>();
    private class PipelineException extends Exception {}

    private class PipelineResult {
        Id canonicalInvoiceId;
    }

    private class PipelineTarget {
        String objectApiName;
        Map<String, String> sourceToTargetFields = new Map<String, String>();
        Map<String, Object> defaultValues = new Map<String, Object>();
        String methodName;
    }

    public static void processIncomingInvoice(Map<String, Object> incomingData) {
        try {
            if (Test.isRunningTest() && forcePipelineFailureForTest) {
                throw new PipelineException('Forced invoice pipeline failure for logging coverage.');
            }
            runInvoicePipeline(incomingData == null ? new Map<String, Object>() : incomingData);
        } catch (Exception e) {
            Id orderId = getIdValue(incomingData, 'Order__c');
            Id accountId = getIdValue(incomingData, 'Related_Account__c');
            if (orderId != null) {
                ErrorLogUtility.logException('Payment', 'QuickBridgeRecordEngine.processIncomingInvoice', e, 'Order', orderId);
            } else if (accountId != null) {
                ErrorLogUtility.logException('Payment', 'QuickBridgeRecordEngine.processIncomingInvoice', e, 'Account', accountId);
            } else {
                ErrorLogUtility.logException('Payment', 'QuickBridgeRecordEngine.processIncomingInvoice', e, null, null);
            }
        }
    }

    private static PipelineResult runInvoicePipeline(Map<String, Object> incomingData) {
        PipelineResult result = new PipelineResult();
        List<PipelineTarget> targets = invoicePipelineTargets();
        if (targets.isEmpty()) {
            throw new AuraHandledException('No invoice pipeline targets are configured.');
        }
        String canonicalObject = targets[0].objectApiName;
        for (PipelineTarget target : targets) {
            SObject record = buildRecord(target, incomingData);
            if (target.objectApiName == canonicalObject) {
                insert record;
                result.canonicalInvoiceId = (Id) record.get('Id');
            } else {
                try {
                    insert record;
                } catch (Exception e) {
                    ErrorLogUtility.logDmlFailure(
                        'Payment',
                        'QuickBridgeRecordEngine.runInvoicePipeline',
                        'insert',
                        target.objectApiName,
                        null,
                        e.getTypeName() + ': ' + e.getMessage(),
                        canonicalObject,
                        result.canonicalInvoiceId
                    );
                }
            }
        }
        return result;
    }

    private static List<PipelineTarget> invoicePipelineTargets() {
        String canonicalTargetObject = resolveCanonicalInvoiceObject();
        PipelineTarget canonicalTarget = defaultInvoiceTarget(canonicalTargetObject);
        List<PipelineTarget> targets = new List<PipelineTarget>{ canonicalTarget };
        Map<String, PipelineTarget> targetsByObject = new Map<String, PipelineTarget>{ canonicalTargetObject => canonicalTarget };

        for (Invoice_Field_Mapping__mdt mapping : loadActiveMappings()) {
            if (String.isBlank(mapping.Target_Object_API_Name__c) || String.isBlank(mapping.Source_Field_API_Name__c) || String.isBlank(mapping.Target_Field_API_Name__c)) {
                continue;
            }
            PipelineTarget target = targetsByObject.get(mapping.Target_Object_API_Name__c);
            if (target == null) {
                target = new PipelineTarget();
                target.objectApiName = mapping.Target_Object_API_Name__c;
                target.methodName = 'QuickBridgeRecordEngine.processIncomingInvoice';
                targetsByObject.put(target.objectApiName, target);
                targets.add(target);
            }
            target.sourceToTargetFields.put(mapping.Source_Field_API_Name__c, mapping.Target_Field_API_Name__c);
        }
        return targets;
    }

    private static String resolveCanonicalInvoiceObject() {
        if (Test.isRunningTest() && String.isNotBlank(testInvoicePipelineTargetObject)) {
            return testInvoicePipelineTargetObject;
        }
        QBOInvoiceMappingResolver.ResolverResult res = QBOInvoiceMappingResolver.resolve();
        if (String.isBlank(res.invoiceSourceObject)) {
            throw new AuraHandledException('QBO invoice mapping did not resolve a Salesforce invoice source object.');
        }
        return res.invoiceSourceObject;
    }

    private static PipelineTarget defaultInvoiceTarget(String targetObject) {
        PipelineTarget invoiceTarget = new PipelineTarget();
        invoiceTarget.objectApiName = targetObject;
        invoiceTarget.methodName = 'QuickBridgeRecordEngine.processIncomingInvoice';
        invoiceTarget.sourceToTargetFields.put('Amount__c', 'Amount__c');
        invoiceTarget.sourceToTargetFields.put('Order__c', 'Order__c');
        invoiceTarget.sourceToTargetFields.put('Related_Account__c', 'Related_Account__c');
        invoiceTarget.sourceToTargetFields.put('Reference_number__c', 'Reference_number__c');
        invoiceTarget.defaultValues.put('Status__c', 'Paid');
        invoiceTarget.defaultValues.put('Invoice_Date__c', Date.today());
        return invoiceTarget;
    }

    private static SObject buildRecord(PipelineTarget target, Map<String, Object> incomingData) {
        Schema.SObjectType objectType = objectTypeFor(target.objectApiName);
        if (objectType == null) {
            throw new AuraHandledException('Unsupported invoice pipeline target: ' + target.objectApiName);
        }

        SObject record = objectType.newSObject();
        Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
        for (String fieldName : target.defaultValues.keySet()) {
            putIfFieldExists(record, fields, fieldName, target.defaultValues.get(fieldName));
        }
        for (String sourceField : target.sourceToTargetFields.keySet()) {
            if (incomingData.containsKey(sourceField)) {
                String targetField = target.sourceToTargetFields.get(sourceField);
                putIfFieldExists(record, fields, targetField, incomingData.get(sourceField));
            }
        }
        return record;
    }

    private static List<Invoice_Field_Mapping__mdt> loadActiveMappings() {
        return Test.isRunningTest() && testActiveMappings != null
            ? testActiveMappings
            : [
                SELECT Target_Object_API_Name__c, Source_Field_API_Name__c, Target_Field_API_Name__c
                FROM Invoice_Field_Mapping__mdt
                WHERE Is_Active__c = true
            ];
    }

    private static Schema.SObjectType objectTypeFor(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }
        if (objectTypeByApiName.containsKey(objectApiName)) {
            return objectTypeByApiName.get(objectApiName);
        }
        try {
            List<Schema.DescribeSObjectResult> describes = Schema.describeSObjects(new List<String>{ objectApiName });
            if (!describes.isEmpty()) {
                Schema.SObjectType objectType = describes[0].getSObjectType();
                objectTypeByApiName.put(objectApiName, objectType);
                return objectType;
            }
        } catch (Exception e) {
            objectTypeByApiName.put(objectApiName, null);
        }
        return null;
    }

    private static void putIfFieldExists(SObject record, Map<String, Schema.SObjectField> fields, String fieldName, Object value) {
        if (record == null || fields == null || String.isBlank(fieldName) || value == null || !fields.containsKey(fieldName)) {
            return;
        }
        Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();
        record.put(fieldName, coerceValue(value, fieldDescribe.getType()));
    }

    private static Object coerceValue(Object value, Schema.DisplayType displayType) {
        if (value == null) {
            return null;
        }
        if (displayType == Schema.DisplayType.Currency ||
            displayType == Schema.DisplayType.Double ||
            displayType == Schema.DisplayType.Percent) {
            return value instanceof Decimal ? value : Decimal.valueOf(String.valueOf(value));
        }
        if (displayType == Schema.DisplayType.Integer) {
            return value instanceof Integer ? value : Integer.valueOf(String.valueOf(value));
        }
        if (displayType == Schema.DisplayType.Boolean) {
            return value instanceof Boolean ? value : String.valueOf(value).toLowerCase() == 'true';
        }
        if (displayType == Schema.DisplayType.Date) {
            return value instanceof Date ? value : Date.valueOf(String.valueOf(value));
        }
        if (displayType == Schema.DisplayType.DateTime) {
            return value instanceof Datetime ? value : Datetime.valueOf(String.valueOf(value));
        }
        return value;
    }

    private static Id getIdValue(Map<String, Object> incomingData, String key) {
        if (incomingData == null || String.isBlank(key) || !incomingData.containsKey(key) || incomingData.get(key) == null) {
            return null;
        }
        try {
            return (Id) incomingData.get(key);
        } catch (Exception e) {
            try {
                return (Id) String.valueOf(incomingData.get(key));
            } catch (Exception ignored) {
                return null;
            }
        }
    }
}