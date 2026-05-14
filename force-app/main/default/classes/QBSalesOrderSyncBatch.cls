public class QBSalesOrderSyncBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    private Set<Id> orderIds;
    private Boolean isInitialSync;

    public QBSalesOrderSyncBatch(Set<Id> ids, Boolean isInitial) {
        this.orderIds = ids;
        this.isInitialSync = isInitial;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Status, QuickbookID__c, SyncToken__c, Account.QuickbookID__c,
            (SELECT Id, Quantity, UnitPrice, Description, Product2.QuickbookID__c, QB_LineiTemID__c FROM OrderItems)
            FROM Order
            WHERE Id IN :orderIds
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Order> scope) {
        List<Order> ordersToUpdate = new List<Order>();
        List<OrderItem> itemsToUpdate = new List<OrderItem>();

        Map<String, String> headerMap = QBObjectMappings.getOrderToInvoiceMapping();
        Map<String, String> lineMap = QBObjectMappings.getOrderItemMapping();

        for (Order ord : scope) {
            try {
                if (ord.OrderItems == null || ord.OrderItems.isEmpty()) {
                    System.debug('Skipping Order ' + ord.Id + ' because it has no Line Items.');
                    continue;
                }

                String endpointPath = '';
                String qboObjectName = '';

                // Status Check: Draft -> Estimate, Activated -> Invoice
                if (ord.Status == 'Draft') {
                    endpointPath = '/estimate';
                    qboObjectName = 'Estimate';
                } else if (ord.Status == 'Activated') {
                    endpointPath = '/invoice';
                    qboObjectName = 'Invoice';
                } else {
                    continue;
                }

                Map<String, Object> requestBody = new Map<String, Object>();

                // Dynamic Field Mapping for Order Header
                for (String sfField : headerMap.keySet()) {
                    String qboFieldMapping = headerMap.get(sfField);

                    if (qboFieldMapping == 'CustomerRef.value' || qboFieldMapping == 'CustomerRef') {
                        continue;
                    }

                    Object val = getFieldValue(ord, sfField);
                    if (val != null) {
                        if (val instanceof Date) {
                            val = DateTime.newInstance((Date)val, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
                        }
                        requestBody.put(qboFieldMapping, val);
                    }
                }

                // Customer Reference (Account ID)
                if(ord.Account != null && String.isNotBlank(ord.Account.QuickbookID__c)) {
                    requestBody.put('CustomerRef', new Map<String, String>{
                        'value' => ord.Account.QuickbookID__c
                    });
                }

                // 3. Dynamic Field Mapping for Order Line Items
                List<Map<String, Object>> lines = new List<Map<String, Object>>();

                for (OrderItem item : ord.OrderItems) {
                    Map<String, Object> line = new Map<String, Object>();
                    line.put('DetailType', 'SalesItemLineDetail');

                    Map<String, Object> itemDetail = new Map<String, Object>();
                    Decimal quantity = item.Quantity != null ? item.Quantity : 1;
                    Decimal unitPrice = item.UnitPrice != null ? item.UnitPrice : 0;

                    for (String sfField : lineMap.keySet()) {
                        Object val = getFieldValue(item, sfField);
                        String qboField = lineMap.get(sfField);

                        if (val != null) {
                            if (qboField == 'Qty') {
                                quantity = (Decimal)val;
                                itemDetail.put('Qty', quantity);
                            } else if (qboField == 'UnitPrice') {
                                unitPrice = (Decimal)val;
                                itemDetail.put('UnitPrice', unitPrice);
                            } else if (qboField == 'Description') {
                                line.put('Description', val);
                            } else {
                                itemDetail.put(qboField, val);
                            }
                        }
                    }

                    line.put('Amount', quantity * unitPrice);

                    if(item.Product2 != null && String.isNotBlank(item.Product2.QuickbookID__c)) {
                        itemDetail.put('ItemRef', new Map<String, String>{ 'value' => item.Product2.QuickbookID__c });
                    }

                    line.put('SalesItemLineDetail', itemDetail);

                    if (String.isNotBlank(item.QB_LineiTemID__c) && item.QB_LineiTemID__c.contains(':')) {
                        if (qboObjectName != 'Invoice') {
                            line.put('Id', item.QB_LineiTemID__c.split(':')[1]);
                        }
                    }

                    lines.add(line);
                }

                requestBody.put('Line', lines);

                // =======================================================
                // 4. THE FIX: Handle QBO ID (Estimate to Invoice Logic)
                // =======================================================
                if (String.isNotBlank(ord.QuickbookID__c) && !isInitialSync) {

                    if (ord.Status == 'Activated' && qboObjectName == 'Invoice') {
                        System.debug('Converting Estimate to Invoice. Sending as a NEW record.');
                    } else {
                        // Normal update
                        requestBody.put('Id', ord.QuickbookID__c);
                        requestBody.put('SyncToken', String.isBlank(ord.SyncToken__c) ? '0' : ord.SyncToken__c);
                        requestBody.put('sparse', true);
                    }
                }

                // 5. API Callout
                String jsonBody = JSON.serialize(requestBody);
                HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', endpointPath, jsonBody);

                if (res != null && res.getStatusCode() == 200) {
                    Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                    Map<String, Object> qboResponseObj = (Map<String, Object>)responseMap.get(qboObjectName);

                    Order ordToUpdate = new Order(Id = ord.Id);
                    ordToUpdate.QuickbookID__c = (String)qboResponseObj.get('Id');
                    ordToUpdate.SyncToken__c = (String)qboResponseObj.get('SyncToken');
                    ordersToUpdate.add(ordToUpdate);

                    List<Object> qboLines = (List<Object>)qboResponseObj.get('Line');
                    if (qboLines != null) {
                        Integer qboLineIndex = 0;
                        for (OrderItem item : ord.OrderItems) {
                            while (qboLineIndex < qboLines.size()) {
                                Map<String, Object> qbLine = (Map<String, Object>)qboLines[qboLineIndex];
                                if (qbLine.get('DetailType') == 'SalesItemLineDetail') {
                                    OrderItem itemToUpdate = new OrderItem(Id = item.Id);
                                    itemToUpdate.QB_LineiTemID__c = ordToUpdate.QuickbookID__c + ':' + (String)qbLine.get('Id');
                                    itemsToUpdate.add(itemToUpdate);
                                    qboLineIndex++;
                                    break;
                                }
                                qboLineIndex++;
                            }
                        }
                    }
                } else {
                    System.debug('QBO Sync Error: ' + (res != null ? res.getStatusCode() + ' - ' + res.getBody() : 'Null Response'));
                    ErrorLogUtility.logCalloutFailure(
                        'QuickBooks',
                        'QBSalesOrderSyncBatch.execute',
                        'QBO sales order sync failed: ' + (res != null ? res.getStatusCode() + ' - ' + res.getBody() : 'Null Response'),
                        res == null ? null : res.getStatusCode(),
                        'Order',
                        ord == null ? null : ord.Id
                    );
                }

            } catch (Exception e) {
                System.debug('Exception in QBSalesOrderSyncBatch: ' + e.getMessage() + ' at Line ' + e.getLineNumber());
                ErrorLogUtility.logException(
                    'QuickBooks',
                    'QBSalesOrderSyncBatch.execute',
                    e,
                    'Order',
                    ord == null ? null : ord.Id
                );
            }
        }

        if (!ordersToUpdate.isEmpty()) {
            Database.SaveResult[] orderResults = Database.update(ordersToUpdate, false);
            ErrorLogUtility.logDmlResults(
                'QuickBooks',
                'QBSalesOrderSyncBatch.execute.updateOrders',
                'update',
                ordersToUpdate,
                orderResults,
                null,
                null
            );
        }
        if (!itemsToUpdate.isEmpty()) {
            Database.SaveResult[] itemResults = Database.update(itemsToUpdate, false);
            ErrorLogUtility.logDmlResults(
                'QuickBooks',
                'QBSalesOrderSyncBatch.execute.updateOrderItems',
                'update',
                itemsToUpdate,
                itemResults,
                null,
                null
            );
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Order Sync Completed Successfully.');
    }

    private Object getFieldValue(SObject obj, String fieldPath) {
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