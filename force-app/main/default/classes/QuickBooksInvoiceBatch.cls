public class QuickBooksInvoiceBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {

    private Set<Id> recordIds;
    private Boolean isInitialSync;
    private Map<Id, SObject> triggerItemsMap;

    public QuickBooksInvoiceBatch(Set<Id> recordIds, Boolean isInitialSync) {
        this.recordIds = recordIds;
        this.isInitialSync = isInitialSync;
        this.triggerItemsMap = new Map<Id, SObject>();
    }

    public QuickBooksInvoiceBatch(Set<Id> recordIds, Boolean isInitialSync, List<SObject> triggerItems) {
        this.recordIds = recordIds;
        this.isInitialSync = isInitialSync;
        this.triggerItemsMap = new Map<Id, SObject>();
        if (triggerItems != null) {
            for (SObject item : triggerItems) {
                this.triggerItemsMap.put(item.Id, item);
            }
        }
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String mappedObject = QBObjectMappings.getInvoiceSourceObject();
        String query = 'SELECT Id FROM ' + mappedObject + ' WHERE Id IN :recordIds';
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        QuickBooksInvoiceHandler.setBatchContext(true);

        try {
            List<SObject> recordsToUpdate = new List<SObject>();
            List<SObject> itemsToUpdate = new List<SObject>();

            String mappedObject = QBObjectMappings.getInvoiceSourceObject();
            String mappedLineObject = QBObjectMappings.getInvoiceLineItemObject(mappedObject);
            Map<String, String> fieldMap = QBObjectMappings.getSmartInvoiceMapping();
            Set<String> fieldsToQuery = new Set<String>{'Id', 'QuickBridgeTLG__External_Id__c', 'QuickBridgeTLG__Related_Account__c'};

            fieldsToQuery.add('QuickBridgeTLG__Related_Account__r.QuickBridgeTLG__QuickbookID__c');

            for(String f : fieldMap.keySet()){
                if(!fieldsToQuery.contains(f)) fieldsToQuery.add(f);
            }

            List<String> queryFields = new List<String>(fieldsToQuery);
            String childRelationship = 'QuickBridgeTLG__Invoice_Lines__r'; // Custom Object child relation

            String query = 'SELECT ' + String.join(queryFields, ', ') +
               ', (SELECT Id, QuickBridgeTLG__Product__r.QuickBridgeTLG__QuickbookID__c, QuickBridgeTLG__Product__r.Name, QuickBridgeTLG__Quantity__c, QuickBridgeTLG__Unit_Price__c, QuickBridgeTLG__Product_Description__c ' +
               'FROM ' + childRelationship + ') ' +
               'FROM ' + mappedObject + ' WHERE Id IN :recordIds';

            Map<Id, SObject> recordsWithItems = new Map<Id, SObject>((List<SObject>)Database.query(query));

            for (SObject obj : scope) {
                SObject currentRecord = recordsWithItems.get(obj.Id);
                if (currentRecord == null) continue;

                List<SObject> childItems = currentRecord.getSObjects(childRelationship);
                if (childItems == null || childItems.isEmpty()) continue;

                String qbId = (String)currentRecord.get('QuickBridgeTLG__External_Id__c');

                if (qbId == null) {
                    Map<String, Object> result = createInvoice(currentRecord, childItems, fieldMap);
                    if (result != null) {
                        String newQbId = (String)result.get('invoiceId');
                        currentRecord.put('QuickBridgeTLG__External_Id__c', newQbId);
                        recordsToUpdate.add(currentRecord);
                        itemsToUpdate.addAll(updateLineItemsWithExternalIds(childItems, result, newQbId));
                    }
                } else if (qbId != null && !isInitialSync) {
                    Map<String, Object> result = updateInvoice(currentRecord, childItems, fieldMap);
                    if (result != null) {
                        itemsToUpdate.addAll(updateLineItemsWithExternalIds(childItems, result, qbId));
                    }
                }
            }

            if (!recordsToUpdate.isEmpty()) {
                update recordsToUpdate;
                IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', recordsToUpdate.size());
            }
            if (!itemsToUpdate.isEmpty()) update itemsToUpdate;

        } catch(Exception e) {
            System.debug('Error in Invoice Batch: ' + e.getMessage());
            ErrorLogUtility.logException(
                'QuickBooks',
                'QuickBooksInvoiceBatch.execute',
                e,
                'Invoice__c',
                scope == null || scope.isEmpty() ? null : scope[0].Id
            );
        } finally {
            QuickBooksInvoiceHandler.setBatchContext(false);
        }
    }

    public void finish(Database.BatchableContext bc) {}

    @TestVisible
    private Map<String, Object> createInvoice(SObject record, List<SObject> lineItems, Map<String, String> fieldMap) {
        Map<String, Object> requestBody = new Map<String, Object>();

        String customerRefId = getCustomerRefId(record);
        if(String.isNotBlank(customerRefId)) {
            requestBody.put('CustomerRef', new Map<String, String>{ 'value' => customerRefId });
        }

        applyDynamicMappings(requestBody, record, fieldMap);
        requestBody.put('Line', buildLineItems(lineItems));

        String requestJson = JSON.serialize(requestBody);
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/invoice', requestJson);

        if (res != null && res.getStatusCode() == 200) {
            Map<String, Object> invoiceMap = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(res.getBody())).get('Invoice');
            return new Map<String, Object>{ 'invoiceId' => invoiceMap.get('Id'), 'lines' => invoiceMap.get('Line') };
        }
        ErrorLogUtility.logCalloutFailure(
            'QuickBooks',
            'QuickBooksInvoiceBatch.createInvoice',
            'QuickBooks invoice create failed: ' + (res == null ? 'Null Response' : res.getBody()),
            res == null ? null : res.getStatusCode(),
            'Invoice__c',
            record == null ? null : record.Id
        );
        return null;
    }

    @TestVisible
    private Map<String, Object> updateInvoice(SObject record, List<SObject> lineItems, Map<String, String> fieldMap) {
        String qbId = (String)record.get('QuickBridgeTLG__External_Id__c');
        HttpResponse getRes = QuickBooksAuthHandler.makeApiCall('GET', '/invoice/' + qbId, null);
        if (getRes == null || getRes.getStatusCode() != 200) {
            ErrorLogUtility.logCalloutFailure(
                'QuickBooks',
                'QuickBooksInvoiceBatch.updateInvoice.getInvoice',
                'QuickBooks invoice query failed: ' + (getRes == null ? 'Null Response' : getRes.getBody()),
                getRes == null ? null : getRes.getStatusCode(),
                'Invoice__c',
                record == null ? null : record.Id
            );
            return null;
        }

        Map<String, Object> existingInvoice = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(getRes.getBody())).get('Invoice');

        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('Id', qbId);
        requestBody.put('SyncToken', existingInvoice.get('SyncToken'));
        requestBody.put('sparse', true);

        applyDynamicMappings(requestBody, record, fieldMap);
        requestBody.put('Line', buildLineItems(lineItems));

        String requestJson = JSON.serialize(requestBody);
        HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/invoice', requestJson);

        if (updateRes != null && updateRes.getStatusCode() == 200) {
            Map<String, Object> invoiceMap = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(updateRes.getBody())).get('Invoice');
            return new Map<String, Object>{ 'invoiceId' => invoiceMap.get('Id'), 'lines' => invoiceMap.get('Line') };
        }
        ErrorLogUtility.logCalloutFailure(
            'QuickBooks',
            'QuickBooksInvoiceBatch.updateInvoice',
            'QuickBooks invoice update failed: ' + (updateRes == null ? 'Null Response' : updateRes.getBody()),
            updateRes == null ? null : updateRes.getStatusCode(),
            'Invoice__c',
            record == null ? null : record.Id
        );
        return null;
    }

    @TestVisible
    private void applyDynamicMappings(Map<String, Object> requestBody, SObject record, Map<String, String> fieldMap) {
        for (String sfField : fieldMap.keySet()) {
            String qbField = fieldMap.get(sfField);
            Object value = getFieldValue(record, sfField);

            if (value != null) {
                if (value instanceof Date) {
                    value = DateTime.newInstance((Date)value, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
                }

                if (qbField.contains('.')) {
                    List<String> path = qbField.split('\\.');
                    Map<String, Object> currentMap = requestBody;
                    for (Integer i = 0; i < path.size() - 1; i++) {
                        String part = path[i];
                        if (!currentMap.containsKey(part)) currentMap.put(part, new Map<String, Object>());
                        currentMap = (Map<String, Object>)currentMap.get(part);
                    }
                    currentMap.put(path[path.size() - 1], value);
                } else {
                    requestBody.put(qbField, value);
                }
            }
        }
    }

    @TestVisible
    private List<Map<String, Object>> buildLineItems(List<SObject> lineItems) {
        List<Map<String, Object>> qbLines = new List<Map<String, Object>>();
        Decimal totalAmount = 0;

        for (SObject item : lineItems) {
            // Updated to custom fields
            Decimal quantity = 0;
            Decimal unitPrice = 0;
            try { quantity = (Decimal)item.get('QuickBridgeTLG__Quantity__c'); } catch(Exception e){}
            try { unitPrice = (Decimal)item.get('QuickBridgeTLG__Unit_Price__c'); } catch(Exception e){}

            if(quantity == null) quantity = 0;
            if(unitPrice == null) unitPrice = 0;

            Decimal lineAmount = quantity * unitPrice;
            totalAmount += lineAmount;

            SObject product = null;
            try { product = item.getSObject('QuickBridgeTLG__Product__r'); } catch(Exception e){}

            String productQbId = null;
            String productName = null;

            if(product != null) {
                try { productQbId = (String)product.get('QuickBridgeTLG__QuickbookID__c'); } catch(Exception e){}
                try { productName = (String)product.get('Name'); } catch(Exception e){}
            }

            if(productQbId != null) {
                Map<String, Object> lineDetail = new Map<String, Object>{
                    'DetailType' => 'SalesItemLineDetail',
                    'Amount' => lineAmount,
                    'SalesItemLineDetail' => new Map<String, Object>{
                        'Qty' => quantity,
                        'UnitPrice' => unitPrice,
                        'ItemRef' => new Map<String, String>{
                            'value' => productQbId,
                            'name' => productName
                        }
                    }
                };
                qbLines.add(lineDetail);
            }
        }
        qbLines.add(new Map<String, Object>{ 'DetailType' => 'SubTotalLineDetail', 'Amount' => totalAmount });
        return qbLines;
    }

    private static String getCustomerRefId(SObject record) {
    try {
        SObject accountRecord = record.getSObject('QuickBridgeTLG__Related_Account__r');
        if(accountRecord != null) return (String)accountRecord.get('QuickBridgeTLG__QuickbookID__c');
    } catch(Exception e) {}
    return null;
}

    @TestVisible
    private static Object getFieldValue(SObject obj, String fieldPath) {
        if (obj == null || String.isBlank(fieldPath)) {
            return null;
        }
        if(!fieldPath.contains('.')) {
            try { return obj.get(fieldPath); } catch(Exception e) { return null; }
        }
        
        List<String> fields = fieldPath.split('\\.');
        SObject currentObj = obj;
        try {
            for (Integer i = 0; i < fields.size() - 1; i++) {
                currentObj = currentObj.getSObject(fields[i]);
                if (currentObj == null) return null;
            }
            return currentObj.get(fields[fields.size() - 1]);
        } catch (Exception e) {
            return null;
        }
    }

    private static List<SObject> updateLineItemsWithExternalIds(List<SObject> lineItems, Map<String, Object> qbResult, String invoiceQbId) {
        List<SObject> itemsToUpdate = new List<SObject>();
        List<Object> linesObj = (List<Object>)qbResult.get('lines');
        if (linesObj == null || lineItems == null) return itemsToUpdate;

        Integer qboLineIndex = 0;
        for (SObject item : lineItems) {
            while (qboLineIndex < linesObj.size()) {
                Map<String, Object> qbLine = (Map<String, Object>)linesObj[qboLineIndex];
                if (qbLine.get('DetailType') == 'SalesItemLineDetail') {
                    String lineId = (String)qbLine.get('Id');
                    
                    SObject itemToUpdate = item.Id.getSObjectType().newSObject(item.Id);
                    
                    Schema.SObjectType sot = item.Id.getSObjectType();
                    Map<String, Schema.SObjectField> fields = sot.getDescribe().fields.getMap();
                    
                    String extIdField = fields.containsKey('QuickBridgeTLG__external_id__c') ? 'QuickBridgeTLG__External_Id__c' : 'External_Id__c';
                    String invExtIdField = fields.containsKey('QuickBridgeTLG__invoice_external_id__c') ? 'QuickBridgeTLG__Invoice_External_Id__c' : 'Invoice_External_Id__c';
                    
                    itemToUpdate.put(extIdField, lineId);
                    itemToUpdate.put(invExtIdField, invoiceQbId);
                    
                    itemsToUpdate.add(itemToUpdate);
                    qboLineIndex++;
                    break;
                }
                qboLineIndex++;
            }
        }
        return itemsToUpdate;
    }
}
