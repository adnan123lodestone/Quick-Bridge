public with sharing class QBOrderRecordActionController {
    
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

    @AuraEnabled
    public static ActionResponse syncToQuickBooks(Id orderId) {
        try {
            if (orderId == null) {
                throw new AuraHandledException('Order Id is required.');
            }

            // 1. Build dynamic query fields
            String orderFields = QBSalesOrderSyncBatch.buildOrderQueryFields();
            String orderItemFields = QBSalesOrderSyncBatch.buildOrderItemQueryFields();

            String query = 'SELECT ' + orderFields + 
                           ', AccountId, Account.QuickbookID__c' +
                           ', (SELECT Id, Quantity, UnitPrice, Description, TotalPrice, Product2Id, Product2.Name, Product2.QuickbookID__c, QB_LineItemID__c ' + 
                           orderItemFields + 
                           ' FROM OrderItems) ' +
                           ' FROM Order WHERE Id = :orderId LIMIT 1';

            List<Order> orders = Database.query(query);
            if (orders.isEmpty()) {
                throw new AuraHandledException('Order not found.');
            }
            Order ord = orders[0];

            // 2. Preflight checks
            if (ord.AccountId == null || String.isBlank(ord.Account.QuickbookID__c)) {
                throw new AuraHandledException('The associated Account does not have a QuickBooks ID. Please sync the Account to QuickBooks first.');
            }

            Set<String> missingProducts = new Set<String>();
            for (OrderItem item : ord.OrderItems) {
                if (item.Product2Id == null || String.isBlank(item.Product2.QuickbookID__c)) {
                    missingProducts.add(item.Product2.Name != null ? item.Product2.Name : String.valueOf(item.Product2Id));
                }
            }
            if (!missingProducts.isEmpty()) {
                throw new AuraHandledException('The following products on this order do not have a QuickBooks ID. Please sync the products to QuickBooks first: ' + String.join(new List<String>(missingProducts), ', '));
            }

            // 3. Determine endpoint and object name based on status and settings
            QboTargetInfo targetInfo = getQboTargetInfo(ord.Status);
            String endpointPath = targetInfo.endpointPath;
            String qboObjectName = targetInfo.qboObjectName;

            // 4. Build request payload
            Map<String, Object> requestBody = new Map<String, Object>();
            Map<String, String> headerMap = QBObjectMappings.getOrderToInvoiceMapping();
            Map<String, String> lineMap = QBObjectMappings.getOrderItemMapping();

            Boolean isCreate = String.isBlank(ord.QuickbookID__c);

            for (String sfField : headerMap.keySet()) {
                String qboFieldMapping = headerMap.get(sfField);
                if (String.isBlank(qboFieldMapping) || qboFieldMapping == 'CustomerRef.value' || qboFieldMapping == 'CustomerRef') {
                    continue;
                }
                String rootProp = qboFieldMapping.contains('.') ? qboFieldMapping.substringBefore('.') : qboFieldMapping;
                if (QBO_READONLY_PROPS.contains(rootProp)) {
                    continue;
                }
                if (rootProp == 'Id' && isCreate) {
                    continue;
                }
                Object val = getFieldValue(ord, sfField);
                if (val != null) {
                    if (val instanceof Date) {
                        val = DateTime.newInstance((Date)val, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
                    }
                    putPath(requestBody, qboFieldMapping, val);
                }
            }

            // Add Customer Ref
            requestBody.put('CustomerRef', new Map<String, String>{ 'value' => ord.Account.QuickbookID__c });

            // Build Lines
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
                    if (val == null || String.isBlank(qboField)) {
                        continue;
                    }
                    String leaf = normalizeLineLeaf(qboField);
                    if (leaf == 'Qty') {
                        quantity = (Decimal)val;
                        itemDetail.put('Qty', quantity);
                    } else if (leaf == 'UnitPrice') {
                        unitPrice = (Decimal)val;
                        itemDetail.put('UnitPrice', unitPrice);
                    } else if (leaf == 'Description') {
                        line.put('Description', val);
                    } else if (leaf == 'Amount') {
                        continue;
                    } else if (leaf == 'ItemRef.value' || leaf == 'ItemRef') {
                        continue;
                    } else if (!leaf.contains('.')) {
                        itemDetail.put(leaf, val);
                    }
                }
                line.put('Amount', quantity * unitPrice);
                itemDetail.put('ItemRef', new Map<String, String>{ 'value' => item.Product2.QuickbookID__c });
                line.put('SalesItemLineDetail', itemDetail);

                if (String.isNotBlank(item.QB_LineItemID__c) && item.QB_LineItemID__c.contains(':')) {
                    if (qboObjectName != 'Invoice') {
                        line.put('Id', item.QB_LineItemID__c.split(':')[1]);
                    }
                }
                lines.add(line);
            }
            requestBody.put('Line', lines);

            // Add existing QuickBooks metadata for update (bypassed if converting Estimate to Invoice)
            if (String.isNotBlank(ord.QuickbookID__c)) {
                if (ord.Status == 'Activated' && qboObjectName == 'Invoice') {
                    System.debug('Converting Estimate to Invoice.');
                } else {
                    requestBody.put('Id', ord.QuickbookID__c);
                    requestBody.put('SyncToken', String.isBlank(ord.SyncToken__c) ? '0' : ord.SyncToken__c);
                    requestBody.put('sparse', true);
                }
            }

            // 5. Call API
            String jsonBody = JSON.serialize(requestBody);
            HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', endpointPath, jsonBody);

            if (res != null && res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                Map<String, Object> qboResponseObj = (Map<String, Object>)responseMap.get(qboObjectName);

                // Bypass triggers during updates
                QuickBooksInvoiceHandler.setBatchContext(true);
                QBTriggerHandler.isOrderProcessing = true;
                try {
                    Order ordToUpdate = new Order(Id = ord.Id);
                    ordToUpdate.QuickbookID__c = (String)qboResponseObj.get('Id');
                    ordToUpdate.SyncToken__c = (String)qboResponseObj.get('SyncToken');
                    update ordToUpdate;

                    List<Object> qboLines = (List<Object>)qboResponseObj.get('Line');
                    if (qboLines != null) {
                        List<OrderItem> itemsToUpdate = new List<OrderItem>();
                        Integer qboLineIndex = 0;
                        for (OrderItem item : ord.OrderItems) {
                            while (qboLineIndex < qboLines.size()) {
                                Map<String, Object> qbLine = (Map<String, Object>)qboLines[qboLineIndex];
                                if (qbLine.get('DetailType') == 'SalesItemLineDetail') {
                                    OrderItem itemToUpdate = new OrderItem(Id = item.Id);
                                    itemToUpdate.QB_LineItemID__c = ordToUpdate.QuickbookID__c + ':' + (String)qbLine.get('Id');
                                    itemsToUpdate.add(itemToUpdate);
                                    qboLineIndex++;
                                    break;
                                }
                                qboLineIndex++;
                            }
                        }
                        if (!itemsToUpdate.isEmpty()) {
                            update itemsToUpdate;
                        }
                    }
                    
                    ActionResponse actionResponse = new ActionResponse();
                    actionResponse.success = true;
                    actionResponse.quickBooksId = ordToUpdate.QuickbookID__c;
                    actionResponse.message = 'Order successfully synced to QuickBooks ' + qboObjectName + ' ' + ordToUpdate.QuickbookID__c + '.';
                    return actionResponse;
                } finally {
                    QuickBooksInvoiceHandler.setBatchContext(false);
                    QBTriggerHandler.isOrderProcessing = false;
                }
            } else {
                String errorMsg = (res != null) ? res.getStatusCode() + ' - ' + res.getBody() : 'Null Response';
                ErrorLogUtility.logCalloutFailure('QuickBooks', 'QBOrderRecordActionController.syncToQuickBooks', 'QBO sales order sync failed: ' + errorMsg, res == null ? null : res.getStatusCode(), 'Order', orderId);
                throw new AuraHandledException(getQuickBooksErrorMessage(res, 'QuickBooks sales order sync failed.'));
            }
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBOrderRecordActionController.syncToQuickBooks', e, 'Order', orderId);
            throw buildActionException(e);
        }
    }

    @AuraEnabled
    public static ActionResponse syncFromQuickBooks(Id orderId) {
        try {
            if (orderId == null) {
                throw new AuraHandledException('Order Id is required.');
            }

            Order existingOrder = [SELECT Id, Status, QuickbookID__c, Pricebook2Id, AccountId FROM Order WHERE Id = :orderId LIMIT 1];
            if (String.isBlank(existingOrder.QuickbookID__c)) {
                throw new AuraHandledException('This Order does not have a QuickBooks ID yet. Run Sync To QB first.');
            }

            // 1. Resolve endpoint and Object type
            QboTargetInfo targetInfo = getQboTargetInfo(existingOrder.Status);
            String endpointPath = targetInfo.endpointPath;
            String qboObjectName = targetInfo.qboObjectName;

            // 2. Fetch latest data from QuickBooks
            HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', endpointPath + '/' + existingOrder.QuickbookID__c, null);

            if (response == null || response.getStatusCode() != 200) {
                throw new AuraHandledException(getQuickBooksErrorMessage(response, 'QuickBooks ' + qboObjectName + ' could not be retrieved.'));
            }

            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
            Map<String, Object> qboData = (Map<String, Object>)responseMap.get(qboObjectName);
            if (qboData == null) {
                throw new AuraHandledException('QuickBooks returned an empty ' + qboObjectName + ' response.');
            }

            // 3. Apply Dynamic Mappings to Order
            Map<String, String> invoiceToOrderMapping = QBObjectMappings.getInvoiceToOrderMapping();
            Order orderToUpdate = new Order(Id = existingOrder.Id);
            applyQuickBooksDataToOrder(orderToUpdate, qboData, invoiceToOrderMapping);

            orderToUpdate.QuickbookID__c = (String)qboData.get('Id');
            orderToUpdate.SyncToken__c = (String)qboData.get('SyncToken');

            // Resolve Account
            if (qboData.containsKey('CustomerRef')) {
                Map<String, Object> customerRef = (Map<String, Object>)qboData.get('CustomerRef');
                String qbCustomerId = (String)customerRef.get('value');
                if (String.isNotBlank(qbCustomerId)) {
                    List<Account> accs = [SELECT Id FROM Account WHERE QuickbookID__c = :qbCustomerId LIMIT 1];
                    if (!accs.isEmpty()) {
                        orderToUpdate.AccountId = accs[0].Id;
                    }
                }
            }

            // Resolve Pricebook
            Id pricebookId = existingOrder.Pricebook2Id;
            if (pricebookId == null) {
                pricebookId = getStandardPricebookId();
                orderToUpdate.Pricebook2Id = pricebookId;
            }

            // Update Order with triggers bypassed
            QuickBooksInvoiceHandler.setBatchContext(true);
            QBTriggerHandler.isOrderProcessing = true;
            try {
                update orderToUpdate;
            } finally {
                QuickBooksInvoiceHandler.setBatchContext(false);
                QBTriggerHandler.isOrderProcessing = false;
            }

            // 4. Process Line Items
            List<Object> qboLines = (List<Object>)qboData.get('Line');
            if (qboLines != null) {
                Set<String> productQbIds = new Set<String>();
                for (Object lineObj : qboLines) {
                    Map<String, Object> line = (Map<String, Object>)lineObj;
                    if (line.get('DetailType') == 'SalesItemLineDetail') {
                        Map<String, Object> detail = (Map<String, Object>)line.get('SalesItemLineDetail');
                        if (detail != null && detail.containsKey('ItemRef')) {
                            Map<String, Object> itemRef = (Map<String, Object>)detail.get('ItemRef');
                            String pQbId = (String)itemRef.get('value');
                            if (String.isNotBlank(pQbId)) {
                                productQbIds.add(pQbId);
                            }
                        }
                    }
                }

                // Query and map Products
                Map<String, Product2> productMap = new Map<String, Product2>();
                for (Product2 p : [SELECT Id, QuickbookID__c, Name FROM Product2 WHERE QuickbookID__c IN :productQbIds]) {
                    productMap.put(p.QuickbookID__c, p);
                }

                List<Product2> productsToInsert = new List<Product2>();
                for (Object lineObj : qboLines) {
                    Map<String, Object> line = (Map<String, Object>)lineObj;
                    if (line.get('DetailType') == 'SalesItemLineDetail') {
                        Map<String, Object> detail = (Map<String, Object>)line.get('SalesItemLineDetail');
                        if (detail != null && detail.containsKey('ItemRef')) {
                            Map<String, Object> itemRef = (Map<String, Object>)detail.get('ItemRef');
                            String pQbId = (String)itemRef.get('value');
                            String pName = (String)itemRef.get('name');
                            if (String.isNotBlank(pQbId) && !productMap.containsKey(pQbId)) {
                                Product2 newProd = new Product2(
                                    Name = String.isNotBlank(pName) ? pName : 'QuickBooks Product ' + pQbId,
                                    QuickbookID__c = pQbId,
                                    IsActive = true
                                );
                                productsToInsert.add(newProd);
                                productMap.put(pQbId, newProd);
                            }
                        }
                    }
                }

                if (!productsToInsert.isEmpty()) {
                    insert productsToInsert;
                    for (Product2 p : productsToInsert) {
                        productMap.put(p.QuickbookID__c, p);
                    }

                    Id stdPricebookId = getStandardPricebookId();
                    List<PricebookEntry> stdPbes = new List<PricebookEntry>();
                    for (Product2 p : productsToInsert) {
                        stdPbes.add(new PricebookEntry(
                            Pricebook2Id = stdPricebookId,
                            Product2Id = p.Id,
                            UnitPrice = 0,
                            IsActive = true
                        ));
                    }
                    if (!stdPbes.isEmpty()) {
                        insert stdPbes;
                    }
                }

                // Query and map PricebookEntries
                Map<Id, PricebookEntry> pbeMap = new Map<Id, PricebookEntry>();
                for (PricebookEntry pbe : [SELECT Id, Product2Id, Product2.QuickbookID__c FROM PricebookEntry 
                                           WHERE Pricebook2Id = :pricebookId AND Product2.QuickbookID__c IN :productQbIds AND IsActive = true]) {
                    pbeMap.put(pbe.Product2Id, pbe);
                }

                List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
                for (Product2 p : productMap.values()) {
                    if (p.Id != null && !pbeMap.containsKey(p.Id)) {
                        pbesToInsert.add(new PricebookEntry(
                            Pricebook2Id = pricebookId,
                            Product2Id = p.Id,
                            UnitPrice = 0,
                            IsActive = true
                        ));
                    }
                }
                if (!pbesToInsert.isEmpty()) {
                    insert pbesToInsert;
                    for (PricebookEntry pbe : pbesToInsert) {
                        pbeMap.put(pbe.Product2Id, pbe);
                    }
                }

                // Query existing OrderItems
                Map<String, OrderItem> existingOrderItems = new Map<String, OrderItem>();
                for (OrderItem oi : [SELECT Id, QB_LineItemID__c, Quantity, UnitPrice, Description FROM OrderItem WHERE OrderId = :existingOrder.Id]) {
                    if (String.isNotBlank(oi.QB_LineItemID__c)) {
                        existingOrderItems.put(oi.QB_LineItemID__c, oi);
                    }
                }

                List<OrderItem> orderItemsToUpsert = new List<OrderItem>();
                Map<String, String> lineMap = QBObjectMappings.getOrderItemMapping();
                Map<String, String> reverseLineMap = reverseMapping(lineMap);

                for (Object lineObj : qboLines) {
                    Map<String, Object> line = (Map<String, Object>)lineObj;
                    if (line.get('DetailType') != 'SalesItemLineDetail') {
                        continue;
                    }

                    Map<String, Object> detail = (Map<String, Object>)line.get('SalesItemLineDetail');
                    if (detail == null || !detail.containsKey('ItemRef')) {
                        continue;
                    }

                    String lineId = (String)line.get('Id');
                    String compositeId = orderToUpdate.QuickbookID__c + ':' + lineId;

                    Map<String, Object> itemRef = (Map<String, Object>)detail.get('ItemRef');
                    String pQbId = (String)itemRef.get('value');
                    Product2 prod = productMap.get(pQbId);
                    if (prod == null) {
                        continue;
                    }
                    PricebookEntry pbe = pbeMap.get(prod.Id);
                    if (pbe == null) {
                        continue;
                    }

                    Decimal quantity = detail.containsKey('Qty') ? Decimal.valueOf(String.valueOf(detail.get('Qty'))) : 1;
                    Decimal unitPrice = detail.containsKey('UnitPrice') ? Decimal.valueOf(String.valueOf(detail.get('UnitPrice'))) : 0;
                    String description = (String)line.get('Description');

                    OrderItem oi = existingOrderItems.get(compositeId);
                    if (oi == null) {
                        oi = new OrderItem(
                            OrderId = existingOrder.Id,
                            PricebookEntryId = pbe.Id,
                            QB_LineItemID__c = compositeId
                        );
                    }

                    oi.Quantity = quantity;
                    oi.UnitPrice = unitPrice;
                    oi.Description = description;

                    // Apply any other dynamic line-item mappings
                    for (String qbField : reverseLineMap.keySet()) {
                        String sfField = reverseLineMap.get(qbField);
                        String leaf = normalizeLineLeaf(qbField);
                        if (leaf == 'Qty' || leaf == 'UnitPrice' || leaf == 'Description' || leaf == 'Amount' || leaf == 'ItemRef') {
                            continue;
                        }
                        Object val = getNestedValue(detail, leaf);
                        if (val != null) {
                            putFieldValue(oi, sfField, val);
                        }
                    }

                    orderItemsToUpsert.add(oi);
                }

                // Upsert OrderItems with triggers bypassed
                if (!orderItemsToUpsert.isEmpty()) {
                    QuickBooksInvoiceHandler.setBatchContext(true);
                    QBTriggerHandler.isOrderProcessing = true;
                    try {
                        upsert orderItemsToUpsert QB_LineItemID__c;
                    } finally {
                        QuickBooksInvoiceHandler.setBatchContext(false);
                        QBTriggerHandler.isOrderProcessing = false;
                    }
                }
            }

            ActionResponse actionResponse = new ActionResponse();
            actionResponse.success = true;
            actionResponse.quickBooksId = existingOrder.QuickbookID__c;
            actionResponse.message = 'Order successfully updated from QuickBooks ' + qboObjectName + ' ' + existingOrder.QuickbookID__c + '.';
            return actionResponse;
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBOrderRecordActionController.syncFromQuickBooks', e, 'Order', orderId);
            throw buildActionException(e);
        }
    }

    // --- Helper Methods ---

    private static void applyQuickBooksDataToOrder(Order orderToUpdate, Map<String, Object> qboData, Map<String, String> mapping) {
        for (String qbField : mapping.keySet()) {
            String sfField = mapping.get(qbField);
            Object qbValue = getNestedValue(qboData, qbField);
            if (qbValue != null) {
                putFieldValue(orderToUpdate, sfField, qbValue);
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

    private static void putFieldValue(SObject record, String fieldName, Object value) {
        if (record == null || String.isBlank(fieldName) || fieldName.contains('.') || value == null) {
            return;
        }

        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        if (!fields.containsKey(fieldName)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();
        if (!fieldDescribe.isCreateable() && !fieldDescribe.isUpdateable()) {
            return;
        }

        Schema.DisplayType displayType = fieldDescribe.getType();
        record.put(fieldName, coerceValue(value, displayType));
    }

    private static Object coerceValue(Object value, Schema.DisplayType displayType) {
        if (value == null) {
            return null;
        }

        try {
            if (
                displayType == Schema.DisplayType.Currency ||
                displayType == Schema.DisplayType.Double ||
                displayType == Schema.DisplayType.Percent
            ) {
                return Decimal.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.Integer) {
                return Integer.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.Boolean) {
                if (value instanceof Boolean) {
                    return value;
                }
                return String.valueOf(value).toLowerCase() == 'true';
            }
            if (displayType == Schema.DisplayType.Date) {
                if (value instanceof Date) {
                    return value;
                }
                return Date.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.DateTime) {
                if (value instanceof Datetime) {
                    return value;
                }
                return Datetime.valueOf(String.valueOf(value));
            }
        } catch (Exception e) {
            return value;
        }

        return value;
    }

    private static Id getStandardPricebookId() {
        try {
            if (Test.isRunningTest()) {
                return Test.getStandardPricebookId();
            }
            return [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1].Id;
        } catch (Exception e) {
            System.debug('Error getting standard pricebook: ' + e.getMessage());
            return null;
        }
    }

    private static Map<String, String> reverseMapping(Map<String, String> sourceMapping) {
        Map<String, String> reversedMapping = new Map<String, String>();
        if (sourceMapping == null) {
            return reversedMapping;
        }
        
        for (String sfField : sourceMapping.keySet()) {
            String qbField = sourceMapping.get(sfField);
            if (String.isNotBlank(sfField) && String.isNotBlank(qbField)) {
                reversedMapping.put(qbField, sfField);
            }
        }
        
        return reversedMapping;
    }

    private static String normalizeLineLeaf(String qboField) {
        String leaf = qboField;
        if (leaf.startsWith('Line.')) {
            leaf = leaf.substringAfter('Line.');
        }
        if (leaf.startsWith('SalesItemLineDetail.')) {
            leaf = leaf.substringAfter('SalesItemLineDetail.');
        }
        return leaf;
    }

    private static Object getFieldValue(SObject obj, String fieldPath) {
        if (!fieldPath.contains('.')) {
            try {
                return obj.get(fieldPath);
            } catch (Exception e) {
                return null;
            }
        }
        List<String> fields = fieldPath.split('\\.');
        SObject currentObj = obj;
        for (Integer i = 0; i < fields.size() - 1; i++) {
            currentObj = currentObj.getSObject(fields[i]);
            if (currentObj == null) {
                return null;
            }
        }
        return currentObj.get(fields[fields.size() - 1]);
    }

    private static void putPath(Map<String, Object> root, String dottedPath, Object value) {
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

    private static String getQuickBooksErrorMessage(HttpResponse response, String fallbackMessage) {
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

    // Target Info helper class and resolver to reduce redundancy
    public class QboTargetInfo {
        public String endpointPath { get; set; }
        public String qboObjectName { get; set; }
        
        public QboTargetInfo(String endpoint, String objName) {
            this.endpointPath = endpoint;
            this.qboObjectName = objName;
        }
    }
    
    private static QboTargetInfo getQboTargetInfo(String status) {
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
        } else if (status == 'Activated') {
            return new QboTargetInfo('/invoice', 'Invoice');
        } else {
            throw new AuraHandledException('Only Draft or Activated Orders can be synced to QuickBooks.');
        }
    }
}