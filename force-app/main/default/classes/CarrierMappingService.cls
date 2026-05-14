public with sharing class CarrierMappingService {
    public static final String DIRECTION_TO_CARRIER = 'SF to Carrier';
    public static final String DIRECTION_TO_SF = 'Carrier to SF';
    @TestVisible private static Map<String, MappingSet> testMappingSets;

    private class PathToken {
        public String key;
        public Integer indexValue;
        public Boolean hasIndex = false;
    }

    public class MappingSet {
        public String integration;
        public String actionName;
        public String sfObjectApiName;
        public List<Field_Mapping__mdt> requestMappings = new List<Field_Mapping__mdt>();
        public List<Field_Mapping__mdt> responseMappings = new List<Field_Mapping__mdt>();
    }

    public static MappingSet load(String integration, String actionName, String sfObjectApiName) {
        String mappingKey = getMappingKey(integration, actionName, sfObjectApiName);
        if (Test.isRunningTest() && testMappingSets != null && testMappingSets.containsKey(mappingKey)) {
            return testMappingSets.get(mappingKey);
        }

        MappingSet mappingSet = new MappingSet();
        mappingSet.integration = integration;
        mappingSet.actionName = actionName;
        mappingSet.sfObjectApiName = sfObjectApiName;

        if (String.isBlank(integration) || String.isBlank(actionName) || String.isBlank(sfObjectApiName)) {
            return mappingSet;
        }

        for (Field_Mapping__mdt mapping : queryMappings(integration, actionName, sfObjectApiName)) {
            if (isDirectionToSalesforce(mapping.Sync_Direction__c)) {
                mappingSet.responseMappings.add(mapping);
            } else {
                mappingSet.requestMappings.add(mapping);
            }
        }

        return mappingSet;
    }

    @TestVisible
    private static String getMappingKey(String integration, String actionName, String sfObjectApiName) {
        return String.valueOf(integration) + '|' + String.valueOf(actionName) + '|' + String.valueOf(sfObjectApiName);
    }

    private static List<Field_Mapping__mdt> queryMappings(String integration, String actionName, String sfObjectApiName) {
        List<Field_Mapping__mdt> mappings = new List<Field_Mapping__mdt>();
        String legacyIntegrationActionKey = integration + '_' + actionName;

        mappings.addAll([
            SELECT DeveloperName, Action__c, SF_Object__c, SF_Field__c, External_Field__c, Sync_Direction__c
            FROM Field_Mapping__mdt
            WHERE Integration__c = :integration
            AND Action__c = :actionName
            AND SF_Object__c = :sfObjectApiName
            AND Is_Active__c = true
        ]);
        mappings.addAll([
            SELECT DeveloperName, Action__c, SF_Object__c, SF_Field__c, External_Field__c, Sync_Direction__c
            FROM Field_Mapping__mdt
            WHERE Integration__c = :legacyIntegrationActionKey
            AND SF_Object__c = :sfObjectApiName
            AND Is_Active__c = true
        ]);
        return mappings;
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
            if (String.isNotBlank(mapping.SF_Field__c)) {
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

    public static void applyResponseMappings(Id targetRecordId, MappingSet mappingSet, Map<String, Object> responseValues) {
        SObject updateRecord = buildResponseUpdate(targetRecordId, mappingSet, responseValues);
        if (updateRecord != null) {
            String gateway = String.isBlank(mappingSet.integration) ? 'Carrier' : mappingSet.integration;
            try {
                update updateRecord;
            } catch (DmlException e) {
                // Log every individual DML error row (getDmlMessage(0) only captured the first)
                for (Integer i = 0; i < e.getNumDml(); i++) {
                    ErrorLogUtility.logDmlFailure(
                        gateway,
                        'CarrierMappingService.applyResponseMappings',
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

    public static Object getPath(Map<String, Object> values, String path) {
        if (values == null || String.isBlank(path)) {
            return null;
        }

        Object current = values;
        for (PathToken token : parsePath(path)) {
            if (String.isNotBlank(token.key)) {
                if (current instanceof Map<String, Object>) {
                    current = ((Map<String, Object>) current).get(token.key);
                } else {
                    return null;
                }
            }

            if (token.hasIndex) {
                if (!(current instanceof List<Object>)) {
                    return null;
                }
                List<Object> listValue = (List<Object>) current;
                if (token.indexValue < 0 || token.indexValue >= listValue.size()) {
                    return null;
                }
                current = listValue[token.indexValue];
            } else if (String.isBlank(token.key)) {
                return null;
            }
        }
        return current;
    }

    public static void putPath(Map<String, Object> values, String path, Object fieldValue) {
        if (values == null || String.isBlank(path)) {
            return;
        }

        List<PathToken> tokens = parsePath(path);
        Map<String, Object> current = values;
        for (Integer i = 0; i < tokens.size(); i++) {
            PathToken token = tokens[i];
            Boolean isLast = i == tokens.size() - 1;

            if (String.isBlank(token.key)) {
                return;
            }

            if (token.hasIndex) {
                Object existingList = current.get(token.key);
                if (!(existingList instanceof List<Object>)) {
                    existingList = new List<Object>();
                    current.put(token.key, existingList);
                }
                List<Object> listValue = (List<Object>) existingList;
                while (listValue.size() <= token.indexValue) {
                    listValue.add(null);
                }
                if (isLast) {
                    listValue[token.indexValue] = normalizeOutgoingValue(fieldValue);
                    return;
                }
                if (!(listValue[token.indexValue] instanceof Map<String, Object>)) {
                    listValue[token.indexValue] = new Map<String, Object>();
                }
                current = (Map<String, Object>) listValue[token.indexValue];
                continue;
            }

            if (isLast) {
                current.put(token.key, normalizeOutgoingValue(fieldValue));
                return;
            }

            if (!(current.get(token.key) instanceof Map<String, Object>)) {
                current.put(token.key, new Map<String, Object>());
            }
            current = (Map<String, Object>) current.get(token.key);
        }
    }

    private static List<PathToken> parsePath(String path) {
        List<PathToken> tokens = new List<PathToken>();
        if (String.isBlank(path)) {
            return tokens;
        }

        for (String rawSegment : path.split('\\.')) {
            if (String.isBlank(rawSegment)) {
                continue;
            }
            PathToken token = new PathToken();
            if (rawSegment.startsWith('[') && rawSegment.endsWith(']')) {
                token.hasIndex = true;
                token.indexValue = Integer.valueOf(rawSegment.substring(1, rawSegment.length() - 1));
            } else if (isInteger(rawSegment)) {
                token.hasIndex = true;
                token.indexValue = Integer.valueOf(rawSegment);
            } else if (rawSegment.contains('[') && rawSegment.endsWith(']')) {
                token.key = rawSegment.substringBefore('[');
                token.hasIndex = true;
                Integer startIndex = rawSegment.indexOf('[') + 1;
                token.indexValue = Integer.valueOf(rawSegment.substring(startIndex, rawSegment.length() - 1));
            } else {
                token.key = rawSegment;
            }
            tokens.add(token);
        }
        return tokens;
    }

    private static Boolean isInteger(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        try {
            Integer.valueOf(value);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean isDirectionToSalesforce(String directionValue) {
        if (String.isBlank(directionValue)) {
            return false;
        }
        String normalized = directionValue.trim().toLowerCase();
        return normalized == DIRECTION_TO_SF.toLowerCase()
            || normalized == 'fedex to sf'
            || normalized == 'ups to sf'
            || normalized == 'carrier to salesforce';
    }

    /* Legacy numeric-dot path support is intentionally handled by parsePath only for
       bracket paths; carrier field definitions now use bracket notation for arrays. */
    private static Object legacyGetPath(Map<String, Object> values, String path) {
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

    private static Object getSObjectValue(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) {
            return null;
        }
        try {
            if (fieldApiName.contains('.')) {
                List<String> segments = fieldApiName.split('\\.');
                SObject current = record;
                for (Integer i = 0; i < segments.size() - 1; i++) {
                    current = current == null ? null : current.getSObject(segments[i]);
                }
                return current == null ? null : current.get(segments[segments.size() - 1]);
            }
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
        String className = CarrierMappingService.class.getName();
        return className.contains('.') ? className.substringBefore('.') + '__' : '';
    }
}