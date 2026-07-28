public class QBObjectMappings {
    private static final Map<String, String> ACCOUNT_TO_CUSTOMER_FALLBACK = new Map<String, String>{
        'Name' => 'DisplayName',
        'AccountNumber' => 'AcctNum',
        'Main_Email__c' => 'PrimaryEmailAddr.Address',
        'Phone' => 'PrimaryPhone.FreeFormNumber',
        'BillingStreet' => 'BillAddr.Line1',
        'BillingCity' => 'BillAddr.City',
        'BillingState' => 'BillAddr.CountrySubDivisionCode',
        'BillingPostalCode' => 'BillAddr.PostalCode',
        'BillingCountry' => 'BillAddr.Country',
        'Terms__c' => 'SalesTermRef.value',
        'External_Id__c' => 'ExternalId'
    };
    
    private static final Map<String, String> PRODUCT_TO_ITEM_FALLBACK = new Map<String, String>{
        'Name' => 'Name',
        'Description' => 'Description',
        'ProductCode' => 'Sku',
        'IsActive' => 'Active',
        'Quantity_On_Hand__c' => 'QtyOnHand',
        'Sale_Price__c' => 'UnitPrice',
        'Cost_Price__c' => 'PurchaseCost',
        'Income_Account__c' => 'IncomeAccountRef.value',
        'Expense_Account__c' => 'ExpenseAccountRef.value'
    };
    
    private static final Map<String, String> INVOICE_FALLBACK = new Map<String, String>{
        'Invoice_No__c' => 'DocNumber',
        'Invoice_Date__c' => 'TxnDate',
        'Due_Date__c' => 'DueDate',
        'Terms__c' => 'SalesTermRef.value',
        'External_Id__c' => 'ExternalId'
    };
    
    private static final Map<String, String> CREDIT_MEMO_FALLBACK = new Map<String, String>{
        'Txn_Number__c' => 'DocNumber',
        'Txn_Date__c' => 'TxnDate',
        'External_Id__c' => 'ExternalId'
    };
    
    private static final Map<String, String> PURCHASE_ORDER_FALLBACK = new Map<String, String>{
        'PO_Number__c' => 'DocNumber',
        'PO_Date__c' => 'TxnDate',
        'Delivery_Date__c' => 'ExpectedDate',
        'External_Id__c' => 'ExternalId'
    };
    
    private static final Map<String, String> ORDER_TO_INVOICE_FALLBACK = new Map<String, String>{
        'EffectiveDate' => 'TxnDate',
        //'TotalAmount' => 'TotalAmt',
        'Description' => 'CustomerMemo.value'
    };
    
    private static final Map<String, String> ORDER_ITEM_FALLBACK = new Map<String, String>{
        'Quantity' => 'Qty',
        'UnitPrice' => 'UnitPrice',
        'Description' => 'Description'
    };
    
    private static final Map<String, String> CREDIT_MEMO_LINE_FALLBACK = new Map<String, String>{
        'Quantity__c' => 'Line.SalesItemLineDetail.Qty',
        'Rate__c' => 'Line.SalesItemLineDetail.UnitPrice',
        'Description__c' => 'Line.Description'
    };
    
    private static final Map<String, String> PURCHASE_ORDER_LINE_FALLBACK = new Map<String, String>{
        'Quantity__c' => 'Line.ItemBasedExpenseLineDetail.Qty',
        'Cost_Price__c' => 'Line.ItemBasedExpenseLineDetail.UnitPrice',
        'Product_Description__c' => 'Line.Description'
    };
    
    private static final Map<String, String> TAX_CODE_FALLBACK = new Map<String, String>{
        'Name' => 'TaxCode', // QBO root name
        'QuickBridgeTLG__Tax_Rate_Per__c' => 'RateValue', // QBO inner rate
        'QuickBridgeTLG__Is_Active__c' => 'Active',
        'QuickBridgeTLG__Item_Description__c' => 'Description'
    };
    
    private static final Map<String, String> QUOTE_FALLBACK = new Map<String, String>{
        'Name' => 'DocNumber',
        'ExpirationDate' => 'ExpirationDate',
        'Description' => 'CustomerMemo.value'
    };
    
    private static final Map<String, String> QUOTE_LINE_ITEM_FALLBACK = new Map<String, String>{
        'Quantity' => 'Qty',
        'UnitPrice' => 'UnitPrice',
        'Description' => 'Description'
    };

    public static Map<String, String> getQuoteMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Quote', 'QBO to SF');
        if (dynamicMap != null && !dynamicMap.isEmpty()) { 
            return reverseMapping(dynamicMap); 
        }
        
        // Return fallback if no metadata found
        return reverseMapping(new Map<String, String>(QUOTE_FALLBACK));
    }
    
    public static Map<String, String> getQuoteLineItemMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('QuoteLineItem', 'QBO to SF');
        if (dynamicMap != null && !dynamicMap.isEmpty()) { 
            return reverseMapping(dynamicMap); 
        }
        
        // Return fallback if no metadata found
        return reverseMapping(new Map<String, String>(QUOTE_LINE_ITEM_FALLBACK));
    }

    public static Map<String, String> getTaxCodeInboundMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Item_Sales_Tax__c', 'QBO to SF');
        if (dynamicMap != null && !dynamicMap.isEmpty()) {
            return reverseMapping(dynamicMap);
        }
        
        // Fallback
        Map<String, String> fallback = new Map<String, String>();
        for (String sfField : TAX_CODE_FALLBACK.keySet()) {
            String qboField = TAX_CODE_FALLBACK.get(sfField);
            fallback.put(qboField, sfField);
        }
        return fallback;
    }
    private static Map<String, String> getDynamicMapping(String objectName, String syncDirection) {
        return getDynamicMapping(objectName, syncDirection, null);
    }

    // targetObject scopes to a specific QBO object (e.g. 'Customer' vs 'Vendor') so
    // that two QBO objects sharing the same Salesforce object keep independent
    // mappings. Legacy rows with a blank Target_Object_API_Name__c still apply.
    private static Map<String, String> getDynamicMapping(String objectName, String syncDirection, String targetObject) {
        Map<String, String> mapping = new Map<String, String>();

        try {
            List<Field_Mapping__mdt> metadataList = [
                SELECT SF_Field__c, External_Field__c, Target_Object_API_Name__c
                FROM Field_Mapping__mdt
                WHERE Integration__c = 'qbonline' AND SF_Object__c = :objectName AND Is_Active__c = true AND Sync_Direction__c IN ('Two-Way', :syncDirection)
            ];

            Boolean scopeByObject = String.isNotBlank(targetObject);
            for(Field_Mapping__mdt record : metadataList) {
                // Skip rows that belong to a different QBO object; keep legacy
                // (blank target object) rows so existing deployments are unaffected.
                if (scopeByObject
                    && String.isNotBlank(record.Target_Object_API_Name__c)
                    && record.Target_Object_API_Name__c != targetObject) {
                    continue;
                }
                if(String.isNotBlank(record.SF_Field__c) && String.isNotBlank(record.External_Field__c)) {
                    mapping.put(record.SF_Field__c, record.External_Field__c);
                }
            }
        } catch (Exception e) {
            System.debug('Mapping fetch error: ' + e.getMessage());
        }

        return mapping;
    }
    
    public static Map<String, String> reverseMapping(Map<String, String> sourceMapping) {
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
    
    // 1. Account -> Customer
    public static Map<String, String> getAccountToCustomerMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Account', 'SF to QBO', 'Customer');
        if (dynamicMap != null && !dynamicMap.isEmpty()) { return dynamicMap; }

        // Fallback
        return new Map<String, String>(ACCOUNT_TO_CUSTOMER_FALLBACK);
    }

    // Reverse Mapping for Customer -> Account (Inbound Sync)
    public static Map<String, String> getCustomerToAccountMapping() {
        Map<String, String> inboundFields = getDynamicMapping('Account', 'QBO to SF', 'Customer');
        if (inboundFields == null || inboundFields.isEmpty()) {
            return reverseMapping(new Map<String, String>(ACCOUNT_TO_CUSTOMER_FALLBACK));
        }
        return reverseMapping(inboundFields);
    }

    // Account -> Vendor (Outbound Sync)
    public static Map<String, String> getAccountToVendorMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Account', 'SF to QBO', 'Vendor');
        if (dynamicMap != null && !dynamicMap.isEmpty()) { return dynamicMap; }

        // Fallback to the shared Account->Customer field set when no Vendor-specific
        // mappings exist.
        return new Map<String, String>(ACCOUNT_TO_CUSTOMER_FALLBACK);
    }

    // Reverse Mapping for Vendor -> Account (Inbound Sync)
    public static Map<String, String> getVendorToAccountMapping() {
        Map<String, String> inboundFields = getDynamicMapping('Account', 'QBO to SF', 'Vendor');
        if (inboundFields == null || inboundFields.isEmpty()) {
            return reverseMapping(new Map<String, String>(ACCOUNT_TO_CUSTOMER_FALLBACK));
        }
        return reverseMapping(inboundFields);
    }
    
    // 2. Product2 -> Item
    public static Map<String, String> getProductToItemMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Product2', 'SF to QBO');
        if (dynamicMap != null && !dynamicMap.isEmpty()) { return dynamicMap; }
        
        // Fallback
        return new Map<String, String>(PRODUCT_TO_ITEM_FALLBACK);
    }
    
    public static Map<String, String> getItemToProductMapping() {
        Map<String, String> inboundFields = getDynamicMapping('Product2', 'QBO to SF');
        if (inboundFields == null || inboundFields.isEmpty()) {
            return reverseMapping(new Map<String, String>(PRODUCT_TO_ITEM_FALLBACK));
        }
        return reverseMapping(inboundFields);
    }
    // 3. Invoice__c -> QBO Invoice
    public static Map<String, String> getInvoiceMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Invoice__c', 'SF to QBO');
        if (dynamicMap != null && !dynamicMap.isEmpty()) return dynamicMap;
        
        return new Map<String, String>(INVOICE_FALLBACK);
    }
    
    // 4. Credit_Memo__c -> QBO CreditMemo
    public static Map<String, String> getCreditMemoMapping() {
        // Map<String, String> dynamicMap = getDynamicMapping('Credit_Memo__c', 'SF to QBO');
        Map<String, String> dynamicMap = getDynamicMapping('QuickBridgeTLG__Credit_Memo__c', 'SF to QBO');
        if (dynamicMap != null && !dynamicMap.isEmpty()) return dynamicMap;
        
        return new Map<String, String>(CREDIT_MEMO_FALLBACK);
    }
    
    // 5. Purchase_Order__c -> QBO PurchaseOrder
    public static Map<String, String> getPurchaseOrderMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Purchase_Order__c', 'SF to QBO');
        if (dynamicMap != null && !dynamicMap.isEmpty()) return dynamicMap;
        
        return new Map<String, String>(PURCHASE_ORDER_FALLBACK);
    }
    
    // 6. Item_Sales_Tax__c -> QBO TaxCode (AST)
    public static Map<String, String> getTaxCodeMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Item_Sales_Tax__c', 'SF to QBO');
        
        if (dynamicMap != null && !dynamicMap.isEmpty()) {
            return dynamicMap;
        }
        return new Map<String, String>(TAX_CODE_FALLBACK);
    }
    
    // Old Order -> Invoice Fallback
    public static Map<String, String> getOrderToInvoiceMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Order', 'SF to QBO');
        if (dynamicMap != null && !dynamicMap.isEmpty()) { return dynamicMap; }
        
        return new Map<String, String>(ORDER_TO_INVOICE_FALLBACK);
    }
    
    public static Map<String, String> getOrderItemMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('OrderItem', 'SF to QBO');
        if (dynamicMap != null && !dynamicMap.isEmpty()) return dynamicMap;
        return new Map<String, String>(ORDER_ITEM_FALLBACK);
    }
    
    public static Map<String, String> getCreditMemoLineMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Credit_Memo_Line__c', 'SF to QBO');
        if (dynamicMap != null && !dynamicMap.isEmpty()) return dynamicMap;
        return new Map<String, String>(CREDIT_MEMO_LINE_FALLBACK);
    }
    
    public static Map<String, String> getPurchaseOrderLineMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('Purchase_Order_Line__c', 'SF to QBO');
        if (dynamicMap != null && !dynamicMap.isEmpty()) return dynamicMap;
        return new Map<String, String>(PURCHASE_ORDER_LINE_FALLBACK);
    }

    // Reverse Mapping for QBO PurchaseOrder Line -> Purchase_Order_Line__c (Inbound Sync)
    public static Map<String, String> getQBOToPurchaseOrderLineMapping() {
        Map<String, String> inboundFields = getDynamicMapping('Purchase_Order_Line__c', 'QBO to SF');
        if (inboundFields == null || inboundFields.isEmpty()) {
            return reverseMapping(new Map<String, String>(PURCHASE_ORDER_LINE_FALLBACK));
        }
        return reverseMapping(inboundFields);
    }

    // Dynamic Invoice Source Detector
    public static String getInvoiceSourceObject() {
        try {
            QBOInvoiceMappingResolver.ResolverResult res = QBOInvoiceMappingResolver.resolve();
            if (String.isNotBlank(res.invoiceSourceObject)) {
                return res.invoiceSourceObject;
            }
        } catch (Exception e) {
            System.debug('getInvoiceSourceObject fallback: ' + e.getMessage());
        }
        return 'Order';
    }
    
    public static Map<String, String> getSmartInvoiceMapping() {
        String activeObject = getInvoiceSourceObject();
        
        if (activeObject == 'Order') {
            return getOrderToInvoiceMapping();
        }
        else if (activeObject == 'Invoice__c') {
            return getInvoiceMapping();
        }
        else {
            Map<String, String> standardQboMapping = getInvoiceMapping();
            Map<String, String> customFinalMapping = new Map<String, String>();
            
            List<Invoice_Field_Mapping__mdt> customMappings = [
                SELECT Source_Field_API_Name__c, Target_Field_API_Name__c 
                FROM Invoice_Field_Mapping__mdt 
                WHERE Is_Active__c = true
            ];
            
            for(Invoice_Field_Mapping__mdt mdt : customMappings) {
                String standardField = mdt.Source_Field_API_Name__c;
                String customField = mdt.Target_Field_API_Name__c;
                
                if (standardQboMapping.containsKey(standardField)) {
                    String qboField = standardQboMapping.get(standardField);
                    customFinalMapping.put(customField, qboField);
                }
            }
            return customFinalMapping;
        }
    }
    
    // Order Summary -> Invoice Fallback
    private static final Map<String, String> ORDER_SUMMARY_TO_INVOICE_FALLBACK = new Map<String, String>{
        'OrderedDate' => 'TxnDate',
        'Description' => 'CustomerMemo.value'
    };

    private static final Map<String, String> ORDER_ITEM_SUMMARY_FALLBACK = new Map<String, String>{
        'Quantity' => 'Qty',
        'UnitPrice' => 'UnitPrice',
        'Description' => 'Description'
    };

    public static Map<String, String> getOrderSummaryToInvoiceMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('OrderSummary', 'SF to QBO');
        if (dynamicMap != null && !dynamicMap.isEmpty()) { return dynamicMap; }
        return new Map<String, String>(ORDER_SUMMARY_TO_INVOICE_FALLBACK);
    }

    public static Map<String, String> getOrderItemSummaryMapping() {
        Map<String, String> dynamicMap = getDynamicMapping('OrderItemSummary', 'SF to QBO');
        if (dynamicMap != null && !dynamicMap.isEmpty()) return dynamicMap;
        return new Map<String, String>(ORDER_ITEM_SUMMARY_FALLBACK);
    }

    public static Map<String, String> getInvoiceToOrderSummaryMapping() {
        return reverseMapping(getOrderSummaryToInvoiceMapping());
    }

    public static Map<String, String> getInvoiceToOrderMapping() {
        return reverseMapping(getOrderToInvoiceMapping());
    }
    
    public static String getInvoiceLineItemObject(String parentObject) {
        try {
            QBOInvoiceMappingResolver.ResolverResult res = QBOInvoiceMappingResolver.resolve();
            if (String.isNotBlank(res.lineSourceObject)) {
                return res.lineSourceObject;
            }
        } catch (Exception e) {
            System.debug('getInvoiceLineItemObject fallback: ' + e.getMessage());
        }
        if (parentObject == 'Order') return 'OrderItem';
        return parentObject.replace('__c', '') + '_Line__c';
    }
}