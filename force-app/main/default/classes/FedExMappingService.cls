public with sharing class FedExMappingService {
    public static final String DIRECTION_TO_FEDEX = 'SF to FedEx';
    public static final String DIRECTION_TO_SF = 'FedEx to SF';

    public class MappingSet {
        public String actionName;
        public String sfObjectApiName;
        public List<Field_Mapping__mdt> requestMappings = new List<Field_Mapping__mdt>();
        public List<Field_Mapping__mdt> responseMappings = new List<Field_Mapping__mdt>();
    }

    public static MappingSet load(String actionName, String sfObjectApiName) {
        MappingSet mappingSet = new MappingSet();
        mappingSet.actionName = actionName;
        mappingSet.sfObjectApiName = sfObjectApiName;

        if (String.isBlank(actionName) || String.isBlank(sfObjectApiName)) {
            return mappingSet;
        }

        for (Field_Mapping__mdt mapping : [
            SELECT DeveloperName, Action__c, SF_Object__c, SF_Field__c, External_Field__c, Sync_Direction__c
            FROM Field_Mapping__mdt
            WHERE Integration__c = 'fedex'
            AND Action__c = :actionName
            AND SF_Object__c = :sfObjectApiName
            AND Is_Active__c = true
        ]) {
            if (mapping.Sync_Direction__c == DIRECTION_TO_SF) {
                mappingSet.responseMappings.add(mapping);
            } else {
                mappingSet.requestMappings.add(mapping);
            }
        }

        return mappingSet;
    }

    public static SObject queryMappedRecord(Id recordId, MappingSet mappingSet, String direction) {
        if (recordId == null || mappingSet == null || String.isBlank(mappingSet.sfObjectApiName)) {
            throw new AuraHandledException('A source record and Salesforce object are required.');
        }

        Set<String> fieldNames = new Set<String>{ 'Id' };
        List<Field_Mapping__mdt> mappings = direction == DIRECTION_TO_SF
            ? mappingSet.responseMappings
            : mappingSet.requestMappings;

        for (Field_Mapping__mdt mapping : mappings) {
            if (String.isNotBlank(mapping.SF_Field__c) && !mapping.SF_Field__c.contains('.')) {
                fieldNames.add(mapping.SF_Field__c);
            }
        }

        String queryText = 'SELECT ' + String.join(new List<String>(fieldNames), ',') +
            ' FROM ' + mappingSet.sfObjectApiName +
            ' WHERE Id = :recordId LIMIT 1';
        return Database.query(queryText);
    }

    public static Map<String, Object> buildRequestPayload(SObject sourceRecord, MappingSet mappingSet) {
        Map<String, Object> payload = new Map<String, Object>();
        if (sourceRecord == null || mappingSet == null) {
            return payload;
        }

        for (Field_Mapping__mdt mapping : mappingSet.requestMappings) {
            if (String.isBlank(mapping.SF_Field__c) || String.isBlank(mapping.External_Field__c)) {
                continue;
            }

            Object fieldValue = getSObjectValue(sourceRecord, mapping.SF_Field__c);
            if (fieldValue != null) {
                putPath(payload, mapping.External_Field__c, fieldValue);
            }
        }
        return payload;
    }

    public static SObject buildResponseUpdate(Id targetRecordId, MappingSet mappingSet, Map<String, Object> responseValues) {
        if (targetRecordId == null || mappingSet == null || String.isBlank(mappingSet.sfObjectApiName)) {
            return null;
        }

        Schema.SObjectType sObjectType = getSObjectType(mappingSet.sfObjectApiName);
        if (sObjectType == null) {
            return null;
        }

        SObject updateRecord = sObjectType.newSObject(targetRecordId);
        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
        Boolean hasChanges = false;

        for (Field_Mapping__mdt mapping : mappingSet.responseMappings) {
            if (String.isBlank(mapping.SF_Field__c) || String.isBlank(mapping.External_Field__c)) {
                continue;
            }
            if (!fieldMap.containsKey(mapping.SF_Field__c)) {
                continue;
            }

            Object responseValue = getPath(responseValues, mapping.External_Field__c);
            if (responseValue == null) {
                continue;
            }

            Schema.DescribeFieldResult describeField = fieldMap.get(mapping.SF_Field__c).getDescribe();
            if (!describeField.isUpdateable()) {
                continue;
            }

            updateRecord.put(mapping.SF_Field__c, coerceValue(responseValue, describeField.getType()));
            hasChanges = true;
        }

        return hasChanges ? updateRecord : null;
    }

    public static void applyResponseMappings(Id targetRecordId, MappingSet mappingSet, Map<String, Object> responseValues) {
        SObject updateRecord = buildResponseUpdate(targetRecordId, mappingSet, responseValues);
        if (updateRecord != null) {
            try {
                update updateRecord;
            } catch (DmlException e) {
                for (Integer i = 0; i < e.getNumDml(); i++) {
                    ErrorLogUtility.logDmlFailure(
                        'FedEx',
                        'FedExMappingService.applyResponseMappings',
                        'update',
                        mappingSet.sfObjectApiName,
                        targetRecordId,
                        e.getDmlMessage(i),
                        null,
                        null
                    );
                }
                throw e;
            }
        }
    }

    public static Object getPath(Map<String, Object> values, String path) {
        if (values == null || String.isBlank(path)) {
            return null;
        }

        Object current = values;
        for (String segment : path.split('\\.')) {
            if (current instanceof Map<String, Object>) {
                current = ((Map<String, Object>) current).get(segment);
            } else if (current instanceof List<Object>) {
                Integer indexValue;
                try {
                    indexValue = Integer.valueOf(segment);
                } catch (Exception e) {
                    return null;
                }
                List<Object> listValue = (List<Object>) current;
                if (indexValue < 0 || indexValue >= listValue.size()) {
                    return null;
                }
                current = listValue[indexValue];
            } else {
                return null;
            }
        }
        return current;
    }

    public static void putPath(Map<String, Object> values, String path, Object fieldValue) {
        if (values == null || String.isBlank(path)) {
            return;
        }

        List<String> segments = path.split('\\.');
        Map<String, Object> current = values;
        for (Integer i = 0; i < segments.size(); i++) {
            String segment = segments[i];
            if (i == segments.size() - 1) {
                current.put(segment, normalizeOutgoingValue(fieldValue));
            } else {
                if (!(current.get(segment) instanceof Map<String, Object>)) {
                    current.put(segment, new Map<String, Object>());
                }
                current = (Map<String, Object>) current.get(segment);
            }
        }
    }

    public static Map<String, Object> flattenSelectedPaths(Map<String, Object> values, Set<String> paths) {
        Map<String, Object> flattened = new Map<String, Object>();
        for (String path : paths) {
            flattened.put(path, getPath(values, path));
        }
        return flattened;
    }

    private static Object getSObjectValue(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName) || fieldApiName.contains('.')) {
            return null;
        }
        try {
            return record.get(fieldApiName);
        } catch (Exception e) {
            return null;
        }
    }

    private static Object normalizeOutgoingValue(Object value) {
        if (value instanceof Date) {
            return String.valueOf((Date) value);
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }
        return value;
    }

    private static Object coerceValue(Object value, Schema.DisplayType displayType) {
        if (value == null) {
            return null;
        }

        if (displayType == Schema.DisplayType.Boolean) {
            if (value instanceof Boolean) return value;
            return String.valueOf(value).equalsIgnoreCase('true');
        }
        if (displayType == Schema.DisplayType.Currency ||
            displayType == Schema.DisplayType.Double ||
            displayType == Schema.DisplayType.Percent) {
            if (value instanceof Decimal) return value;
            return Decimal.valueOf(String.valueOf(value));
        }
        if (displayType == Schema.DisplayType.Integer) {
            if (value instanceof Integer) return value;
            return Integer.valueOf(String.valueOf(value));
        }
        if (displayType == Schema.DisplayType.Date) {
            if (value instanceof Date) return value;
            if (value instanceof Datetime) return ((Datetime) value).date();
            return Date.valueOf(String.valueOf(value).left(10));
        }
        if (displayType == Schema.DisplayType.DateTime) {
            if (value instanceof Datetime) return value;
            String stringValue = String.valueOf(value);
            if (stringValue.contains('T')) {
                return Datetime.valueOfGmt(stringValue.replace('T', ' ').replace('Z', ''));
            }
            return Datetime.valueOf(stringValue);
        }
        return String.valueOf(value);
    }

    private static Schema.SObjectType getSObjectType(String objectApiName) {
        if (String.isBlank(objectApiName)) return null;

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType sObjectType = globalDescribe.get(objectApiName);
        if (sObjectType == null && objectApiName.endsWith('__c')) {
            String namespacePrefix = getNamespacePrefix();
            if (String.isNotBlank(namespacePrefix) && !objectApiName.startsWith(namespacePrefix)) {
                sObjectType = globalDescribe.get(namespacePrefix + objectApiName);
            }
        }
        return sObjectType;
    }

    private static String getNamespacePrefix() {
        String className = FedExMappingService.class.getName();
        return className.contains('.') ? className.substringBefore('.') + '__' : '';
    }
}