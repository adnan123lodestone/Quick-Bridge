public class QBInvoiceToOrderSyncBatch implements Database.Batchable<String>, Database.AllowsCallouts, Database.Stateful {

    private String lastSyncDate;
    public static Boolean isProcessing = false;

    // Stateful variables
    private Map<String, Id> customerIdMap = new Map<String, Id>();
    private Map<String, Id> productIdMap = new Map<String, Id>();
    private Map<String, Id> orderIdMap = new Map<String, Id>();
    private Id standardPricebookId;

    public QBInvoiceToOrderSyncBatch() {
        // Set lastSyncDate to yesterday's date in 'YYYY-MM-DD' format
        Datetime yesterday = Datetime.now().addDays(-1);
        this.lastSyncDate = yesterday.format('YYYY-MM-dd');
        this.standardPricebookId = getStandardPricebookId();
    }
    public QBInvoiceToOrderSyncBatch(String syncDate) {
        this.lastSyncDate = syncDate;
        this.standardPricebookId = getStandardPricebookId();
    }

    private Id getStandardPricebookId() {
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

    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> invoiceIds = new List<String>();
        try {
            String query = 'select * from Invoice Where Metadata.LastUpdatedTime > \'' + lastSyncDate + '\'';

            // First encode the query
            String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');

            // Construct the resource path with both query and minorversion parameters
            String resourcePath = '/query?query=' + encodedQuery + '&minorversion=65';

            HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', resourcePath, null);

            if(response != null && response.getStatusCode() == 200 && String.isNotBlank(response.getBody())) {
                Map<String, Object> result = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                if(result != null && result.containsKey('QueryResponse')) {
                    Map<String, Object> queryResponse = (Map<String, Object>)result.get('QueryResponse');
                    if(queryResponse != null && queryResponse.containsKey('Invoice')) {
                        List<Object> invoices = (List<Object>)queryResponse.get('Invoice');
                        if(invoices != null) {
                            for(Object inv : invoices) {
                                if(inv != null) {
                                    invoiceIds.add(JSON.serialize(inv));
                                }
                            }
                        }
                    }
                }
            } else if (response != null) {
                ErrorLogUtility.logCalloutFailure(
                    'QuickBooks',
                    'QBInvoiceToOrderSyncBatch.start',
                    'QuickBooks invoice query returned HTTP ' + response.getStatusCode() + ': ' + response.getBody(),
                    response.getStatusCode(),
                    null,
                    null
                );
            }
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBInvoiceToOrderSyncBatch.start', e, null, null);
        }
        return invoiceIds;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        IntegrationUsageService.assertCanConsumeTask('QuickBooks', scope == null ? 1 : scope.size());
        isProcessing = true;
        QuickBooksInvoiceHandler.isProcessing = true;
        QBTriggerHandler.isOrderProcessing = true;

        try {
            // Phase 1: Process Accounts and Products
            processAccountsAndProducts(scope);

            // Phase 2: Process Orders
            processOrders(scope);

            // Phase 3: Process Order Items
            processOrderItems(scope);

        } catch(Exception e) {
            System.debug('Error processing invoices: ' + e.getMessage() + ' Stack Trace: ' + e.getStackTraceString());
            ErrorLogUtility.logException('QuickBooks', 'QBInvoiceToOrderSyncBatch.execute', e, null, null);
        } finally {
            isProcessing = false;
            QuickBooksInvoiceHandler.isProcessing = false;
            QBTriggerHandler.isOrderProcessing = false;
        }
    }

    private void processAccountsAndProducts(List<String> scope) {
        List<Account> accountsToUpsert = new List<Account>();
        List<Product2> productsToUpsert = new List<Product2>();
        Set<String> productQBIds = new Set<String>();

        // Collect all accounts and products from invoices
        for(String invoiceStr : scope) {
            Map<String, Object> invoice = (Map<String, Object>)JSON.deserializeUntyped(invoiceStr);

            // Process Customer (Account)
            if(invoice.containsKey('CustomerRef')) {
                Map<String, Object> customerRef = (Map<String, Object>)invoice.get('CustomerRef');
                String qbCustomerId = (String)customerRef.get('value');
                String customerName = (String)customerRef.get('name');

                if(!customerIdMap.containsKey(qbCustomerId)) {
                    accountsToUpsert.add(new Account(
                        Name = customerName,
                        QuickbookID__c = qbCustomerId
                    ));
                }
            }

            // Process Products from Line Items
            if(invoice.containsKey('Line')) {
                List<Object> lines = (List<Object>)invoice.get('Line');
                for(Object lineObj : lines) {
                    Map<String, Object> line = (Map<String, Object>)lineObj;
                    if(line.get('DetailType') == 'SalesItemLineDetail') {
                        Map<String, Object> salesItemDetail = (Map<String, Object>)line.get('SalesItemLineDetail');
                        if(salesItemDetail != null && salesItemDetail.containsKey('ItemRef')) {
                            Map<String, Object> itemRef = (Map<String, Object>)salesItemDetail.get('ItemRef');
                            String qbProductId = (String)itemRef.get('value');
                            productQBIds.add(qbProductId);
                        }
                    }
                }
            }
        }

        // Upsert Accounts
        if(!accountsToUpsert.isEmpty()) {
            Schema.SObjectField externalIdField = Account.Fields.QuickbookID__c;
            Database.UpsertResult[] results = Database.upsert(accountsToUpsert, externalIdField, false);
            ErrorLogUtility.logUpsertResults(
                'QuickBooks',
                'QBInvoiceToOrderSyncBatch.processAccountsAndProducts.upsertAccounts',
                'upsert',
                accountsToUpsert,
                results,
                null,
                null
            );

            for(Integer i = 0; i < results.size(); i++) {
                if(results[i].isSuccess()) {
                    customerIdMap.put(accountsToUpsert[i].QuickbookID__c, results[i].getId());
                } else {
                    System.debug('Error upserting account: ' + results[i].getErrors());
                }
            }
        }

        // Find existing products and populate productIdMap with ALL products (existing + new)
        for(Product2 p : [SELECT Id, QuickbookID__c FROM Product2 WHERE QuickbookID__c IN :productQBIds]) {
            productIdMap.put(p.QuickbookID__c, p.Id);
        }

        // Prepare new products for creation
        for(String invoiceStr : scope) {
            Map<String, Object> invoice = (Map<String, Object>)JSON.deserializeUntyped(invoiceStr);

            if(invoice.containsKey('Line')) {
                List<Object> lines = (List<Object>)invoice.get('Line');
                for(Object lineObj : lines) {
                    Map<String, Object> line = (Map<String, Object>)lineObj;
                    if(line.get('DetailType') == 'SalesItemLineDetail') {
                        Map<String, Object> salesItemDetail = (Map<String, Object>)line.get('SalesItemLineDetail');
                        if(salesItemDetail != null && salesItemDetail.containsKey('ItemRef')) {
                            Map<String, Object> itemRef = (Map<String, Object>)salesItemDetail.get('ItemRef');
                            String qbProductId = (String)itemRef.get('value');
                            String productName = (String)itemRef.get('name');

                            // Only add to upsert list if not already in productIdMap (not existing)
                            if(!productIdMap.containsKey(qbProductId)) {
                                productsToUpsert.add(new Product2(
                                    Name = productName,
                                    QuickbookID__c = qbProductId,
                                    IsActive = true
                                ));
                            }
                        }
                    }
                }
            }
        }

        // Upsert Products and create Pricebook Entries
        if(!productsToUpsert.isEmpty()) {
            Schema.SObjectField externalIdField = Product2.Fields.QuickbookID__c;
            Database.UpsertResult[] results = Database.upsert(productsToUpsert, externalIdField, false);
            ErrorLogUtility.logUpsertResults(
                'QuickBooks',
                'QBInvoiceToOrderSyncBatch.processAccountsAndProducts.upsertProducts',
                'upsert',
                productsToUpsert,
                results,
                null,
                null
            );

            List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
            for(Integer i = 0; i < results.size(); i++) {
                if(results[i].isSuccess()) {
                    String qbProductId = productsToUpsert[i].QuickbookID__c;
                    productIdMap.put(qbProductId, results[i].getId());

                    // Create Pricebook Entry for new product
                    pbesToInsert.add(new PricebookEntry(
                        Pricebook2Id = standardPricebookId,
                        Product2Id = results[i].getId(),
                        UnitPrice = 0, // Default price, will be updated from invoice if needed
                        IsActive = true
                    ));
                } else {
                    System.debug('Error upserting product: ' + results[i].getErrors());
                }
            }

            // Insert Pricebook Entries
            if(!pbesToInsert.isEmpty()) {
                try {
                    insert pbesToInsert;
                } catch(Exception e) {
                    System.debug('Error creating pricebook entries: ' + e.getMessage());
                    ErrorLogUtility.logException(
                        'QuickBooks',
                        'QBInvoiceToOrderSyncBatch.processAccountsAndProducts.insertPricebookEntries',
                        e,
                        null,
                        null
                    );
                }
            }
        }
    }

    private void processOrders(List<String> scope) {
        List<Order> ordersToUpsert = new List<Order>();
        Map<String, String> invoiceToOrderMapping = QBObjectMappings.getInvoiceToOrderMapping();

        for(String invoiceStr : scope) {
            Map<String, Object> invoice = (Map<String, Object>)JSON.deserializeUntyped(invoiceStr);
            String qbInvoiceId = (String)invoice.get('Id');

            if(!orderIdMap.containsKey(qbInvoiceId)) {
                Map<String, Object> customerRef = (Map<String, Object>)invoice.get('CustomerRef');
                if (customerRef == null) {
                    continue;
                }
                String qbCustomerId = (String)customerRef.get('value');

                if(customerIdMap.containsKey(qbCustomerId)) {
                    Order newOrder = new Order(
                        QuickbookID__c = qbInvoiceId,
                        AccountId = customerIdMap.get(qbCustomerId),
                        Status = 'Draft',
                        EffectiveDate = Date.today(),
                        Pricebook2Id = standardPricebookId
                    );

                    applyDynamicMapping(newOrder, invoice, invoiceToOrderMapping);
                    newOrder.QuickbookID__c = qbInvoiceId;

                    ordersToUpsert.add(newOrder);
                }
            }
        }

        if(!ordersToUpsert.isEmpty()) {
            Schema.SObjectField externalIdField = Order.Fields.QuickbookID__c;
            Database.UpsertResult[] results = Database.upsert(ordersToUpsert, externalIdField, false);
            ErrorLogUtility.logUpsertResults(
                'QuickBooks',
                'QBInvoiceToOrderSyncBatch.processOrders.upsertOrders',
                'upsert',
                ordersToUpsert,
                results,
                null,
                null
            );

            for(Integer i = 0; i < results.size(); i++) {
                if(results[i].isSuccess()) {
                    orderIdMap.put(ordersToUpsert[i].QuickbookID__c, results[i].getId());
                } else {
                    System.debug('Error upserting order: ' + results[i].getErrors());
                }
            }
        }
    }

    public void processOrderItems(List<String> scope) {
        List<OrderItem> orderItemsToUpsert = new List<OrderItem>();

        // Get all existing OrderItems with their details for comparison
        Map<String, OrderItem> existingOrderItemsMap = new Map<String, OrderItem>();

        // Collect all potential QB Invoice IDs from scope
        Set<String> allInvoiceIds = new Set<String>();
        for(String invoiceStr : scope) {
            Map<String, Object> invoice = (Map<String, Object>)JSON.deserializeUntyped(invoiceStr);
            String qbInvoiceId = (String)invoice.get('Id');
            allInvoiceIds.add(qbInvoiceId);
        }

        // Query existing OrderItems for ALL orders that might be related to invoices in this scope
        for(OrderItem oi : [SELECT Id, QB_LineItemID__c, Quantity, UnitPrice, Description, Product2Id, PricebookEntryId, OrderId,
                                  Order.QuickbookID__c, Order.Pricebook2Id
                           FROM OrderItem
                           WHERE Order.QuickbookID__c IN :allInvoiceIds]) {
            if(oi.QB_LineItemID__c != null) {
                existingOrderItemsMap.put(oi.QB_LineItemID__c, oi);
            }
        }

        // Create a map to track Order IDs and their Pricebook2Ids for validation
        Map<Id, Id> orderToPricebookMap = new Map<Id, Id>();
        for(OrderItem oi : existingOrderItemsMap.values()) {
            orderToPricebookMap.put(oi.OrderId, oi.Order.Pricebook2Id);
        }

        // Also add orders from current batch to the map
        for(String orderId : orderIdMap.keySet()) {
            Id salesforceOrderId = orderIdMap.get(orderId);
            orderToPricebookMap.put(salesforceOrderId, standardPricebookId);
        }

        // Get Product2 and PricebookEntry info for ALL products, organized by Pricebook
        Map<String, Map<Id, ProductEntryInfo>> productInfoByPricebook = new Map<String, Map<Id, ProductEntryInfo>>();

        // Query all PricebookEntries for products we need, for all relevant pricebooks
        Set<Id> relevantPricebooks = new Set<Id>(orderToPricebookMap.values());
        relevantPricebooks.add(standardPricebookId); // Ensure standard pricebook is included

        for(PricebookEntry pbe : [
            SELECT Id, Product2Id, Product2.QuickbookID__c, UnitPrice, Pricebook2Id
            FROM PricebookEntry
            WHERE Product2.QuickbookID__c IN :productIdMap.keySet()
            AND Pricebook2Id IN :relevantPricebooks
            AND IsActive = true
        ]) {
            String qbProductId = pbe.Product2.QuickbookID__c;
            Id pricebookId = pbe.Pricebook2Id;

            if(!productInfoByPricebook.containsKey(qbProductId)) {
                productInfoByPricebook.put(qbProductId, new Map<Id, ProductEntryInfo>());
            }

            productInfoByPricebook.get(qbProductId).put(pricebookId,
                new ProductEntryInfo(pbe.Product2Id, pbe.Id, pbe.UnitPrice));
        }

        for(String invoiceStr : scope) {
            Map<String, Object> invoice = (Map<String, Object>)JSON.deserializeUntyped(invoiceStr);
            String qbInvoiceId = (String)invoice.get('Id');

            // Find or create order for this invoice
            Id currentOrderId = null;
            Id orderPricebookId = null;

            if(orderIdMap.containsKey(qbInvoiceId)) {
                currentOrderId = orderIdMap.get(qbInvoiceId);
                orderPricebookId = standardPricebookId; // New orders use standard pricebook
            } else {
                // Query for existing order if not in current batch
                List<Order> existingOrders = [SELECT Id, Pricebook2Id FROM Order WHERE QuickbookID__c = :qbInvoiceId LIMIT 1];
                if(!existingOrders.isEmpty()) {
                    currentOrderId = existingOrders[0].Id;
                    orderPricebookId = existingOrders[0].Pricebook2Id;
                    orderIdMap.put(qbInvoiceId, currentOrderId); // Add to map for future reference
                    orderToPricebookMap.put(currentOrderId, orderPricebookId);
                }
            }

            if(currentOrderId == null) {
                System.debug('Order not found for invoice: ' + qbInvoiceId);
                continue;
            }

            if(invoice.containsKey('Line')) {
                List<Object> lines = (List<Object>)invoice.get('Line');
                for(Object lineObj : lines) {
                    Map<String, Object> line = (Map<String, Object>)lineObj;
                    if(line.get('DetailType') != 'SalesItemLineDetail') continue;

                    Map<String, Object> salesItemDetail = (Map<String, Object>)line.get('SalesItemLineDetail');
                    if(salesItemDetail == null || !salesItemDetail.containsKey('ItemRef')) continue;

                    Map<String, Object> itemRef = (Map<String, Object>)salesItemDetail.get('ItemRef');
                    String qbProductId = (String)itemRef.get('value');
                    String qbLineItemId = (String)line.get('Id');
                    String compositeLineId = qbInvoiceId + ':' + qbLineItemId;

                    // Check if product info exists for the correct pricebook
                    if(!productInfoByPricebook.containsKey(qbProductId) ||
                       !productInfoByPricebook.get(qbProductId).containsKey(orderPricebookId)) {
                        System.debug('Product info not found for QB ID: ' + qbProductId + ' in pricebook: ' + orderPricebookId);

                        // Try to create missing pricebook entry if product exists
                        if(productIdMap.containsKey(qbProductId)) {
                            try {
                                PricebookEntry newPbe = new PricebookEntry(
                                    Pricebook2Id = orderPricebookId,
                                    Product2Id = productIdMap.get(qbProductId),
                                    UnitPrice = 0,
                                    IsActive = true
                                );
                                insert newPbe;

                                // Add to our map
                                if(!productInfoByPricebook.containsKey(qbProductId)) {
                                    productInfoByPricebook.put(qbProductId, new Map<Id, ProductEntryInfo>());
                                }
                                productInfoByPricebook.get(qbProductId).put(orderPricebookId,
                                    new ProductEntryInfo(productIdMap.get(qbProductId), newPbe.Id, 0));

                                System.debug('Created missing pricebook entry for product: ' + qbProductId);
                            } catch(Exception e) {
                                System.debug('Failed to create pricebook entry for product ' + qbProductId + ': ' + e.getMessage());
                                ErrorLogUtility.logException(
                                    'QuickBooks',
                                    'QBInvoiceToOrderSyncBatch.processOrderItems.insertPricebookEntry',
                                    e,
                                    'Product2',
                                    productIdMap.get(qbProductId)
                                );
                                continue;
                            }
                        } else {
                            continue;
                        }
                    }

                    ProductEntryInfo peInfo = productInfoByPricebook.get(qbProductId).get(orderPricebookId);

                    try {
                        Decimal quantity = (Decimal)salesItemDetail.get('Qty');
                        Decimal unitPrice = (Decimal)salesItemDetail.get('UnitPrice');
                        String description = (String)line.get('Description');

                        if(quantity == null || unitPrice == null) {
                            System.debug('Invalid quantity/price for item: ' + compositeLineId);
                            continue;
                        }

                        // Check if this is an update to existing OrderItem
                        OrderItem orderItemToProcess;
                        Boolean isUpdate = false;

                        if(existingOrderItemsMap.containsKey(compositeLineId)) {
                            // Existing OrderItem - check if update is needed
                            OrderItem existingItem = existingOrderItemsMap.get(compositeLineId);

                            // Compare values to see if update is needed
                            Boolean needsUpdate = false;
                            if(existingItem.Quantity != quantity) {
                                System.debug('Quantity change detected for ' + compositeLineId + ': ' + existingItem.Quantity + ' -> ' + quantity);
                                needsUpdate = true;
                            }
                            if(existingItem.UnitPrice != unitPrice) {
                                System.debug('Unit Price change detected for ' + compositeLineId + ': ' + existingItem.UnitPrice + ' -> ' + unitPrice);
                                needsUpdate = true;
                            }
                            if(existingItem.Description != description) {
                                System.debug('Description change detected for ' + compositeLineId);
                                needsUpdate = true;
                            }
                            if(existingItem.Product2Id != peInfo.productId) {
                                System.debug('Product change detected for ' + compositeLineId);
                                needsUpdate = true;
                            }

                            if(needsUpdate) {
                                // Update existing OrderItem
                                orderItemToProcess = new OrderItem(
                                    Id = existingItem.Id,
                                    OrderId = currentOrderId,
                                    Product2Id = peInfo.productId,
                                    PricebookEntryId = peInfo.pricebookEntryId,
                                    Quantity = quantity,
                                    UnitPrice = unitPrice,
                                    QB_LineItemID__c = compositeLineId,
                                    Description = description
                                );
                                isUpdate = true;
                                System.debug('Preparing UPDATE for OrderItem: ' + compositeLineId + ' for Order: ' + currentOrderId + ' with PBE: ' + peInfo.pricebookEntryId);
                            } else {
                                System.debug('No changes detected for line item: ' + compositeLineId);
                                continue; // Skip if no changes
                            }
                        } else {
                            // New OrderItem
                            orderItemToProcess = new OrderItem(
                                OrderId = currentOrderId,
                                Product2Id = peInfo.productId,
                                PricebookEntryId = peInfo.pricebookEntryId,
                                Quantity = quantity,
                                UnitPrice = unitPrice,
                                QB_LineItemID__c = compositeLineId,
                                Description = description
                            );
                            System.debug('Preparing NEW OrderItem: ' + compositeLineId + ' for Order: ' + currentOrderId + ' with PBE: ' + peInfo.pricebookEntryId);
                        }

                        if(orderItemToProcess != null) {
                            orderItemsToUpsert.add(orderItemToProcess);
                        }
                    } catch(Exception e) {
                        System.debug('Error creating OrderItem ' + compositeLineId + ': ' + e.getMessage());
                        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
                        context.gatewayName = 'QuickBooks';
                        context.classMethodName = 'QBInvoiceToOrderSyncBatch.processOrderItems.buildOrderItem';
                        context.errorMessage = e.getTypeName() + ': ' + e.getMessage();
                        context.stackTrace = e.getStackTraceString();
                        context.sourceObjectApiName = 'Order';
                        context.sourceRecordId = currentOrderId;
                        context.sourceRecordIdText = currentOrderId == null ? qbInvoiceId : String.valueOf(currentOrderId);
                        context.externalReference = compositeLineId;
                        context.errorCategory = 'Code Exception';
                        ErrorLogUtility.logError(context);
                    }
                }
            }
        }

        if(!orderItemsToUpsert.isEmpty()) {
            System.debug('Upserting ' + orderItemsToUpsert.size() + ' OrderItems (New + Updated)');

            Database.UpsertResult[] results = Database.upsert(
                orderItemsToUpsert,
                OrderItem.Fields.QB_LineItemID__c,
                false
            );
            ErrorLogUtility.logUpsertResults(
                'QuickBooks',
                'QBInvoiceToOrderSyncBatch.processOrderItems.upsertOrderItems',
                'upsert',
                orderItemsToUpsert,
                results,
                null,
                null
            );

            Integer successCount = 0;
            Integer updateCount = 0;
            Integer newCount = 0;

            for(Integer i = 0; i < results.size(); i++) {
                if(results[i].isSuccess()) {
                    successCount++;
                    if(results[i].isCreated()) {
                        newCount++;
                    } else {
                        updateCount++;
                    }
                } else {
                    System.debug('Failed to upsert OrderItem ' + orderItemsToUpsert[i].QB_LineItemID__c +
                        ': ' + results[i].getErrors());
                }
            }
            System.debug('Successfully processed ' + successCount + '/' + orderItemsToUpsert.size() +
                        ' OrderItems (New: ' + newCount + ', Updated: ' + updateCount + ')');
            IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', successCount);
        } else {
            System.debug('No OrderItems to process - all items are up to date');
        }
    }

    // Helper class to store product and pricebook entry info
    public class ProductEntryInfo {
        public Id productId {get; set;}
        public Id pricebookEntryId {get; set;}
        public Decimal unitPrice {get; set;}

        public ProductEntryInfo(Id pId, Id peId, Decimal price) {
            this.productId = pId;
            this.pricebookEntryId = peId;
            this.unitPrice = price;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Batch processing completed');
        System.debug('Processed Accounts: ' + customerIdMap.size());
        System.debug('Processed Products: ' + productIdMap.size());
        System.debug('Processed Orders: ' + orderIdMap.size());
    }

    private void applyDynamicMapping(SObject record, Map<String, Object> qbData, Map<String, String> mapping) {
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

    private Object getNestedValue(Map<String, Object> data, String path) {
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

    private void putFieldValue(SObject record, String fieldName, Object value) {
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

    private Object coerceValue(Object value, Schema.DisplayType displayType) {
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
}