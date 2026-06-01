public with sharing class QBOInvoiceSyncQueueable implements Queueable, Database.AllowsCallouts {
    
    private Set<String> qboInvoiceIds;
    
    public QBOInvoiceSyncQueueable(Set<String> ids) {
        this.qboInvoiceIds = ids;
    }
    
    public void execute(QueueableContext context) {
        try {
            executeInternal();
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBOInvoiceSyncQueueable.execute', e, null, null);
            throw e;
        }
    }

    // Synchronous entry point for direct calls (e.g. from a record action controller)
    public void executeSync() {
        try {
            executeInternal();
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBOInvoiceSyncQueueable.executeSync', e, null, null);
            throw e;
        }
    }

    private void executeInternal() {
        if (qboInvoiceIds == null || qboInvoiceIds.isEmpty()) {
            return;
        }

        // MAPPINGS FETCH 
        Map<String, String> qboToSfOrderMap = QBObjectMappings.getInvoiceToOrderMapping();
        Map<String, String> qboToSfInvoiceMap = QBObjectMappings.reverseMapping(QBObjectMappings.getInvoiceMapping());
        
        // STANDARD PRICEBOOK FETCH
        Id standardPricebookId;
        if(Test.isRunningTest()) {
            standardPricebookId = Test.getStandardPricebookId();
        } else {
            List<Pricebook2> standardPbs = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
            if(!standardPbs.isEmpty()) {
                standardPricebookId = standardPbs[0].Id;
            }
        }
        
        // 3. COLLECTIONS FOR BULKIFICATION
        Map<String, Account> accountsToUpsert = new Map<String, Account>();
        Map<String, Product2> productsToUpsert = new Map<String, Product2>();
        List<Map<String, Object>> parsedInvoices;
        
        // ---------------------------------------------------------
        // PHASE 1: BULK CALLOUT & DATA COLLECTION (Account + Products)
        // ---------------------------------------------------------
        try {
            parsedInvoices = QuickBooksBulkQueryService.queryByIds('Invoice', qboInvoiceIds);
        } catch (Exception e) {
            ErrorLogUtility.LogContext logContext = new ErrorLogUtility.LogContext();
            logContext.gatewayName = 'QuickBooks';
            logContext.classMethodName = 'QBOInvoiceSyncQueueable.execute.bulkFetchInvoices';
            logContext.errorMessage = e.getTypeName() + ': ' + e.getMessage();
            logContext.stackTrace = e.getStackTraceString();
            logContext.sourceObjectApiName = 'Invoice__c';
            logContext.externalReference = String.join(new List<String>(qboInvoiceIds), ',');
            logContext.errorCategory = 'Callout Failure';
            ErrorLogUtility.logError(logContext);
            throw e;
        }

        for (Map<String, Object> invoiceData : parsedInvoices) {
            if (invoiceData == null) {
                continue;
            }

            Map<String, Object> customerRef = (Map<String, Object>)invoiceData.get('CustomerRef');
            if(customerRef != null) {
                String qboCustomerId = (String)customerRef.get('value');
                String customerName = (String)customerRef.get('name');
                if(String.isNotBlank(qboCustomerId) && !accountsToUpsert.containsKey(qboCustomerId)) {
                    accountsToUpsert.put(qboCustomerId, new Account(Name = customerName, QuickBridgeTLG__QuickbookID__c = qboCustomerId));
                }
            }

            List<Object> lines = (List<Object>)invoiceData.get('Line');
            if(lines != null) {
                for(Object lineObj : lines) {
                    Map<String, Object> lineItem = (Map<String, Object>)lineObj;
                    if((String)lineItem.get('DetailType') == 'SalesItemLineDetail') {
                        Map<String, Object> salesDetail = (Map<String, Object>)lineItem.get('SalesItemLineDetail');
                        Map<String, Object> itemRef = (Map<String, Object>)salesDetail.get('ItemRef');

                        if(itemRef != null) {
                            String itemId = (String)itemRef.get('value');
                            String itemName = (String)itemRef.get('name');

                            if(String.isNotBlank(itemId) && !productsToUpsert.containsKey(itemId)) {
                                productsToUpsert.put(itemId, new Product2(
                                    Name = itemName,
                                    QuickBridgeTLG__External_Id__c = itemId,
                                    IsActive = true
                                ));
                            }
                        }
                    }
                }
            }
        }
        
        if (parsedInvoices.isEmpty()) return; 
        
        // ---------------------------------------------------------
        // PHASE 2: UPSERT ACCOUNTS & PRODUCTS
        // ---------------------------------------------------------
        List<Account> accountRecords = accountsToUpsert.values();
        List<Product2> productRecords = productsToUpsert.values();
        // Guard flags prevent AccountTrigger/ProductTrigger from creating outbound work items
        QBTriggerHandler.isAccountProcessing = true;
        QBTriggerHandler.isProductProcessing = true;
        try {
            Database.UpsertResult[] accountResults = Database.upsert(accountRecords, Account.Fields.QuickBridgeTLG__QuickbookID__c, false);
            ErrorLogUtility.logUpsertResults('QuickBooks', 'QBOInvoiceSyncQueueable.execute.upsertAccounts', 'upsert', accountRecords, accountResults, null, null);
            Database.UpsertResult[] productResults = Database.upsert(productRecords, Product2.Fields.QuickBridgeTLG__External_Id__c, false);
            ErrorLogUtility.logUpsertResults('QuickBooks', 'QBOInvoiceSyncQueueable.execute.upsertProducts', 'upsert', productRecords, productResults, null, null);
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
            QBTriggerHandler.isProductProcessing = false;
        }
        
        Map<String, Id> qboCustomerToSfAccountIdMap = new Map<String, Id>();
        for(Account acc : accountsToUpsert.values()) {
            if(acc.Id != null) qboCustomerToSfAccountIdMap.put(acc.QuickBridgeTLG__QuickbookID__c, acc.Id);
        }
        
        // ---------------------------------------------------------
        // PHASE 3: HANDLE PRICEBOOK ENTRIES (The Exception Handler)
        // ---------------------------------------------------------
        Map<String, Id> qboItemToPbeId = new Map<String, Id>();
        if(standardPricebookId != null && !productsToUpsert.isEmpty()) {
            // Get existing PBEs
            List<PricebookEntry> existingPBEs = [SELECT Id, Product2.QuickBridgeTLG__External_Id__c FROM PricebookEntry 
                                                 WHERE Pricebook2Id = :standardPricebookId AND Product2.QuickBridgeTLG__External_Id__c IN :productsToUpsert.keySet()];
            
            for(PricebookEntry pbe : existingPBEs) {
                qboItemToPbeId.put(pbe.Product2.QuickBridgeTLG__External_Id__c, pbe.Id);
            }
            
            // Create Missing PBEs
            List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
            for(Product2 prod : productsToUpsert.values()) {
                if(!qboItemToPbeId.containsKey(prod.QuickBridgeTLG__External_Id__c) && prod.Id != null) {
                    pbesToInsert.add(new PricebookEntry(
                        Pricebook2Id = standardPricebookId,
                        Product2Id = prod.Id,
                        UnitPrice = 0, // Default 0, actual price goes in OrderItem
                        IsActive = true
                    ));
                }
            }
            if(!pbesToInsert.isEmpty()) {
                Database.SaveResult[] pbeResults = Database.insert(pbesToInsert, false);
                ErrorLogUtility.logDmlResults('QuickBooks', 'QBOInvoiceSyncQueueable.execute.insertPricebookEntries', 'insert', pbesToInsert, pbeResults, null, null);
                // Add newly created PBEs to Map
                for(PricebookEntry pbe : [SELECT Id, Product2.QuickBridgeTLG__External_Id__c FROM PricebookEntry WHERE Id IN :pbesToInsert]) {
                    qboItemToPbeId.put(pbe.Product2.QuickBridgeTLG__External_Id__c, pbe.Id);
                }
            }
        }
        
        // ---------------------------------------------------------
        // PHASE 4: UPSERT ORDERS (With Pricebook)
        // ---------------------------------------------------------
        Map<String, Order> ordersToUpsert = new Map<String, Order>();
        
        for (Map<String, Object> invoiceData : parsedInvoices) {
            String qboInvoiceId = (String)invoiceData.get('Id');
            Map<String, Object> customerRef = (Map<String, Object>)invoiceData.get('CustomerRef');
            String qboCustomerId = (customerRef != null) ? (String)customerRef.get('value') : null;
            Id sfAccountId = (qboCustomerId != null) ? qboCustomerToSfAccountIdMap.get(qboCustomerId) : null;
            
            if (sfAccountId != null) {
                Order newOrder = new Order(
                    AccountId = sfAccountId,
                    QuickBridgeTLG__QuickbookID__c = qboInvoiceId,
                    Status = 'Draft',
                    Pricebook2Id = standardPricebookId // MUST assign Pricebook to add products
                );
                applyDynamicMapping(newOrder, invoiceData, qboToSfOrderMap);
                ordersToUpsert.put(qboInvoiceId, newOrder);
            }
        }
        
        if (!ordersToUpsert.isEmpty()) {
            List<Order> orderRecords = ordersToUpsert.values();
            QBTriggerHandler.isOrderProcessing = true;
            try {
                Database.UpsertResult[] orderResults = Database.upsert(orderRecords, Order.Fields.QuickBridgeTLG__QuickbookID__c, false);
                ErrorLogUtility.logUpsertResults('QuickBooks', 'QBOInvoiceSyncQueueable.execute.upsertOrders', 'upsert', orderRecords, orderResults, null, null);
            } finally {
                QBTriggerHandler.isOrderProcessing = false;
            }
        }
        
        // ---------------------------------------------------------
        // PHASE 5: CREATE ORDER PRODUCTS (Line Items)
        // ---------------------------------------------------------
        // Delete old lines if Update webhook comes to prevent duplicates
        List<Id> orderIds = new List<Id>();
        for(Order o : ordersToUpsert.values()) { if(o.Id != null) orderIds.add(o.Id); }
        QBTriggerHandler.isOrderProcessing = true;
        try {
            if(!orderIds.isEmpty()) {
                List<OrderItem> orderItemsToDelete = [SELECT Id FROM OrderItem WHERE OrderId IN :orderIds];
                if (!orderItemsToDelete.isEmpty()) {
                    Database.DeleteResult[] deleteResults = Database.delete(orderItemsToDelete, false);
                    logDeleteResults('QBOInvoiceSyncQueueable.execute.deleteOrderItems', orderItemsToDelete, deleteResults);
                }
            }

            List<OrderItem> orderItemsToInsert = new List<OrderItem>();
            for (Map<String, Object> invoiceData : parsedInvoices) {
                String qboInvoiceId = (String)invoiceData.get('Id');
                Order relatedOrder = ordersToUpsert.get(qboInvoiceId);

                if(relatedOrder != null && relatedOrder.Id != null) {
                    List<Object> lines = (List<Object>)invoiceData.get('Line');
                    if(lines != null) {
                        for(Object lineObj : lines) {
                            Map<String, Object> lineItem = (Map<String, Object>)lineObj;
                            if((String)lineItem.get('DetailType') == 'SalesItemLineDetail') {
                                Map<String, Object> salesDetail = (Map<String, Object>)lineItem.get('SalesItemLineDetail');
                                Map<String, Object> itemRef = (Map<String, Object>)salesDetail.get('ItemRef');

                                if(itemRef != null) {
                                    String itemId = (String)itemRef.get('value');
                                    Id pbeId = qboItemToPbeId.get(itemId);

                                    if(pbeId != null) {
                                        Decimal qty = salesDetail.get('Qty') != null ? Decimal.valueOf(String.valueOf(salesDetail.get('Qty'))) : 1;
                                        Decimal unitPrice = salesDetail.get('UnitPrice') != null ? Decimal.valueOf(String.valueOf(salesDetail.get('UnitPrice'))) : 0;

                                        orderItemsToInsert.add(new OrderItem(
                                            OrderId = relatedOrder.Id,
                                            PricebookEntryId = pbeId,
                                            Quantity = qty,
                                            UnitPrice = unitPrice
                                        ));
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if(!orderItemsToInsert.isEmpty()) {
                Database.SaveResult[] orderItemResults = Database.insert(orderItemsToInsert, false);
                ErrorLogUtility.logDmlResults('QuickBooks', 'QBOInvoiceSyncQueueable.execute.insertOrderItems', 'insert', orderItemsToInsert, orderItemResults, null, null);
            }
        } finally {
            QBTriggerHandler.isOrderProcessing = false;
        }

        // ---------------------------------------------------------
        // PHASE 6: UPSERT INVOICE__C
        // ---------------------------------------------------------
        List<QuickBridgeTLG__Invoice__c> invoicesToUpsert = new List<QuickBridgeTLG__Invoice__c>();
        for (Map<String, Object> invoiceData : parsedInvoices) {
            String qboInvoiceId = (String)invoiceData.get('Id');
            Order relatedOrder = ordersToUpsert.get(qboInvoiceId);
            
            Map<String, Object> customerRef = (Map<String, Object>)invoiceData.get('CustomerRef');
            String qboCustomerId = (customerRef != null) ? (String)customerRef.get('value') : null;
            Id sfAccountId = (qboCustomerId != null) ? qboCustomerToSfAccountIdMap.get(qboCustomerId) : null;
            
            if(relatedOrder != null && relatedOrder.Id != null) {
                QuickBridgeTLG__Invoice__c newInv = new QuickBridgeTLG__Invoice__c(
                    QuickBridgeTLG__Order__c = relatedOrder.Id,
                    QuickBridgeTLG__Related_Account__c = sfAccountId,
                    QuickBridgeTLG__External_Id__c = qboInvoiceId
                );
                applyDynamicMapping(newInv, invoiceData, qboToSfInvoiceMap);
                invoicesToUpsert.add(newInv);
            }
        }
        
        if (!invoicesToUpsert.isEmpty()) {
            Database.UpsertResult[] invoiceResults = Database.upsert(invoicesToUpsert, QuickBridgeTLG__Invoice__c.Fields.QuickBridgeTLG__External_Id__c, false);
            ErrorLogUtility.logUpsertResults('QuickBooks', 'QBOInvoiceSyncQueueable.execute.upsertInvoices', 'upsert', invoicesToUpsert, invoiceResults, null, null);
        }
    }
    
    // ==========================================
    // HELPER 1: DYNAMIC MAPPING 
    // ==========================================
    private void applyDynamicMapping(SObject sObj, Map<String, Object> jsonData, Map<String, String> mappingMap) {
        if (mappingMap == null || mappingMap.isEmpty()) return;
        
        for (String qboFieldPath : mappingMap.keySet()) {
            String sfFieldApiName = mappingMap.get(qboFieldPath);
            Object qboValue = getNestedQboValue(jsonData, qboFieldPath);
            
            if (qboValue != null) {
                try {
                    if (qboValue instanceof String && ((String)qboValue).contains('-') && ((String)qboValue).length() == 10) {
                        sObj.put(sfFieldApiName, Date.valueOf((String)qboValue));
                    } else {
                        sObj.put(sfFieldApiName, qboValue);
                    }
                } catch (Exception e) {
                    System.debug('Mapping Field Error [' + sfFieldApiName + ']: ' + e.getMessage());
                }
            }
        }
    }

    private void logDeleteResults(String classMethodName, List<OrderItem> records, Database.DeleteResult[] results) {
        if (records == null || results == null) {
            return;
        }

        Integer limitSize = records.size() < results.size() ? records.size() : results.size();
        for (Integer index = 0; index < limitSize; index++) {
            if (results[index] == null || results[index].isSuccess()) {
                continue;
            }

            String message = buildDeleteErrorMessage(results[index].getErrors());
            ErrorLogUtility.logDmlFailure(
                'QuickBooks',
                classMethodName,
                'delete',
                'OrderItem',
                records[index].Id,
                message,
                null,
                null
            );
        }
    }

    private String buildDeleteErrorMessage(Database.Error[] errors) {
        if (errors == null || errors.isEmpty()) {
            return 'Unknown delete error.';
        }

        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            if (error != null) {
                messages.add(error.getStatusCode() + ': ' + error.getMessage());
            }
        }
        return messages.isEmpty() ? 'Unknown delete error.' : String.join(messages, ' | ');
    }
    
    // ==========================================
    // HELPER 2: NESTED JSON EXTRACTOR
    // ==========================================
    private Object getNestedQboValue(Map<String, Object> jsonData, String path) {
        if (String.isBlank(path)) return null;
        if (!path.contains('.')) return jsonData.get(path);
        
        List<String> keys = path.split('\\.');
        Map<String, Object> currentLevel = jsonData;
        
        for (Integer i = 0; i < keys.size() - 1; i++) {
            if (currentLevel.get(keys[i]) != null) {
                currentLevel = (Map<String, Object>)currentLevel.get(keys[i]);
            } else {
                return null;
            }
        }
        return currentLevel.get(keys[keys.size() - 1]);
    }
}