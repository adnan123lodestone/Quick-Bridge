public class QuickBooksInvoiceBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    
    private Set<Id> orderIds;
    private Boolean isInitialSync;
    private Map<Id, OrderItem> triggerOrderItems; // Store the original trigger data
    
    public QuickBooksInvoiceBatch(Set<Id> orderIds, Boolean isInitialSync) {
        this.orderIds = orderIds;
        this.isInitialSync = isInitialSync;
        this.triggerOrderItems = new Map<Id, OrderItem>();
    }
    
    // New constructor to pass trigger data
    public QuickBooksInvoiceBatch(Set<Id> orderIds, Boolean isInitialSync, List<OrderItem> triggerItems) {
        this.orderIds = orderIds;
        this.isInitialSync = isInitialSync;
        this.triggerOrderItems = new Map<Id, OrderItem>();
        
        // Store trigger items by their ID for quick lookup
        if (triggerItems != null) {
            for (OrderItem item : triggerItems) {
                this.triggerOrderItems.put(item.Id, item);
            }
        }
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Account.QuickbookID__c, EffectiveDate, TotalAmount, QuickbookID__c
            FROM Order 
            WHERE Id IN :orderIds
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<Order> scope) {
        QuickBooksInvoiceHandler.setBatchContext(true);
        
        try {
            List<Order> ordersToUpdate = new List<Order>();
            List<OrderItem> itemsToUpdate = new List<OrderItem>();
            
            // Query current OrderItems but merge with trigger data for accuracy
            Map<Id, Order> ordersWithItems = new Map<Id, Order>([
                SELECT Id, Account.QuickbookID__c, EffectiveDate, TotalAmount, QuickbookID__c,
                       (SELECT Id, Product2.QuickbookID__c, Product2.Name, ListPrice, Quantity, 
                               QB_LineItemID__c, OrderId, UnitPrice
                        FROM OrderItems)
                FROM Order
                WHERE Id IN :orderIds
            ]);

            for (Order ord : scope) {
                Order currentOrd = ordersWithItems.get(ord.Id);

                if (currentOrd == null || currentOrd.OrderItems == null || currentOrd.OrderItems.isEmpty()) {
                    continue;
                }
                
                // Merge trigger data with current data to ensure we have the latest values
                List<OrderItem> mergedItems = mergeOrderItemData(currentOrd.OrderItems);
                
                if (currentOrd.QuickbookID__c == null && isInitialSync) {
                    // Initial sync - create new invoice
                    Map<String, Object> result = createInvoice(currentOrd, mergedItems);
                    if (result != null) {
                        currentOrd.QuickbookID__c = (String)result.get('invoiceId');
                        ordersToUpdate.add(currentOrd);
                        
                        // Update OrderItems with composite QB Line IDs
                        List<OrderItem> updatedItems = updateOrderItemsWithCompositeLineIds(mergedItems, result, currentOrd.QuickbookID__c);
                        itemsToUpdate.addAll(updatedItems);
                    }
                } else if (currentOrd.QuickbookID__c != null) {
                    // Update existing invoice
                    Map<String, Object> result = updateInvoice(currentOrd, mergedItems);
                    if (result != null) {
                        // Update OrderItems with composite QB Line IDs (including new items)
                        List<OrderItem> updatedItems = updateOrderItemsWithCompositeLineIds(mergedItems, result, currentOrd.QuickbookID__c);
                        itemsToUpdate.addAll(updatedItems);
                    }
                }
            }
            
            // Update records with recursion prevention
            if (!ordersToUpdate.isEmpty()) {
                update ordersToUpdate;
            }
            if (!itemsToUpdate.isEmpty()) {
                update itemsToUpdate;
            }
        } finally {
            QuickBooksInvoiceHandler.setBatchContext(false);
        }
    }
    
    // New method to merge trigger data with current data
    private List<OrderItem> mergeOrderItemData(List<OrderItem> currentItems) {
        List<OrderItem> mergedItems = new List<OrderItem>();
        
        for (OrderItem currentItem : currentItems) {
            OrderItem itemToUse = currentItem;
            
            // If we have trigger data for this item, use the trigger values for key fields
            if (triggerOrderItems.containsKey(currentItem.Id)) {
                OrderItem triggerItem = triggerOrderItems.get(currentItem.Id);
                
                // Use trigger values for the fields that were actually updated
                itemToUse = currentItem.clone(true, true, true, true);
                itemToUse.Quantity = triggerItem.Quantity;
                itemToUse.UnitPrice = triggerItem.UnitPrice;
                
                System.debug('Merged OrderItem ' + currentItem.Id + ' with trigger data - UnitPrice: ' + triggerItem.UnitPrice + ', Quantity: ' + triggerItem.Quantity);
            }
            
            mergedItems.add(itemToUse);
        }
        
        return mergedItems;
    }
    
    public void finish(Database.BatchableContext bc) {
        // Optional: Send notification or log completion
    }
    
    // Updated helper method to create composite Line IDs like QB to SF sync
    private List<OrderItem> updateOrderItemsWithCompositeLineIds(List<OrderItem> orderItems, Map<String, Object> qbResult, String invoiceId) {
        List<OrderItem> itemsToUpdate = new List<OrderItem>();
        
        // Get the lines from QB response
        List<Object> linesObj = (List<Object>)qbResult.get('lines');
        if (linesObj == null) return itemsToUpdate;
        
        // Convert to proper format
        List<Map<String, Object>> lines = new List<Map<String, Object>>();
        for (Object lineObj : linesObj) {
            lines.add((Map<String, Object>)lineObj);
        }
        
        // Create a map of existing OrderItem composite IDs for comparison
        Map<String, OrderItem> existingCompositeIds = new Map<String, OrderItem>();
        for (OrderItem item : orderItems) {
            if (String.isNotBlank(item.QB_LineItemID__c)) {
                existingCompositeIds.put(item.QB_LineItemID__c, item);
            }
        }
        
        // Match OrderItems with QB lines by product and sequence
        Set<String> matchedQbLineIds = new Set<String>();

        for (OrderItem item : orderItems) {
            String productQBId = item.Product2.QuickbookID__c;
            Boolean foundMatch = false;
            
            for (Map<String, Object> line : lines) {
                String qbLineId = (String)line.get('Id');
                if (qbLineId == null || matchedQbLineIds.contains(qbLineId)) {
                    continue;
                }

                if (line.get('DetailType') == 'SubTotalLineDetail') {
                    continue;
                }
                
                Map<String, Object> salesDetail = (Map<String, Object>)line.get('SalesItemLineDetail');
                if (salesDetail != null) {
                    Map<String, Object> itemRef = (Map<String, Object>)salesDetail.get('ItemRef');
                    String lineProductId = (String)itemRef.get('value');
                    
                    // Match by product ID
                    if (productQBId == lineProductId) {
                        String compositeLineId = invoiceId + ':' + qbLineId;
                        
                        if (item.QB_LineItemID__c != compositeLineId) {
                            item.QB_LineItemID__c = compositeLineId;
                            itemsToUpdate.add(item);
                            System.debug('Updated OrderItem ' + item.Id + ' with composite ID: ' + compositeLineId);
                        }
                        matchedQbLineIds.add(qbLineId);
                        foundMatch = true;
                        break;
                    }
                }
            }
        }
        
        return itemsToUpdate;
    }
    
    // Create new invoice in QuickBooks
    private Map<String, Object> createInvoice(Order ord, List<OrderItem> orderItems) {
        // Build request body
        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('CustomerRef', new Map<String, String>{
            'value' => ord.Account.QuickbookID__c
        });
        requestBody.put('TxnDate', formatDate(ord.EffectiveDate));
        
        // Build line items
        List<Map<String, Object>> lineItems = new List<Map<String, Object>>();
        Decimal totalAmount = 0;
        
        for (OrderItem item : orderItems) {
            Decimal lineAmount = item.UnitPrice * item.Quantity;
            totalAmount += lineAmount;
            
            Map<String, Object> lineItem = new Map<String, Object>{
                'DetailType' => 'SalesItemLineDetail',
                'Amount' => lineAmount,
                'SalesItemLineDetail' => new Map<String, Object>{
                    'ItemRef' => new Map<String, String>{
                        'value' => item.Product2.QuickbookID__c,
                        'name' => item.Product2.Name
                    },
                    'Qty' => item.Quantity,
                    'UnitPrice' => item.UnitPrice
                }
            };
            
            lineItems.add(lineItem);
        }
        
        // Add subtotal line
        lineItems.add(new Map<String, Object>{
            'DetailType' => 'SubTotalLineDetail',
            'Amount' => totalAmount
        });
        
        requestBody.put('Line', lineItems);
        
        // Make API call
        String requestJson = JSON.serialize(requestBody);
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/invoice?minorversion=65', requestJson);
        
        if (res.getStatusCode() == 200) {
            // Parse response
            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            Map<String, Object> invoiceMap = (Map<String, Object>)responseMap.get('Invoice');
            
            System.debug('Create Invoice Response: ' + responseMap);
            
            return new Map<String, Object>{
                'invoiceId' => invoiceMap.get('Id'),
                'lines' => invoiceMap.get('Line')
            };
        } else {
            System.debug('Error creating invoice: ' + res.getBody());
            return null;
        }
    }
    
    // Update existing invoice in QuickBooks
    private Map<String, Object> updateInvoice(Order ord, List<OrderItem> orderItems) {
        System.debug('Starting updateInvoice for Order: ' + ord.Id);
        System.debug('Order Items Count: ' + orderItems.size());
        
        for (OrderItem item : orderItems) {
            System.debug('OrderItem ID: ' + item.Id + 
                       ' UnitPrice: ' + item.UnitPrice + 
                       ' Quantity: ' + item.Quantity + 
                       ' QB_LineItemID__c: ' + item.QB_LineItemID__c);
        }
        
        // First get the invoice to obtain SyncToken
        HttpResponse getRes = QuickBooksAuthHandler.makeApiCall('GET', '/invoice/' + ord.QuickbookID__c + '?minorversion=65', null);
        
        if (getRes.getStatusCode() != 200) {
            System.debug('Error getting invoice: ' + getRes.getBody());
            return null;
        }
        
        Map<String, Object> getResponseMap = (Map<String, Object>)JSON.deserializeUntyped(getRes.getBody());
        Map<String, Object> existingInvoice = (Map<String, Object>)getResponseMap.get('Invoice');
        
        // Build update request
        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('Id', ord.QuickbookID__c);
        requestBody.put('SyncToken', existingInvoice.get('SyncToken'));
        requestBody.put('sparse', true);
        requestBody.put('TxnDate', formatDate(ord.EffectiveDate));
        
        // Build line items with existing QB Line IDs where available
        List<Map<String, Object>> lineItems = new List<Map<String, Object>>();
        Decimal totalAmount = 0;
        
        for (OrderItem item : ord.OrderItems) {
            Decimal lineAmount = item.UnitPrice * item.Quantity;
            totalAmount += lineAmount;
            
            Map<String, Object> lineItem = new Map<String, Object>{
                'DetailType' => 'SalesItemLineDetail',
                'Amount' => lineAmount,
                'SalesItemLineDetail' => new Map<String, Object>{
                    'ItemRef' => new Map<String, String>{
                        'value' => item.Product2.QuickbookID__c,
                        'name' => item.Product2.Name
                    },
                    'Qty' => item.Quantity,
                    'UnitPrice' => item.UnitPrice,
                    'TaxCodeRef' => new Map<String, String>{
                        'value' => 'TAX' 
                    }
                }
            };
            
            // Extract QB Line ID from composite field if available
            if (String.isNotBlank(item.QB_LineItemID__c)) {
                String[] parts = item.QB_LineItemID__c.split(':');
                if (parts.size() == 2 && parts[0] == ord.QuickbookID__c) {
                    String qbLineId = parts[1];
                    lineItem.put('Id', qbLineId);
                    System.debug('Using existing QB Line ID: ' + qbLineId + ' for OrderItem: ' + item.Id);
                }
            }
            
            lineItems.add(lineItem);
        }
        
        // Add subtotal line
        lineItems.add(new Map<String, Object>{
            'DetailType' => 'SubTotalLineDetail',
            'Amount' => totalAmount
        });
        
        requestBody.put('Line', lineItems);
        
        // Make API call
        String requestJson = JSON.serialize(requestBody);
        System.debug('Update Invoice Request: ' + requestJson);
        
        HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/invoice?minorversion=65', requestJson);
        
        if (updateRes.getStatusCode() == 200) {
            // Parse response
            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(updateRes.getBody());
            Map<String, Object> invoiceMap = (Map<String, Object>)responseMap.get('Invoice');
            
            System.debug('Update Invoice Response: ' + responseMap);
            
            return new Map<String, Object>{
                'invoiceId' => invoiceMap.get('Id'),
                'lines' => invoiceMap.get('Line')
            };
        } else {
            System.debug('Error updating invoice: ' + updateRes.getBody());
            return null;
        }
    }
    
    // Helper method to format date for QuickBooks
    private static String formatDate(Date d) {
        if (d == null) return null;
        return DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
    }
}