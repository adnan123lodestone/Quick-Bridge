public class QuickBooksPurchaseOrderBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    
    private Set<Id> recordIds;
    private Boolean isInitialSync;
    private ConnectorExecutionResult sharedExecutionResult;
    private Set<Id> sharedSuccessfulRecordIds = new Set<Id>();
    private Set<Id> sharedFailedRecordIds = new Set<Id>();
    
    public QuickBooksPurchaseOrderBatch(Set<Id> recordIds, Boolean isInitialSync) {
        this.recordIds = recordIds;
        this.isInitialSync = isInitialSync;
    }

    public ConnectorExecutionResult executeSharedScope(List<SObject> scope) {
        sharedExecutionResult = ConnectorExecutionResult.success();
        sharedSuccessfulRecordIds.clear();
        sharedFailedRecordIds.clear();
        execute(null, scope);
        sharedExecutionResult.processedCount = scope == null ? 0 : scope.size();
        sharedExecutionResult.failedCount = sharedFailedRecordIds.size();
        sharedSuccessfulRecordIds.removeAll(sharedFailedRecordIds);
        sharedExecutionResult.successfulCount = sharedSuccessfulRecordIds.size();
        ConnectorExecutionResult result = sharedExecutionResult;
        sharedExecutionResult = null;
        return result;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String poObjName = Schema.getGlobalDescribe().containsKey('QuickBridgeTLG__Purchase_Order__c') ? 'QuickBridgeTLG__Purchase_Order__c' : 'Purchase_Order__c';
        String query = 'SELECT Id FROM ' + poObjName + ' WHERE Id IN :recordIds';
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            List<SObject> recordsToUpdate = new List<SObject>();

            Map<String, String> fieldMap = QBObjectMappings.getPurchaseOrderMapping();
            Map<String, String> lineFieldMap = QBObjectMappings.getPurchaseOrderLineMapping();
            
            Boolean isNamespaced = Schema.getGlobalDescribe().containsKey('QuickBridgeTLG__Purchase_Order__c');
            String ns = isNamespaced ? 'QuickBridgeTLG__' : '';
            String poObjName = ns + 'Purchase_Order__c';

            Set<String> normalizedFields = new Set<String>{ 'id', (ns + 'external_id__c').toLowerCase(), (ns + 'supplier__c').toLowerCase(), (ns + 'account__c').toLowerCase(), (ns + 'vendor__c').toLowerCase() };
            List<String> queryFields = new List<String>{ 'Id', ns + 'External_Id__c', ns + 'Supplier__c', ns + 'Account__c', ns + 'Vendor__c' };

            if (fieldMap != null) {
                for (String f : fieldMap.keySet()) {
                    if (String.isBlank(f)) continue;
                    String baseField = f.replace('QuickBridgeTLG__', '').toLowerCase();
                    String fullField = (ns + f.replace('QuickBridgeTLG__', '')).toLowerCase();
                    if (!normalizedFields.contains(baseField) && !normalizedFields.contains(fullField)) {
                        normalizedFields.add(baseField);
                        normalizedFields.add(fullField);
                        queryFields.add(f);
                    }
                }
            }

            String lineSubquery = isNamespaced ?
                '(SELECT Id, QuickBridgeTLG__Product__r.QuickBridgeTLG__QuickbookID__c, QuickBridgeTLG__Quantity__c, QuickBridgeTLG__Cost_Price__c, QuickBridgeTLG__Product_Description__c FROM QuickBridgeTLG__Purchase_Order_Lines__r)' :
                '(SELECT Id, Product__r.QuickbookID__c, Quantity__c, Cost_Price__c, Product_Description__c FROM Purchase_Order_Lines__r)';

            String supplierRel = isNamespaced ? 'QuickBridgeTLG__Supplier__r.QuickBridgeTLG__QuickbookID__c' : 'Supplier__r.QuickbookID__c';
            String accountRel = isNamespaced ? 'QuickBridgeTLG__Account__r.QuickBridgeTLG__QuickbookID__c' : 'Account__r.QuickbookID__c';
            String vendorRel = isNamespaced ? 'QuickBridgeTLG__Vendor__r.QuickBridgeTLG__QuickbookID__c' : 'Vendor__r.QuickbookID__c';

            String query = 'SELECT ' + String.join(queryFields, ', ') + 
                           ', ' + supplierRel + ', ' + accountRel + ', ' + vendorRel + ', ' +
                           lineSubquery +
                           ' FROM ' + poObjName + ' WHERE Id IN :recordIds';
            
            Map<Id, SObject> recordsWithItems = new Map<Id, SObject>((List<SObject>)Database.query(query));

            for (SObject obj : scope) {
                SObject currentRecord = recordsWithItems.get(obj.Id);
                List<SObject> childItems = new List<SObject>();
                if (currentRecord != null) {
                    if (currentRecord.getPopulatedFieldsAsMap().containsKey('Purchase_Order_Lines__r')) {
                        childItems = currentRecord.getSObjects('Purchase_Order_Lines__r');
                    } else if (currentRecord.getPopulatedFieldsAsMap().containsKey('QuickBridgeTLG__Purchase_Order_Lines__r')) {
                        childItems = currentRecord.getSObjects('QuickBridgeTLG__Purchase_Order_Lines__r');
                    }
                }
                
                if (currentRecord == null || childItems == null || childItems.isEmpty()) {
                    recordSharedFailure(obj == null ? null : obj.Id, 'Purchase order has no line items.', false);
                    continue;
                }
                
                String qbId = null;
                try { qbId = (String)currentRecord.get('External_Id__c'); } catch(Exception e){}
                if (qbId == null) {
                    try { qbId = (String)currentRecord.get('QuickBridgeTLG__External_Id__c'); } catch(Exception e){}
                }
                
                if (String.isBlank(qbId)) {
                    String newQbId = createPurchaseOrder(currentRecord, childItems, fieldMap, lineFieldMap);
                    if (newQbId != null) {
                        try { currentRecord.put('External_Id__c', newQbId); } catch(Exception e){}
                        try { currentRecord.put('QuickBridgeTLG__External_Id__c', newQbId); } catch(Exception e){}
                        recordsToUpdate.add(currentRecord);
                    }
                } else {
                    updatePurchaseOrder(currentRecord, childItems, fieldMap, qbId, lineFieldMap);
                    sharedSuccessfulRecordIds.add(currentRecord.Id);
                }
            }
            
            if (!recordsToUpdate.isEmpty()) {
                update recordsToUpdate;
                IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', recordsToUpdate.size());
                for (SObject updatedRecord : recordsToUpdate) {
                    sharedSuccessfulRecordIds.add(updatedRecord.Id);
                }
            }
            
        } catch(Exception e) {
            System.debug('Error in PurchaseOrder Batch: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            ErrorLogUtility.logException(
                'QuickBooks',
                'QuickBooksPurchaseOrderBatch.execute',
                e,
                'Purchase_Order__c',
                scope == null || scope.isEmpty() ? null : scope[0].Id
            );
            recordSharedFailure(
                scope == null || scope.isEmpty() ? null : scope[0].Id,
                e.getMessage(),
                IntegrationRetryPolicy.isRetryable(e)
            );
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('QuickBooksPurchaseOrderBatch completed.');
    }
    
    private String createPurchaseOrder(SObject record, List<SObject> lineItems, Map<String, String> fieldMap, Map<String, String> lineFieldMap) {
        Map<String, Object> requestBody = new Map<String, Object>();
        
        sObject vendorRef = null;
        try { vendorRef = record.getSObject('Supplier__r'); } catch(Exception e){}
        if(vendorRef == null) { try { vendorRef = record.getSObject('QuickBridgeTLG__Supplier__r'); } catch(Exception e){} }
        if(vendorRef == null) { try { vendorRef = record.getSObject('Vendor__r'); } catch(Exception e){} }
        if(vendorRef == null) { try { vendorRef = record.getSObject('QuickBridgeTLG__Vendor__r'); } catch(Exception e){} }
        if(vendorRef == null) { try { vendorRef = record.getSObject('Account__r'); } catch(Exception e){} }
        if(vendorRef == null) { try { vendorRef = record.getSObject('QuickBridgeTLG__Account__r'); } catch(Exception e){} }

        if (vendorRef != null) {
            String qbVendorId = null;
            try { qbVendorId = (String)vendorRef.get('QuickbookID__c'); } catch(Exception e){}
            if (qbVendorId == null) { try { qbVendorId = (String)vendorRef.get('QuickBridgeTLG__QuickbookID__c'); } catch(Exception e){} }
            if (qbVendorId != null) {
                requestBody.put('VendorRef', new Map<String, String>{ 'value' => qbVendorId });
            }
        }
        
        applyDynamicMappings(requestBody, record, fieldMap);
        requestBody.put('Line', buildLineItems(lineItems, record, lineFieldMap));

        String requestJson = JSON.serialize(requestBody);
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/purchaseorder', requestJson);
        
        if (res != null && res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(res.getBody())).get('PurchaseOrder');
            String newQbId = (String)responseMap.get('Id');
            List<Object> qboLines = (List<Object>)responseMap.get('Line');
            List<SObject> lineItemsToUpdate = updateLineItemsWithExternalIds(lineItems, qboLines, newQbId);
            if (!lineItemsToUpdate.isEmpty()) {
                update lineItemsToUpdate;
            }
            return newQbId;
        }
        ErrorLogUtility.logCalloutFailure(
            'QuickBooks',
            'QuickBooksPurchaseOrderBatch.createPurchaseOrder',
            'QuickBooks purchase order create failed: ' + (res == null ? 'Null Response' : res.getBody()),
            res == null ? null : res.getStatusCode(),
            'Purchase_Order__c',
            record == null ? null : record.Id
        );
        throw IntegrationRetryPolicy.exceptionForStatus(
            res == null ? null : res.getStatusCode(),
            'QuickBooks purchase order create failed: ' + (res == null ? 'Null Response' : res.getBody())
        );
    }
    
    private void updatePurchaseOrder(SObject record, List<SObject> lineItems, Map<String, String> fieldMap, String qbId, Map<String, String> lineFieldMap) {
        HttpResponse getRes = QuickBooksAuthHandler.makeApiCall('GET', '/purchaseorder/' + qbId, null);
        if (getRes == null || getRes.getStatusCode() != 200) {
            ErrorLogUtility.logCalloutFailure(
                'QuickBooks',
                'QuickBooksPurchaseOrderBatch.updatePurchaseOrder.getPurchaseOrder',
                'QuickBooks purchase order query failed: ' + (getRes == null ? 'Null Response' : getRes.getBody()),
                getRes == null ? null : getRes.getStatusCode(),
                'Purchase_Order__c',
                record == null ? null : record.Id
            );
            throw IntegrationRetryPolicy.exceptionForStatus(
                getRes == null ? null : getRes.getStatusCode(),
                'QuickBooks purchase order query failed: ' + (getRes == null ? 'Null Response' : getRes.getBody())
            );
        }
        
        Map<String, Object> existingPO = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(getRes.getBody())).get('PurchaseOrder');
        
        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('Id', qbId);
        requestBody.put('SyncToken', existingPO.get('SyncToken'));
        requestBody.put('sparse', true); 
        
        sObject vendorRef = null;
        try { vendorRef = record.getSObject('Supplier__r'); } catch(Exception e){}
        if(vendorRef == null) { try { vendorRef = record.getSObject('QuickBridgeTLG__Supplier__r'); } catch(Exception e){} }
        if(vendorRef == null) { try { vendorRef = record.getSObject('Vendor__r'); } catch(Exception e){} }
        if(vendorRef == null) { try { vendorRef = record.getSObject('QuickBridgeTLG__Vendor__r'); } catch(Exception e){} }
        if(vendorRef == null) { try { vendorRef = record.getSObject('Account__r'); } catch(Exception e){} }
        if(vendorRef == null) { try { vendorRef = record.getSObject('QuickBridgeTLG__Account__r'); } catch(Exception e){} }

        if (vendorRef != null) {
            String qbVendorId = null;
            try { qbVendorId = (String)vendorRef.get('QuickbookID__c'); } catch(Exception e){}
            if (qbVendorId == null) { try { qbVendorId = (String)vendorRef.get('QuickBridgeTLG__QuickbookID__c'); } catch(Exception e){} }
            if (qbVendorId != null) {
                requestBody.put('VendorRef', new Map<String, String>{ 'value' => qbVendorId });
            }
        }

        applyDynamicMappings(requestBody, record, fieldMap);
        requestBody.put('Line', buildLineItems(lineItems, record, lineFieldMap));

        String requestJson = JSON.serialize(requestBody);
        HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/purchaseorder', requestJson);
        if (updateRes != null && updateRes.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(updateRes.getBody())).get('PurchaseOrder');
            List<Object> qboLines = (List<Object>)responseMap.get('Line');
            List<SObject> lineItemsToUpdate = updateLineItemsWithExternalIds(lineItems, qboLines, qbId);
            if (!lineItemsToUpdate.isEmpty()) {
                update lineItemsToUpdate;
            }
        } else {
            ErrorLogUtility.logCalloutFailure(
                'QuickBooks',
                'QuickBooksPurchaseOrderBatch.updatePurchaseOrder',
                'QuickBooks purchase order update failed: ' + (updateRes == null ? 'Null Response' : updateRes.getBody()),
                updateRes == null ? null : updateRes.getStatusCode(),
                'Purchase_Order__c',
                record == null ? null : record.Id
            );
            throw IntegrationRetryPolicy.exceptionForStatus(
                updateRes == null ? null : updateRes.getStatusCode(),
                'QuickBooks purchase order update failed: ' + (updateRes == null ? 'Null Response' : updateRes.getBody())
            );
        }
    }

    private void recordSharedFailure(Id recordId, String message, Boolean retryable) {
        if (sharedExecutionResult == null) {
            return;
        }
        if (recordId != null) {
            sharedFailedRecordIds.add(recordId);
        }
        sharedExecutionResult.addError(message);
        if (retryable == true) {
            sharedExecutionResult.retryable = true;
            sharedExecutionResult.retryDelaySeconds = 60;
            if (recordId != null && !sharedExecutionResult.retryRecordIds.contains(recordId)) {
                sharedExecutionResult.retryRecordIds.add(recordId);
            }
        }
    }
    
    private void applyDynamicMappings(Map<String, Object> requestBody, SObject record, Map<String, String> fieldMap) {
        if(fieldMap == null) return;
        for (String sfField : fieldMap.keySet()) {
            String qbField = fieldMap.get(sfField);
            String topKey = qbField.contains('.') ? qbField.substringBefore('.') : qbField;
            if (topKey.equalsIgnoreCase('ExternalId') || topKey.equalsIgnoreCase('Id')) continue;
            if (requestBody.containsKey(topKey)) continue;

            Object value = null;
            try { value = record.get(sfField); } catch(Exception e) {}

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
    
    private List<Map<String, Object>> buildLineItems(List<SObject> lineItems, SObject record, Map<String, String> lineFieldMap) {
        List<Map<String, Object>> qbLines = new List<Map<String, Object>>();
        if (lineItems == null) return qbLines;

        sObject customerRef = null;
        try { customerRef = record.getSObject('Account__r'); } catch(Exception e){}
        if(customerRef == null) { try { customerRef = record.getSObject('QuickBridgeTLG__Account__r'); } catch(Exception e){} }

        String customerQbId = null;
        if(customerRef != null) {
            try { customerQbId = (String)customerRef.get('QuickbookID__c'); } catch(Exception e){}
            if(customerQbId == null) { try { customerQbId = (String)customerRef.get('QuickBridgeTLG__QuickbookID__c'); } catch(Exception e){} }
        }

        String qtyField = fieldKeyFor(lineFieldMap, 'Line.ItemBasedExpenseLineDetail.Qty', 'Quantity__c');
        String rateField = fieldKeyFor(lineFieldMap, 'Line.ItemBasedExpenseLineDetail.UnitPrice', 'Cost_Price__c');
        String descField = fieldKeyFor(lineFieldMap, 'Line.Description', 'Product_Description__c');

        for (SObject item : lineItems) {
            Decimal quantity = 0;
            Decimal rate = 0;
            try { quantity = (Decimal)item.get(qtyField); } catch(Exception e){}
            if (quantity == null || quantity == 0) { try { quantity = (Decimal)item.get('QuickBridgeTLG__Quantity__c'); } catch(Exception e){} }

            try { rate = (Decimal)item.get(rateField); } catch(Exception e){}
            if (rate == null || rate == 0) { try { rate = (Decimal)item.get('QuickBridgeTLG__Cost_Price__c'); } catch(Exception e){} }

            Decimal lineAmount = (quantity != null && rate != null) ? (quantity * rate) : 0;

            String descText = '';
            try { descText = (String)item.get(descField); } catch(Exception e){}
            if (String.isBlank(descText)) { try { descText = (String)item.get('QuickBridgeTLG__Product_Description__c'); } catch(Exception e){} }

            SObject product = null;
            try { product = item.getSObject('Product__r'); } catch(Exception e){}
            if (product == null) { try { product = item.getSObject('QuickBridgeTLG__Product__r'); } catch(Exception e){} }

            String productQbId = null;
            if (product != null) {
                try { productQbId = (String)product.get('QuickbookID__c'); } catch(Exception e){}
                if (productQbId == null) { try { productQbId = (String)product.get('QuickBridgeTLG__QuickbookID__c'); } catch(Exception e){} }
            }

            Map<String, Object> lineDetail = new Map<String, Object>{
                'DetailType' => 'ItemBasedExpenseLineDetail',
                'Amount' => lineAmount,
                'Description' => descText,
                'ItemBasedExpenseLineDetail' => new Map<String, Object>{
                    'Qty' => quantity,
                    'UnitPrice' => rate
                }
            };

            if(productQbId != null) {
                ((Map<String, Object>)lineDetail.get('ItemBasedExpenseLineDetail')).put('ItemRef', new Map<String, String>{
                    'value' => productQbId
                });
            }

            if(customerQbId != null) {
                ((Map<String, Object>)lineDetail.get('ItemBasedExpenseLineDetail')).put('CustomerRef', new Map<String, String>{
                    'value' => customerQbId
                });
            }

            qbLines.add(lineDetail);
        }
        return qbLines;
    }

    private static String fieldKeyFor(Map<String, String> fieldMap, String qbPath, String defaultSfField) {
        if (fieldMap == null) return defaultSfField;
        for (String sf : fieldMap.keySet()) {
            if (fieldMap.get(sf) == qbPath) return sf;
        }
        return defaultSfField;
    }

    private static List<SObject> updateLineItemsWithExternalIds(List<SObject> lineItems, List<Object> linesObj, String parentQbId) {
        List<SObject> itemsToUpdate = new List<SObject>();
        if (linesObj == null || lineItems == null) return itemsToUpdate;

        Integer qboLineIndex = 0;
        for (SObject item : lineItems) {
            while (qboLineIndex < linesObj.size()) {
                Map<String, Object> qbLine = (Map<String, Object>)linesObj[qboLineIndex];
                String detailType = (String)qbLine.get('DetailType');
                if (detailType == 'ItemBasedExpenseLineDetail' || detailType == 'SalesItemLineDetail' || detailType == 'GroupLineDetail') {
                    String lineId = (String)qbLine.get('Id');
                    String compositeLineId = String.isNotBlank(parentQbId) ? (parentQbId + '_' + lineId) : lineId;
                    
                    SObject itemToUpdate = item.Id.getSObjectType().newSObject(item.Id);
                    Schema.SObjectType sot = item.Id.getSObjectType();
                    Map<String, Schema.SObjectField> fields = sot.getDescribe().fields.getMap();
                    
                    String extIdField = fields.containsKey('quickbridgetlg__external_id__c') ? 'QuickBridgeTLG__External_Id__c' : 'External_Id__c';
                    itemToUpdate.put(extIdField, compositeLineId);
                    
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