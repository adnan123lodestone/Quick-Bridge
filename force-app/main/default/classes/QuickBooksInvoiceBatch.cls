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
        // String mappedObject = QBObjectMappings.getInvoiceSourceObject();
        String query = 'SELECT Id FROM QuickBridgeTLG__Invoice__c WHERE Id IN :recordIds';
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        IntegrationUsageService.assertCanConsumeTask('QuickBooks', scope == null ? 1 : scope.size());
        QuickBooksInvoiceHandler.setBatchContext(true);

        try {
            List<SObject> recordsToUpdate = new List<SObject>();
            List<SObject> itemsToUpdate = new List<SObject>();

            // String mappedObject = QBObjectMappings.getInvoiceSourceObject();
            // String mappedLineObject = QBObjectMappings.getInvoiceLineItemObject(mappedObject);
            String mappedObject = 'QuickBridgeTLG__Invoice__c';
            String mappedLineObject = 'QuickBridgeTLG__Invoice_Line__c';
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
                        currentRecord.put('QuickBridgeTLG__External_Id__c', (String)result.get('invoiceId'));
                        recordsToUpdate.add(currentRecord);
                    }
                } else if (qbId != null && !isInitialSync) {
                    Map<String, Object> result = updateInvoice(currentRecord, childItems, fieldMap);
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

    private Map<String, Object> createInvoice(SObject record, List<SObject> lineItems, Map<String, String> fieldMap) {
        Map<String, Object> requestBody = new Map<String, Object>();

        String customerRefId = getCustomerRefId(record);
        if(String.isNotBlank(customerRefId)) {
            requestBody.put('CustomerRef', new Map<String, String>{ 'value' => customerRefId });
        }

        applyDynamicMappings(requestBody, record, fieldMap);
        requestBody.put('Line', buildLineItems(lineItems));

        String requestJson = JSON.serialize(requestBody);
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/invoice?minorversion=65', requestJson);

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

    private Map<String, Object> updateInvoice(SObject record, List<SObject> lineItems, Map<String, String> fieldMap) {
        String qbId = (String)record.get('QuickBridgeTLG__External_Id__c');
        HttpResponse getRes = QuickBooksAuthHandler.makeApiCall('GET', '/invoice/' + qbId + '?minorversion=65', null);
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
        HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/invoice?minorversion=65', requestJson);

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

    private static Object getFieldValue(SObject obj, String fieldPath) {
        if(!fieldPath.contains('.')) {
            try { return obj.get(fieldPath); } catch(Exception e) { return null; }
        }
        List<String> fields = fieldPath.split('\\.');
        SObject currentObj = obj;
        for (Integer i = 0; i < fields.size() - 1; i++) {
            currentObj = currentObj.getSObject(fields[i]);
            if (currentObj == null) return null;
        }
        return currentObj.get(fields[fields.size() - 1]);
    }
}
// public class QuickBooksInvoiceBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {

//     private Set<Id> recordIds;
//     private Boolean isInitialSync;
//     private Map<Id, SObject> triggerItemsMap;

//     public QuickBooksInvoiceBatch(Set<Id> recordIds, Boolean isInitialSync) {
//         this.recordIds = recordIds;
//         this.isInitialSync = isInitialSync;
//         this.triggerItemsMap = new Map<Id, SObject>();
//     }

//     public QuickBooksInvoiceBatch(Set<Id> recordIds, Boolean isInitialSync, List<SObject> triggerItems) {
//         this.recordIds = recordIds;
//         this.isInitialSync = isInitialSync;
//         this.triggerItemsMap = new Map<Id, SObject>();
//         if (triggerItems != null) {
//             for (SObject item : triggerItems) {
//                 this.triggerItemsMap.put(item.Id, item);
//             }
//         }
//     }

//     public Database.QueryLocator start(Database.BatchableContext bc) {
//         String mappedObject = QBObjectMappings.getInvoiceSourceObject();
//         String query = 'SELECT Id FROM ' + mappedObject + ' WHERE Id IN :recordIds';
//         return Database.getQueryLocator(query);
//     }

//     public void execute(Database.BatchableContext bc, List<SObject> scope) {
//         QuickBooksInvoiceHandler.setBatchContext(true);

//         try {
//             List<SObject> recordsToUpdate = new List<SObject>();
//             List<SObject> itemsToUpdate = new List<SObject>();

//             String mappedObject = QBObjectMappings.getInvoiceSourceObject();
//             String mappedLineObject = QBObjectMappings.getInvoiceLineItemObject(mappedObject);

//             Map<String, String> fieldMap = QBObjectMappings.getSmartInvoiceMapping();
//             Set<String> fieldsToQuery = new Set<String>{'Id', 'QuickbookID__c'};

//             if(mappedObject == 'Order') {
//                 fieldsToQuery.add('Account.QuickbookID__c');
//             }
//             fieldsToQuery.addAll(fieldMap.keySet());

//             List<String> queryFields = new List<String>(fieldsToQuery);
//             String childRelationship = 'OrderItems'; // Default for Order
//             if (mappedObject != 'Order') {
//                 Schema.DescribeSObjectResult describeResult = Schema.getGlobalDescribe().get(mappedObject).getDescribe();
//                 for (Schema.ChildRelationship cr : describeResult.getChildRelationships()) {
//                     if (String.valueOf(cr.getChildSObject()) == mappedLineObject) {
//                         childRelationship = cr.getRelationshipName();
//                         break;
//                     }
//                 }
//             }

//             String query = 'SELECT ' + String.join(queryFields, ', ') +
//                            ', (SELECT Id, Product2.QuickbookID__c, Product2.Name, Quantity, UnitPrice, QB_LineItemID__c ' +
//                            'FROM ' + childRelationship + ') ' +
//                            'FROM ' + mappedObject + ' WHERE Id IN :recordIds';

//             Map<Id, SObject> recordsWithItems = new Map<Id, SObject>((List<SObject>)Database.query(query));

//             for (SObject obj : scope) {
//                 SObject currentRecord = recordsWithItems.get(obj.Id);

//                 List<SObject> childItems = currentRecord.getSObjects(childRelationship);
//                 if (currentRecord == null || childItems == null || childItems.isEmpty()) continue;

//                 String qbId = (String)currentRecord.get('QuickbookID__c');

//                 if (qbId == null && isInitialSync) {
//                     Map<String, Object> result = createInvoice(currentRecord, childItems, fieldMap);
//                     if (result != null) {
//                         currentRecord.put('QuickbookID__c', (String)result.get('invoiceId'));
//                         recordsToUpdate.add(currentRecord);
//                         itemsToUpdate.addAll(updateLineItemsWithCompositeIds(childItems, result, (String)result.get('invoiceId')));
//                     }
//                 } else if (qbId != null) {
//                     Map<String, Object> result = updateInvoice(currentRecord, childItems, fieldMap);
//                     if (result != null) {
//                         itemsToUpdate.addAll(updateLineItemsWithCompositeIds(childItems, result, qbId));
//                     }
//                 }
//             }

//             if (!recordsToUpdate.isEmpty()) update recordsToUpdate;
//             if (!itemsToUpdate.isEmpty()) update itemsToUpdate;

//         } catch(Exception e) {
//             System.debug('Error in Invoice Batch: ' + e.getMessage());
//         } finally {
//             QuickBooksInvoiceHandler.setBatchContext(false);
//         }
//     }

//     public void finish(Database.BatchableContext bc) {}

//     private Map<String, Object> createInvoice(SObject record, List<SObject> lineItems, Map<String, String> fieldMap) {
//         Map<String, Object> requestBody = new Map<String, Object>();

//         String customerRefId = getCustomerRefId(record);
//         if(String.isNotBlank(customerRefId)) {
//             requestBody.put('CustomerRef', new Map<String, String>{ 'value' => customerRefId });
//         }

//         applyDynamicMappings(requestBody, record, fieldMap);

//         requestBody.put('Line', buildLineItems(lineItems));

//         String requestJson = JSON.serialize(requestBody);
//         HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/invoice?minorversion=65', requestJson);

//         if (res.getStatusCode() == 200) {
//             Map<String, Object> invoiceMap = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(res.getBody())).get('Invoice');
//             return new Map<String, Object>{ 'invoiceId' => invoiceMap.get('Id'), 'lines' => invoiceMap.get('Line') };
//         }
//         return null;
//     }

//     private Map<String, Object> updateInvoice(SObject record, List<SObject> lineItems, Map<String, String> fieldMap) {
//         String qbId = (String)record.get('QuickbookID__c');
//         HttpResponse getRes = QuickBooksAuthHandler.makeApiCall('GET', '/invoice/' + qbId + '?minorversion=65', null);
//         if (getRes.getStatusCode() != 200) return null;

//         Map<String, Object> existingInvoice = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(getRes.getBody())).get('Invoice');

//         Map<String, Object> requestBody = new Map<String, Object>();
//         requestBody.put('Id', qbId);
//         requestBody.put('SyncToken', existingInvoice.get('SyncToken'));
//         requestBody.put('sparse', true);

//         applyDynamicMappings(requestBody, record, fieldMap);
//         requestBody.put('Line', buildLineItems(lineItems));

//         String requestJson = JSON.serialize(requestBody);
//         HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/invoice?minorversion=65', requestJson);

//         if (updateRes.getStatusCode() == 200) {
//             Map<String, Object> invoiceMap = (Map<String, Object>)((Map<String, Object>)JSON.deserializeUntyped(updateRes.getBody())).get('Invoice');
//             return new Map<String, Object>{ 'invoiceId' => invoiceMap.get('Id'), 'lines' => invoiceMap.get('Line') };
//         }
//         return null;
//     }

//     private void applyDynamicMappings(Map<String, Object> requestBody, SObject record, Map<String, String> fieldMap) {
//         for (String sfField : fieldMap.keySet()) {
//             String qbField = fieldMap.get(sfField);
//             Object value = getFieldValue(record, sfField);

//             if (value != null) {
//                 if (value instanceof Date) {
//                     value = DateTime.newInstance((Date)value, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
//                 }

//                 if (qbField.contains('.')) {
//                     List<String> path = qbField.split('\\.');
//                     Map<String, Object> currentMap = requestBody;
//                     for (Integer i = 0; i < path.size() - 1; i++) {
//                         String part = path[i];
//                         if (!currentMap.containsKey(part)) currentMap.put(part, new Map<String, Object>());
//                         currentMap = (Map<String, Object>)currentMap.get(part);
//                     }
//                     currentMap.put(path[path.size() - 1], value);
//                 } else {
//                     requestBody.put(qbField, value);
//                 }
//             }
//         }
//     }

//     private List<Map<String, Object>> buildLineItems(List<SObject> lineItems) {
//         List<Map<String, Object>> qbLines = new List<Map<String, Object>>();
//         Decimal totalAmount = 0;

//         for (SObject item : lineItems) {
//             Decimal quantity = (Decimal)item.get('Quantity');
//             Decimal unitPrice = (Decimal)item.get('UnitPrice');
//             Decimal lineAmount = quantity * unitPrice;
//             totalAmount += lineAmount;

//             SObject product = item.getSObject('Product2');
//             String productQbId = product != null ? (String)product.get('QuickbookID__c') : null;
//             String productName = product != null ? (String)product.get('Name') : null;

//             Map<String, Object> lineDetail = new Map<String, Object>{
//                 'DetailType' => 'SalesItemLineDetail',
//                 'Amount' => lineAmount,
//                 'SalesItemLineDetail' => new Map<String, Object>{
//                     'Qty' => quantity,
//                     'UnitPrice' => unitPrice
//                 }
//             };

//             if(productQbId != null) {
//                 ((Map<String, Object>)lineDetail.get('SalesItemLineDetail')).put('ItemRef', new Map<String, String>{
//                     'value' => productQbId,
//                     'name' => productName
//                 });
//             }

//             String qbLineId = (String)item.get('QB_LineItemID__c');
//             if (String.isNotBlank(qbLineId) && qbLineId.contains(':')) {
//                 lineDetail.put('Id', qbLineId.split(':')[1]);
//             }

//             qbLines.add(lineDetail);
//         }
//         qbLines.add(new Map<String, Object>{ 'DetailType' => 'SubTotalLineDetail', 'Amount' => totalAmount });
//         return qbLines;
//     }

//     private List<SObject> updateLineItemsWithCompositeIds(List<SObject> lineItems, Map<String, Object> qbResult, String invoiceId) {
//         List<SObject> itemsToUpdate = new List<SObject>();
//         List<Object> linesObj = (List<Object>)qbResult.get('lines');
//         if (linesObj == null) return itemsToUpdate;

//         return itemsToUpdate;
//     }

//     private static String getCustomerRefId(SObject record) {
//         try {
//             SObject accountRecord = record.getSObject('Account');
//             if(accountRecord != null) return (String)accountRecord.get('QuickbookID__c');
//         } catch(Exception e) {}
//         return null;
//     }

//     private static Object getFieldValue(SObject obj, String fieldPath) {
//         if(!fieldPath.contains('.')) return obj.get(fieldPath);
//         List<String> fields = fieldPath.split('\\.');
//         SObject currentObj = obj;
//         for (Integer i = 0; i < fields.size() - 1; i++) {
//             currentObj = currentObj.getSObject(fields[i]);
//             if (currentObj == null) return null;
//         }
//         return currentObj.get(fields[fields.size() - 1]);
//     }
// }