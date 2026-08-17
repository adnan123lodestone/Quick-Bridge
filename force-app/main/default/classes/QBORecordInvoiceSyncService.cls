public with sharing class QBORecordInvoiceSyncService {
    private static final Set<String> READ_ONLY_QBO_PROPERTIES = new Set<String>{
        'Id', 'SyncToken', 'InvoiceLink', 'TotalAmt', 'Balance', 'HomeTotalAmt', 'HomeBalance'
    };

    public class SyncResult {
        public Id recordId { get; set; }
        public String objectApiName { get; set; }
        public String quickBooksId { get; set; }
        public String message { get; set; }
    }

    public class QBORecordInvoiceSyncException extends Exception {}

    public static SyncResult sync(Id recordId, String objectApiName) {
        if (recordId == null || String.isBlank(objectApiName)) {
            throw new QBORecordInvoiceSyncException('A record Id and object API name are required.');
        }

        Schema.SObjectType sourceType = Schema.getGlobalDescribe().get(objectApiName);
        if (sourceType == null) {
            throw new QBORecordInvoiceSyncException('The supplied Salesforce object is not available in this org.');
        }
        String canonicalObjectName = sourceType.getDescribe().getName();
        String idObjectName = recordId.getSObjectType().getDescribe().getName();
        if (!QBOInvoiceMappingResolver.objectMatches(canonicalObjectName, idObjectName)) {
            throw new QBORecordInvoiceSyncException('The record Id does not belong to the supplied Salesforce object.');
        }
        if (!sourceType.getDescribe().isAccessible()) {
            throw new QBORecordInvoiceSyncException('You do not have access to the supplied Salesforce object.');
        }

        try {
            QBOInvoiceMappingResolver.ResolverResult mapping = QBOInvoiceMappingResolver.resolve(canonicalObjectName);
            MappingContext context = buildContext(sourceType, mapping);
            SObject record = queryRecord(recordId, context);
            String existingQboId = stringValue(getFieldValue(record, context.qboIdFieldPath));
            Map<String, Object> requestBody = buildRequestBody(record, context, existingQboId);
            HttpResponse response = QuickBooksAuthHandler.makeApiCall('POST', '/invoice', JSON.serialize(requestBody));
            if (response == null || response.getStatusCode() != 200) {
                String message = qboFailureMessage(response, 'QuickBooks Invoice sync failed.');
                ErrorLogUtility.logCalloutFailure(
                    'QuickBooks', 'QBORecordInvoiceSyncService.sync', message,
                    response == null ? null : response.getStatusCode(), canonicalObjectName, recordId
                );
                throw new QBORecordInvoiceSyncException(message);
            }

            Map<String, Object> invoice = responseInvoice(response.getBody());
            String qboId = invoice == null ? null : stringValue(invoice.get('Id'));
            if (String.isBlank(qboId)) {
                throw new QBORecordInvoiceSyncException('QuickBooks did not return an invoice identifier.');
            }
            persistInvoiceFields(recordId, context, invoice, qboId);

            SyncResult result = new SyncResult();
            result.recordId = recordId;
            result.objectApiName = canonicalObjectName;
            result.quickBooksId = qboId;
            result.message = 'Record successfully synced to QuickBooks Invoice ' + qboId + '.';
            return result;
        } catch (QBORecordInvoiceSyncException e) {
            throw e;
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBORecordInvoiceSyncService.sync', e, canonicalObjectName, recordId);
            throw new QBORecordInvoiceSyncException('QuickBooks Invoice sync failed.');
        }
    }

    private class MappingContext {
        Schema.SObjectType sourceType;
        QBOInvoiceMappingResolver.ResolverResult mapping;
        String sourceObjectApiName;
        String qboIdFieldPath;
        String paymentLinkFieldPath;
        Map<String, String> headerFieldPaths = new Map<String, String>();
        Map<String, String> lineFieldPaths = new Map<String, String>();
    }

    private static MappingContext buildContext(
        Schema.SObjectType sourceType,
        QBOInvoiceMappingResolver.ResolverResult mapping
    ) {
        if (mapping == null || String.isBlank(mapping.qboIdField)) {
            throw new QBORecordInvoiceSyncException('Configure an inbound QBO Invoice Id mapping before syncing.');
        }
        if (String.isBlank(mapping.invoiceLinkField)) {
            throw new QBORecordInvoiceSyncException('Configure an inbound InvoiceLink mapping before syncing.');
        }
        if (mapping.headerMappings == null || mapping.headerMappings.isEmpty()) {
            throw new QBORecordInvoiceSyncException('Configure outbound QBO Invoice field mappings before syncing.');
        }
        if (String.isBlank(mapping.lineChildRelationship) || mapping.lineMappings == null || mapping.lineMappings.isEmpty()) {
            throw new QBORecordInvoiceSyncException('Configure a mapped child relationship and Invoice line fields before syncing.');
        }

        MappingContext context = new MappingContext();
        context.sourceType = sourceType;
        context.mapping = mapping;
        context.sourceObjectApiName = sourceType.getDescribe().getName();
        context.qboIdFieldPath = resolveDirectField(sourceType, mapping.qboIdField, 'QBO Invoice Id');
        context.paymentLinkFieldPath = resolveDirectField(sourceType, mapping.invoiceLinkField, 'InvoiceLink');
        assertUpdateable(sourceType, context.qboIdFieldPath, 'QBO Invoice Id');
        assertUpdateable(sourceType, context.paymentLinkFieldPath, 'InvoiceLink');

        for (String sfField : mapping.headerMappings.keySet()) {
            String path = resolveFieldPath(sourceType, sfField);
            if (path == null) {
                throw new QBORecordInvoiceSyncException('The configured Invoice field mapping is not valid: ' + sfField + '.');
            }
            context.headerFieldPaths.put(sfField, path);
        }

        Schema.SObjectType lineType = Schema.getGlobalDescribe().get(mapping.lineSourceObject);
        if (lineType == null || !lineType.getDescribe().isAccessible()) {
            throw new QBORecordInvoiceSyncException('The configured Invoice line object is not available or accessible.');
        }
        for (String sfField : mapping.lineMappings.keySet()) {
            String path = resolveFieldPath(lineType, sfField);
            if (path == null) {
                throw new QBORecordInvoiceSyncException('The configured Invoice line mapping is not valid: ' + sfField + '.');
            }
            context.lineFieldPaths.put(sfField, path);
        }
        return context;
    }

    private static SObject queryRecord(Id recordId, MappingContext context) {
        Set<String> fields = new Set<String>{ 'Id', context.qboIdFieldPath };
        fields.addAll(context.headerFieldPaths.values());
        String query = 'SELECT ' + String.join(new List<String>(fields), ', ');
        List<String> lineFields = new List<String>{ 'Id' };
        lineFields.addAll(context.lineFieldPaths.values());
        query += ', (SELECT ' + String.join(lineFields, ', ') + ' FROM ' + context.mapping.lineChildRelationship + ')';
        query += ' FROM ' + context.sourceObjectApiName + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> records = Database.query(query);
        if (records.isEmpty()) throw new QBORecordInvoiceSyncException('The supplied record was not found.');
        return records[0];
    }

    private static Map<String, Object> buildRequestBody(
        SObject record,
        MappingContext context,
        String existingQboId
    ) {
        Map<String, Object> requestBody = new Map<String, Object>();
        for (String sfField : context.mapping.headerMappings.keySet()) {
            String qboField = context.mapping.headerMappings.get(sfField);
            if (isOutboundFieldBlocked(qboField)) continue;
            Object value = getFieldValue(record, context.headerFieldPaths.get(sfField));
            if (value != null) putPath(requestBody, qboField, normalizeValue(value));
        }
        if (!hasCustomerReference(requestBody)) {
            throw new QBORecordInvoiceSyncException('The QBO Invoice mapping must populate CustomerRef.value.');
        }
        requestBody.put('Line', buildLines(record.getSObjects(context.mapping.lineChildRelationship), context));
        if (String.isNotBlank(existingQboId)) {
            requestBody.put('Id', existingQboId);
            requestBody.put('SyncToken', retrieveSyncToken(existingQboId));
            requestBody.put('sparse', true);
        }
        return requestBody;
    }

    private static List<Map<String, Object>> buildLines(List<SObject> sourceLines, MappingContext context) {
        if (sourceLines == null || sourceLines.isEmpty()) {
            throw new QBORecordInvoiceSyncException('The record has no mapped Invoice line records.');
        }
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (SObject sourceLine : sourceLines) {
            Map<String, Object> line = new Map<String, Object>{ 'DetailType' => 'SalesItemLineDetail' };
            for (String sfField : context.mapping.lineMappings.keySet()) {
                String qboField = context.mapping.lineMappings.get(sfField);
                if (isOutboundFieldBlocked(qboField)) continue;
                Object value = getFieldValue(sourceLine, context.lineFieldPaths.get(sfField));
                if (value == null) continue;
                String linePath = qboField != null && qboField.startsWith('Line.') ? qboField.substringAfter('Line.') : qboField;
                putPath(line, linePath, normalizeValue(value));
            }
            if (!hasItemReference(line)) {
                throw new QBORecordInvoiceSyncException(
                    'Each QBO Invoice line mapping must populate SalesItemLineDetail.ItemRef.value.'
                );
            }
            populateAmountWhenPossible(line);
            if (line.get('Amount') == null) {
                throw new QBORecordInvoiceSyncException('Each QBO Invoice line mapping must populate Amount or Qty and UnitPrice.');
            }
            result.add(line);
        }
        return result;
    }

    private static String retrieveSyncToken(String qboId) {
        HttpResponse response = QuickBooksAuthHandler.makeApiCall(
            'GET', '/invoice/' + EncodingUtil.urlEncode(qboId, 'UTF-8'), null
        );
        if (response == null || response.getStatusCode() != 200) {
            throw new QBORecordInvoiceSyncException('QuickBooks Invoice could not be retrieved for update.');
        }
        Map<String, Object> invoice = responseInvoice(response.getBody());
        String syncToken = invoice == null ? null : stringValue(invoice.get('SyncToken'));
        if (String.isBlank(syncToken)) {
            throw new QBORecordInvoiceSyncException('QuickBooks Invoice did not return a SyncToken for update.');
        }
        return syncToken;
    }

    private static void persistInvoiceFields(
        Id recordId,
        MappingContext context,
        Map<String, Object> invoice,
        String qboId
    ) {
        SObject updateRecord = context.sourceType.newSObject(recordId);
        updateRecord.put(context.qboIdFieldPath, qboId);
        for (String sfField : context.mapping.headerMappings.keySet()) {
            String qboField = context.mapping.headerMappings.get(sfField);
            if (qboField == 'InvoiceLink' || qboField.contains('.')) continue;
            Object value = invoice.get(qboField);
            if (value == null || sfField.contains('.')) continue;
            Schema.SObjectField fieldToken = context.sourceType.getDescribe().fields.getMap().get(sfField.toLowerCase());
            if (fieldToken != null && fieldToken.getDescribe().isUpdateable()) updateRecord.put(fieldToken.getDescribe().getName(), value);
        }
        QuickBooksInvoiceHandler.setBatchContext(true);
        try {
            update updateRecord;
        } finally {
            QuickBooksInvoiceHandler.setBatchContext(false);
        }
    }

    private static String resolveDirectField(Schema.SObjectType type, String fieldName, String purpose) {
        String path = resolveFieldPath(type, fieldName);
        if (path == null || path.contains('.')) {
            throw new QBORecordInvoiceSyncException('The configured ' + purpose + ' field must be a writable field on the source object.');
        }
        return path;
    }

    private static String resolveFieldPath(Schema.SObjectType startType, String configuredPath) {
        if (startType == null || String.isBlank(configuredPath)) return null;
        List<String> parts = configuredPath.split('\\.');
        List<String> resolved = new List<String>();
        Schema.SObjectType currentType = startType;
        for (Integer index = 0; index < parts.size(); index++) {
            Schema.SObjectField fieldToken = findFieldOrRelationship(currentType, parts[index], index < parts.size() - 1);
            if (fieldToken == null) return null;
            Schema.DescribeFieldResult describe = fieldToken.getDescribe();
            if (index == parts.size() - 1) {
                if (!describe.isAccessible()) return null;
                resolved.add(describe.getName());
            } else {
                List<Schema.SObjectType> references = describe.getReferenceTo();
                String relationshipName = describe.getRelationshipName();
                if (references == null || references.size() != 1 || String.isBlank(relationshipName)) return null;
                resolved.add(relationshipName);
                currentType = references[0];
            }
        }
        return String.join(resolved, '.');
    }

    private static Schema.SObjectField findFieldOrRelationship(
        Schema.SObjectType type,
        String requestedName,
        Boolean relationshipRequired
    ) {
        if (type == null || String.isBlank(requestedName)) return null;
        for (Schema.SObjectField token : type.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = token.getDescribe();
            if (relationshipRequired) {
                if (requestedName.equalsIgnoreCase(describe.getRelationshipName())) return token;
            } else if (requestedName.equalsIgnoreCase(describe.getName())) {
                return token;
            }
        }
        return null;
    }

    private static void assertUpdateable(Schema.SObjectType type, String fieldPath, String purpose) {
        Schema.SObjectField token = type.getDescribe().fields.getMap().get(fieldPath.toLowerCase());
        if (!type.getDescribe().isUpdateable() || token == null || !token.getDescribe().isUpdateable()) {
            throw new QBORecordInvoiceSyncException('You do not have update access to the configured ' + purpose + ' field.');
        }
    }

    private static Object getFieldValue(SObject record, String resolvedPath) {
        if (record == null || String.isBlank(resolvedPath)) return null;
        List<String> parts = resolvedPath.split('\\.');
        SObject current = record;
        for (Integer index = 0; index < parts.size() - 1; index++) {
            current = current == null ? null : current.getSObject(parts[index]);
        }
        return current == null ? null : current.get(parts[parts.size() - 1]);
    }

    private static Object normalizeValue(Object value) {
        if (value instanceof Date) {
            return DateTime.newInstance((Date)value, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
        }
        return value;
    }

    private static void putPath(Map<String, Object> target, String path, Object value) {
        if (target == null || String.isBlank(path) || value == null) return;
        List<String> parts = path.split('\\.');
        Map<String, Object> current = target;
        for (Integer index = 0; index < parts.size() - 1; index++) {
            if (!current.containsKey(parts[index]) || !(current.get(parts[index]) instanceof Map<String, Object>)) {
                current.put(parts[index], new Map<String, Object>());
            }
            current = (Map<String, Object>) current.get(parts[index]);
        }
        current.put(parts[parts.size() - 1], value);
    }

    private static Boolean isOutboundFieldBlocked(String qboField) {
        if (String.isBlank(qboField)) return true;
        String root = qboField.contains('.') ? qboField.substringBefore('.') : qboField;
        return READ_ONLY_QBO_PROPERTIES.contains(root) || qboField == 'InvoiceLink';
    }

    private static Boolean hasCustomerReference(Map<String, Object> requestBody) {
        Map<String, Object> customerRef = (Map<String, Object>) requestBody.get('CustomerRef');
        return customerRef != null && String.isNotBlank(stringValue(customerRef.get('value')));
    }

    private static Boolean hasItemReference(Map<String, Object> line) {
        Map<String, Object> detail = (Map<String, Object>) line.get('SalesItemLineDetail');
        Map<String, Object> itemRef = detail == null ? null : (Map<String, Object>) detail.get('ItemRef');
        return itemRef != null && String.isNotBlank(stringValue(itemRef.get('value')));
    }

    private static void populateAmountWhenPossible(Map<String, Object> line) {
        if (line.get('Amount') != null) return;
        Map<String, Object> detail = (Map<String, Object>) line.get('SalesItemLineDetail');
        if (detail == null || !(detail.get('Qty') instanceof Decimal) || !(detail.get('UnitPrice') instanceof Decimal)) return;
        line.put('Amount', ((Decimal)detail.get('Qty')) * ((Decimal)detail.get('UnitPrice')));
    }

    private static Map<String, Object> responseInvoice(String responseBody) {
        if (String.isBlank(responseBody)) return null;
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        return response == null ? null : (Map<String, Object>) response.get('Invoice');
    }

    private static String qboFailureMessage(HttpResponse response, String fallback) {
        if (response == null || String.isBlank(response.getBody())) return fallback;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            Map<String, Object> fault = body == null ? null : (Map<String, Object>) body.get('Fault');
            List<Object> errors = fault == null ? null : (List<Object>) fault.get('Error');
            if (errors != null && !errors.isEmpty()) {
                String message = stringValue(((Map<String, Object>)errors[0]).get('Message'));
                if (String.isNotBlank(message)) return fallback + ' ' + message;
            }
        } catch (Exception ignored) {
        }
        return fallback;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
