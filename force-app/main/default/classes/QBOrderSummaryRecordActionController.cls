public with sharing class QBOrderSummaryRecordActionController {
    
    private static final Set<String> QBO_READONLY_PROPS = new Set<String>{
        'TotalAmt',
        'Balance',
        'HomeTotalAmt',
        'HomeBalance'
    };

    public class ActionResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String quickBooksId { get; set; }
    }

    public class QboTargetInfo {
        public String endpointPath { get; set; }
        public String qboObjectName { get; set; }
        
        public QboTargetInfo(String endpoint, String objName) {
            this.endpointPath = endpoint;
            this.qboObjectName = objName;
        }
    }

    @AuraEnabled
    public static ActionResponse syncToQuickBooks(Id orderSummaryId) {
        try {
            QBORecordInvoiceSyncService.SyncResult syncResult =
                QBORecordInvoiceSyncService.sync(
                    orderSummaryId,
                    orderSummaryId == null ? null : orderSummaryId.getSObjectType().getDescribe().getName()
                );
            ActionResponse actionResponse = new ActionResponse();
            actionResponse.success = true;
            actionResponse.quickBooksId = syncResult.quickBooksId;
            actionResponse.message = syncResult.message;
            return actionResponse;
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBOrderSummaryRecordActionController.syncToQuickBooks', e, 'OrderSummary', orderSummaryId);
            throw buildActionException(e);
        }
    }

    @AuraEnabled
    public static ActionResponse syncFromQuickBooks(Id orderSummaryId) {
        try {
            if (orderSummaryId == null) {
                throw new AuraHandledException('Order Summary Id is required.');
            }

            if (!Schema.getGlobalDescribe().containsKey('OrderSummary')) {
                throw new AuraHandledException('OrderSummary object is not available in this org.');
            }

            String orderSummaryFields = buildOrderSummaryQueryFields();
            String query = 'SELECT ' + orderSummaryFields + ', AccountId FROM OrderSummary WHERE Id = :orderSummaryId LIMIT 1';
            List<SObject> summaries = Database.query(query);
            if (summaries.isEmpty()) {
                throw new AuraHandledException('Order Summary not found.');
            }
            SObject summary = summaries[0];

            String qbId = (String)getFieldValue(summary, 'QuickbookID__c');
            if (String.isBlank(qbId)) {
                throw new AuraHandledException('This Order Summary does not have a QuickBooks ID yet. Run Sync To QB first.');
            }

            String statusVal = (String)getFieldValue(summary, 'Status');
            QboTargetInfo targetInfo = getQboTargetInfo(statusVal);
            String endpointPath = targetInfo.endpointPath;
            String qboObjectName = targetInfo.qboObjectName;

            HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', endpointPath + '/' + qbId, null);
            if (response == null || response.getStatusCode() != 200) {
                throw new AuraHandledException(getQuickBooksErrorMessage(response, 'QuickBooks ' + qboObjectName + ' could not be retrieved.'));
            }

            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
            Map<String, Object> qboData = (Map<String, Object>)responseMap.get(qboObjectName);
            if (qboData == null) {
                throw new AuraHandledException('QuickBooks returned an empty ' + qboObjectName + ' response.');
            }

            Map<String, String> invoiceToOrderSummaryMapping = QBObjectMappings.getInvoiceToOrderSummaryMapping();
            SObject summaryToUpdate = Schema.getGlobalDescribe().get('OrderSummary').newSObject((Id)summary.get('Id'));
            applyQuickBooksDataToRecord(summaryToUpdate, qboData, invoiceToOrderSummaryMapping);

            putFieldValue(summaryToUpdate, 'QuickbookID__c', (String)qboData.get('Id'));
            putFieldValue(summaryToUpdate, 'SyncToken__c', (String)qboData.get('SyncToken'));

            QuickBooksInvoiceHandler.setBatchContext(true);
            QBTriggerHandler.isOrderProcessing = true;
            try {
                update summaryToUpdate;
            } finally {
                QuickBooksInvoiceHandler.setBatchContext(false);
                QBTriggerHandler.isOrderProcessing = false;
            }

            ActionResponse actionResponse = new ActionResponse();
            actionResponse.success = true;
            actionResponse.quickBooksId = (String)qboData.get('Id');
            actionResponse.message = 'Order Summary successfully updated from QuickBooks ' + qboObjectName + ' ' + (String)qboData.get('Id') + '.';
            return actionResponse;

        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBOrderSummaryRecordActionController.syncFromQuickBooks', e, 'OrderSummary', orderSummaryId);
            throw buildActionException(e);
        }
    }

    public static String buildOrderSummaryQueryFields() {
        if (!Schema.getGlobalDescribe().containsKey('OrderSummary')) return 'Id';
        Map<String, Schema.SObjectField> schemaFields = Schema.getGlobalDescribe().get('OrderSummary').getDescribe().fields.getMap();
        Set<String> names = new Set<String>{ 'Id', 'Status', 'AccountId', 'QuickbookID__c', 'SyncToken__c' };
        for (String sfField : QBObjectMappings.getOrderSummaryToInvoiceMapping().keySet()) {
            if (!sfField.contains('.')) {
                names.add(sfField);
            }
        }
        Set<String> resolved = new Set<String>();
        for (String f : names) {
            String key = f.toLowerCase();
            Schema.SObjectField token = schemaFields.get(key);
            if (token == null) {
                token = schemaFields.get('quickbridgetlg__' + key);
            }
            if (token != null) {
                resolved.add(token.getDescribe().getName());
            }
        }
        return resolved.isEmpty() ? 'Id' : String.join(new List<String>(resolved), ', ');
    }

    public static String buildOrderItemSummaryQueryFields() {
        if (!Schema.getGlobalDescribe().containsKey('OrderItemSummary')) return '';
        Map<String, Schema.SObjectField> schemaFields = Schema.getGlobalDescribe().get('OrderItemSummary').getDescribe().fields.getMap();
        Set<String> extra = new Set<String>();
        for (String sfField : QBObjectMappings.getOrderItemSummaryMapping().keySet()) {
            if (!sfField.contains('.')) {
                extra.add(sfField);
            }
        }
        Set<String> base = new Set<String>{ 'id', 'quantity', 'unitprice', 'description', 'totalprice',
            'product2id', 'qb_lineitemid__c', 'quickbridgetlg__qb_lineitemid__c' };
        List<String> additional = new List<String>();
        for (String f : extra) {
            if (!base.contains(f.toLowerCase())) {
                Schema.SObjectField token = schemaFields.get(f.toLowerCase());
                if (token == null) {
                    token = schemaFields.get('quickbridgetlg__' + f.toLowerCase());
                }
                if (token != null) {
                    String apiName = token.getDescribe().getName();
                    additional.add(apiName);
                    base.add(apiName.toLowerCase());
                }
            }
        }
        return additional.isEmpty() ? '' : ', ' + String.join(additional, ', ');
    }

    public static QboTargetInfo getQboTargetInfo(String status) {
        Boolean mapDraftOrdersAsEstimates = false;
        try {
            mapDraftOrdersAsEstimates = ConnectorConfigResolver.getBoolean('qbo', 'Map_Draft_Orders_as_Estimates__c');
        } catch (Exception e) {
            System.debug('Could not load Draft Order setting: ' + e.getMessage());
        }

        if (status == 'Draft') {
            if (mapDraftOrdersAsEstimates) {
                return new QboTargetInfo('/estimate', 'Estimate');
            } else {
                return new QboTargetInfo('/invoice', 'Invoice');
            }
        } else {
            return new QboTargetInfo('/invoice', 'Invoice');
        }
    }

    public static Object getFieldValue(SObject obj, String fieldPath) {
        if (obj == null || String.isBlank(fieldPath)) return null;
        
        Map<String, Schema.SObjectField> fields = obj.getSObjectType().getDescribe().fields.getMap();
        String lowPath = fieldPath.toLowerCase();
        
        if (!fieldPath.contains('.')) {
            if (fields.containsKey(lowPath)) {
                return obj.get(fields.get(lowPath).getDescribe().getName());
            }
            if (fields.containsKey('quickbridgetlg__' + lowPath)) {
                return obj.get(fields.get('quickbridgetlg__' + lowPath).getDescribe().getName());
            }
            try {
                return obj.get(fieldPath);
            } catch (Exception e) {
                return null;
            }
        }
        
        List<String> fieldParts = fieldPath.split('\\.');
        SObject currentObj = obj;
        for (Integer i = 0; i < fieldParts.size() - 1; i++) {
            currentObj = currentObj.getSObject(fieldParts[i]);
            if (currentObj == null) return null;
        }
        String lastField = fieldParts[fieldParts.size() - 1];
        try {
            return currentObj.get(lastField);
        } catch (Exception e) {
            return null;
        }
    }

    public static void putFieldValue(SObject record, String fieldName, Object value) {
        if (record == null || String.isBlank(fieldName) || fieldName.contains('.') || value == null) {
            return;
        }

        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        String lowName = fieldName.toLowerCase();
        Schema.SObjectField token = fields.get(lowName);
        if (token == null) {
            token = fields.get('quickbridgetlg__' + lowName);
        }
        if (token == null) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe = token.getDescribe();
        if (!fieldDescribe.isCreateable() && !fieldDescribe.isUpdateable()) {
            return;
        }

        record.put(token.getDescribe().getName(), value);
    }

    private static void applyQuickBooksDataToRecord(SObject record, Map<String, Object> qbData, Map<String, String> mapping) {
        if (record == null || qbData == null || mapping == null) {
            return;
        }

        for (String qbField : mapping.keySet()) {
            Object qbValue = getNestedValue(qbData, qbField);
            if (qbValue != null) {
                try {
                    putFieldValue(record, mapping.get(qbField), qbValue);
                } catch (Exception e) {}
            }
        }
    }

    private static Object getNestedValue(Map<String, Object> data, String path) {
        String[] pathParts = path.split('\\.');
        Object current = data;

        for (String part : pathParts) {
            if (current instanceof Map<String, Object>) {
                current = ((Map<String, Object>)current).get(part);
            } else {
                return null;
            }
        }
        return current;
    }

    public static void putPath(Map<String, Object> root, String dottedPath, Object value) {
        if (root == null || String.isBlank(dottedPath)) {
            return;
        }
        if (!dottedPath.contains('.')) {
            root.put(dottedPath, value);
            return;
        }
        List<String> parts = dottedPath.split('\\.');
        Map<String, Object> current = root;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            String part = parts[i];
            if (!(current.get(part) instanceof Map<String, Object>)) {
                current.put(part, new Map<String, Object>());
            }
            current = (Map<String, Object>)current.get(part);
        }
        current.put(parts[parts.size() - 1], value);
    }

    public static String normalizeLineLeaf(String qboField) {
        String leaf = qboField;
        if (leaf.startsWith('Line.')) {
            leaf = leaf.substringAfter('Line.');
        }
        if (leaf.startsWith('SalesItemLineDetail.')) {
            leaf = leaf.substringAfter('SalesItemLineDetail.');
        }
        return leaf;
    }

    public static String getQuickBooksErrorMessage(HttpResponse response, String fallbackMessage) {
        if (response == null) {
            return fallbackMessage;
        }

        String body = response.getBody();
        if (String.isBlank(body)) {
            return fallbackMessage + ' HTTP ' + response.getStatusCode() + '.';
        }

        try {
            Map<String, Object> parsed = (Map<String, Object>)JSON.deserializeUntyped(body);
            if (parsed != null && parsed.containsKey('Fault')) {
                Map<String, Object> fault = (Map<String, Object>)parsed.get('Fault');
                List<Object> errors = fault == null ? null : (List<Object>)fault.get('Error');
                if (errors != null && !errors.isEmpty()) {
                    Map<String, Object> firstError = (Map<String, Object>)errors[0];
                    if (firstError.get('Detail') != null) {
                        return String.valueOf(firstError.get('Detail'));
                    }
                    if (firstError.get('Message') != null) {
                        return String.valueOf(firstError.get('Message'));
                    }
                }
            }
        } catch (Exception ex) {
            System.debug('Unable to parse QuickBooks error response: ' + ex.getMessage());
        }

        return fallbackMessage + ' HTTP ' + response.getStatusCode() + ': ' + body;
    }

    private static AuraHandledException buildActionException(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException)e;
        }
        return new AuraHandledException(e.getMessage());
    }
}
