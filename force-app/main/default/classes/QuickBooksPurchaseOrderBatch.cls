public class QuickBooksPurchaseOrderBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    
    private Set<Id> recordIds;
    private Boolean isInitialSync;
    
    public QuickBooksPurchaseOrderBatch(Set<Id> recordIds, Boolean isInitialSync) {
        this.recordIds = recordIds;
        this.isInitialSync = isInitialSync;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id FROM Purchase_Order__c WHERE Id IN :recordIds';
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        IntegrationUsageService.assertCanConsumeTask('QuickBooks', scope == null ? 1 : scope.size());
        try {
            List<SObject> recordsToUpdate = new List<SObject>();

            Map<String, String> fieldMap = QBObjectMappings.getPurchaseOrderMapping();
            Map<String, String> lineFieldMap = QBObjectMappings.getPurchaseOrderLineMapping();
            
            Set<String> fieldsToQuery = new Set<String>{'Id', 'External_Id__c', 'Supplier__c', 'Account__c'};
            fieldsToQuery.addAll(fieldMap.keySet());
            
            List<String> queryFields = new List<String>(fieldsToQuery);
            
            String query = 'SELECT ' + String.join(queryFields, ', ') + 
                           ', Supplier__r.QuickbookID__c, Account__r.QuickbookID__c, ' +
                           '(SELECT Id, Product__r.QuickbookID__c, Quantity__c, Cost_Price__c, Product_Description__c FROM Purchase_Order_Lines__r) ' +
                           'FROM Purchase_Order__c WHERE Id IN :recordIds';
            
            Map<Id, SObject> recordsWithItems = new Map<Id, SObject>((List<SObject>)Database.query(query));
            Map<String, Map<String, Object>> existingPurchaseOrdersById = new Map<String, Map<String, Object>>();
            if (!isInitialSync) {
                Set<String> purchaseOrderIdsToUpdate = new Set<String>();
                for (SObject obj : scope) {
                    SObject currentRecord = recordsWithItems.get(obj.Id);
                    if (currentRecord == null) continue;
                    String qbId = (String)currentRecord.get('External_Id__c');
                    if (String.isNotBlank(qbId)) {
                        purchaseOrderIdsToUpdate.add(qbId);
                    }
                }
                existingPurchaseOrdersById = QuickBooksBulkQueryService.queryByIdsMap('PurchaseOrder', purchaseOrderIdsToUpdate);
            }

            for (SObject obj : scope) {
                SObject currentRecord = recordsWithItems.get(obj.Id);
                if (currentRecord == null) continue;
                List<SObject> childItems = currentRecord.getSObjects('Purchase_Order_Lines__r');
                
                if (childItems == null || childItems.isEmpty()) continue;
                
                String qbId = (String)currentRecord.get('External_Id__c');
                
                if (qbId == null && isInitialSync) {
                    String newQbId = createPurchaseOrder(currentRecord, childItems, fieldMap, lineFieldMap);
                    if (newQbId != null) {
                        currentRecord.put('External_Id__c', newQbId);
                        recordsToUpdate.add(currentRecord);
                    }
                } else if (qbId != null && !isInitialSync) {
                    updatePurchaseOrder(
                        currentRecord,
                        childItems,
                        fieldMap,
                        qbId,
                        lineFieldMap,
                        existingPurchaseOrdersById.get(qbId)
                    );
                }
            }
            
            if (!recordsToUpdate.isEmpty()) {
                update recordsToUpdate;
                IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', recordsToUpdate.size());
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
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('QuickBooksPurchaseOrderBatch completed.');
    }
    
    private String createPurchaseOrder(SObject record, List<SObject> lineItems, Map<String, String> fieldMap, Map<String, String> lineFieldMap) {
        Map<String, Object> requestBody = new Map<String, Object>();
        
        SObject vendorRef = record.getSObject('Supplier__r');
        if (vendorRef != null && vendorRef.get('QuickbookID__c') != null) {
            requestBody.put('VendorRef', new Map<String, String>{ 'value' => (String)vendorRef.get('QuickbookID__c') });
        }
        
        applyDynamicMappings(requestBody, record, fieldMap);
        requestBody.put('Line', buildLineItems(lineItems, record, lineFieldMap));

        String requestJson = JSON.serialize(requestBody);
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/purchaseorder', requestJson);
        
        if (res != null && res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(res.getBody())).get('PurchaseOrder');
            return (String)responseMap.get('Id');
        }
        ErrorLogUtility.logCalloutFailure(
            'QuickBooks',
            'QuickBooksPurchaseOrderBatch.createPurchaseOrder',
            'QuickBooks purchase order create failed: ' + (res == null ? 'Null Response' : res.getBody()),
            res == null ? null : res.getStatusCode(),
            'Purchase_Order__c',
            record == null ? null : record.Id
        );
        return null;
    }
    
    private void updatePurchaseOrder(
        SObject record,
        List<SObject> lineItems,
        Map<String, String> fieldMap,
        String qbId,
        Map<String, String> lineFieldMap,
        Map<String, Object> existingPO
    ) {
        if (existingPO == null) {
            ErrorLogUtility.logCalloutFailure(
                'QuickBooks',
                'QuickBooksPurchaseOrderBatch.updatePurchaseOrder.queryPurchaseOrder',
                'QuickBooks purchase order query returned no record for Id ' + qbId,
                null,
                'Purchase_Order__c',
                record == null ? null : record.Id
            );
            return;
        }
        
        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('Id', qbId);
        requestBody.put('SyncToken', existingPO.get('SyncToken'));
        requestBody.put('sparse', true); 
        
        applyDynamicMappings(requestBody, record, fieldMap);
        requestBody.put('Line', buildLineItems(lineItems, record, lineFieldMap));

        String requestJson = JSON.serialize(requestBody);
        HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/purchaseorder', requestJson);
        if (updateRes == null || updateRes.getStatusCode() != 200) {
            ErrorLogUtility.logCalloutFailure(
                'QuickBooks',
                'QuickBooksPurchaseOrderBatch.updatePurchaseOrder',
                'QuickBooks purchase order update failed: ' + (updateRes == null ? 'Null Response' : updateRes.getBody()),
                updateRes == null ? null : updateRes.getStatusCode(),
                'Purchase_Order__c',
                record == null ? null : record.Id
            );
        }
    }

    private void applyDynamicMappings(Map<String, Object> requestBody, SObject record, Map<String, String> fieldMap) {
        for (String sfField : fieldMap.keySet()) {
            String qbField = fieldMap.get(sfField);
            // Skip if the top-level QB key is already set (e.g. VendorRef already resolved via relationship)
            String topKey = qbField.contains('.') ? qbField.substringBefore('.') : qbField;
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

        SObject customerRef = record.getSObject('Account__r');
        String customerQbId = (customerRef != null) ? (String)customerRef.get('QuickbookID__c') : null;

        String qtyField = fieldKeyFor(lineFieldMap, 'Line.ItemBasedExpenseLineDetail.Qty', 'Quantity__c');
        String rateField = fieldKeyFor(lineFieldMap, 'Line.ItemBasedExpenseLineDetail.UnitPrice', 'Cost_Price__c');
        String descField = fieldKeyFor(lineFieldMap, 'Line.Description', 'Product_Description__c');

        for (SObject item : lineItems) {
            Decimal quantity = 0;
            Decimal rate = 0;
            try { quantity = (Decimal)item.get(qtyField); } catch(Exception e){}
            try { rate = (Decimal)item.get(rateField); } catch(Exception e){}
            Decimal lineAmount = (quantity != null && rate != null) ? (quantity * rate) : 0;

            String descText = '';
            try { descText = (String)item.get(descField); } catch(Exception e){}

            SObject product = null;
            try { product = item.getSObject('Product__r'); } catch(Exception e){}
            String productQbId = product != null ? (String)product.get('QuickbookID__c') : null;

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
}
