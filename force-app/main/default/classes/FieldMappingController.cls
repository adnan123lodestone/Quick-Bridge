/**
 * FieldMappingController - Handles field mapping between Salesforce and external systems (QB Online, Klaviyo)
 * 
 * QB API Integration Setup:
 * 1. Create Named Credentials in Salesforce:
 *    - Set Name: "QuickBooksOnline"
 *    - Set URL: https://quickbooks.api.intuit.com
 *    - Use OAuth 2.0 for authentication
 *    - Add scope: com.intuit.quickbooks.accounting
 * 
 * 2. Uncomment and implement the fetchQBFieldsFromAPI() method to fetch actual QB fields
 */
public with sharing class FieldMappingController {
    
    // QB API endpoint (set up Named Credentials with this name in Salesforce)
    private static final String QB_API_ENDPOINT = 'callout:QuickBooksOnline';
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getOrderFields() {
        List<FieldWrapper> fields = new List<FieldWrapper>();
        
        try {
            // Get the Order SObject describe
            Schema.DescribeSObjectResult describeResult = Order.getSObjectType().getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
            
            // Iterate through all fields and add accessible ones
            for (String fieldName : fieldMap.keySet()) {
                Schema.SObjectField field = fieldMap.get(fieldName);
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                
                // Only include accessible fields
                if (fieldDescribe.isAccessible()) {
                    fields.add(new FieldWrapper(fieldDescribe.getLabel(), fieldDescribe.getName()));
                }
            }
            
            // Sort alphabetically by label
            fields.sort();
            
            // Convert to Map format for return
            List<Map<String, String>> result = new List<Map<String, String>>();
            for (FieldWrapper fw : fields) {
                Map<String, String> fieldData = new Map<String, String>();
                fieldData.put('label', fw.label);
                fieldData.put('value', fw.value);
                result.add(fieldData);
            }
            
            return result;
            
        } catch (Exception e) {
            System.debug('Error retrieving Order fields: ' + e.getMessage());
            throw new AuraHandledException('Unable to retrieve Order fields: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getSalesforceObjects() {
        List<Map<String, String>> objects = new List<Map<String, String>>();
        
        try {
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            List<String> objectNames = new List<String>(globalDescribe.keySet());
            objectNames.sort();
            
            for (String objectName : objectNames) {
                Schema.SObjectType sObjectType = globalDescribe.get(objectName);
                Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
                
                // Only include accessible, queryable objects
                if (describeResult.isAccessible() && describeResult.isQueryable()) {
                    Map<String, String> objectData = new Map<String, String>();
                    objectData.put('label', describeResult.getLabel());
                    objectData.put('value', describeResult.getName());
                    objects.add(objectData);
                }
            }
            
        } catch (Exception e) {
            System.debug('Error retrieving Salesforce objects: ' + e.getMessage());
            throw new AuraHandledException('Unable to retrieve Salesforce objects: ' + e.getMessage());
        }
        
        return objects;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getObjectFields(String objectName) {
        List<FieldWrapper> fields = new List<FieldWrapper>();
        
        try {
            if (String.isBlank(objectName)) {
                throw new IllegalArgumentException('Object name is required');
            }
            
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            Schema.SObjectType sObjectType = globalDescribe.get(objectName);
            
            if (sObjectType == null) {
                throw new IllegalArgumentException('Invalid object name: ' + objectName);
            }
            
            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
            
            // Iterate through all fields and add accessible ones
            for (String fieldName : fieldMap.keySet()) {
                Schema.SObjectField field = fieldMap.get(fieldName);
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                
                // Only include accessible fields
                if (fieldDescribe.isAccessible()) {
                    fields.add(new FieldWrapper(fieldDescribe.getLabel(), fieldDescribe.getName()));
                }
            }
            
            // Sort alphabetically by label
            fields.sort();
            
            // Convert to Map format for return
            List<Map<String, String>> result = new List<Map<String, String>>();
            for (FieldWrapper fw : fields) {
                Map<String, String> fieldData = new Map<String, String>();
                fieldData.put('label', fw.label);
                fieldData.put('value', fw.value);
                result.add(fieldData);
            }
            
            return result;
            
        } catch (Exception e) {
            System.debug('Error retrieving fields for object ' + objectName + ': ' + e.getMessage());
            throw new AuraHandledException('Unable to retrieve fields: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<Map<String, String>> getQuickBooksFields() {
        List<Map<String, String>> qbFields = new List<Map<String, String>>();
        
        try {
            // Check if QB API Named Credentials is available and use it, otherwise use hardcoded fields
            try {
                return fetchQBFieldsFromAPI();
            } catch (Exception apiError) {
                System.debug('QB API error, falling back to hardcoded fields: ' + apiError.getMessage());
                // Fall back to hardcoded fields if API is not available
            }
            
            // Hardcoded QB fields as fallback
            qbFields.add(createQBField('QB - Order ID', 'qb_order_id'));
            qbFields.add(createQBField('QB - Customer ID', 'qb_customer_id'));
            qbFields.add(createQBField('QB - Amount', 'qb_amount'));
            qbFields.add(createQBField('QB - Status', 'qb_status'));
            qbFields.add(createQBField('QB - Date', 'qb_date'));
            qbFields.add(createQBField('QB - Line Items', 'qb_line_items'));
            qbFields.add(createQBField('QB - Billing Address', 'qb_billing_addr'));
            qbFields.add(createQBField('QB - Shipping Address', 'qb_shipping_addr'));
            qbFields.add(createQBField('QB - Memo', 'qb_memo'));
            qbFields.add(createQBField('QB - Department', 'qb_department'));
            qbFields.add(createQBField('QB - Tax Total', 'qb_tax_total'));
            qbFields.add(createQBField('QB - Due Date', 'qb_due_date'));
            
            return qbFields;
            
        } catch (Exception e) {
            System.debug('Error retrieving QB fields: ' + e.getMessage());
            throw new AuraHandledException('Unable to retrieve QB fields: ' + e.getMessage());
        }
    }
    
    /**
     * Fetch QB fields from QB API
     * Requires Named Credentials setup in Salesforce for QB OAuth
     * Named Credentials Name: "QuickBooksOnline"
     */
    private static List<Map<String, String>> fetchQBFieldsFromAPI() {
        List<Map<String, String>> qbFields = new List<Map<String, String>>();
        
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(QB_API_ENDPOINT + '/v2/query');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(10000);
            
            // Query to get Invoice fields from QB
            String query = 'SELECT * FROM Invoice LIMIT 1';
            req.setBody(query);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                // Parse response and extract fields
                Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                // Parse QB response and extract available fields
                if (responseBody.containsKey('Invoice')) {
                    Map<String, Object> invoiceData = (Map<String, Object>) responseBody.get('Invoice');
                    
                    // Extract fields from the Invoice object
                    for (String fieldName : invoiceData.keySet()) {
                        qbFields.add(createQBField('QB - ' + fieldName, 'qb_' + fieldName.toLowerCase()));
                    }
                }
            } else {
                throw new CalloutException('QB API error: ' + res.getStatus() + ' - ' + res.getBody());
            }
            
            return qbFields;
            
        } catch (Exception e) {
            System.debug('Error calling QB API: ' + e.getMessage());
            // Re-throw so caller can decide whether to use fallback
            throw e;
        }
    }
    
    
    private static Map<String, String> createQBField(String label, String value) {
        Map<String, String> field = new Map<String, String>();
        field.put('label', label);
        field.put('value', value);
        return field;
    }
    
    // Wrapper class for sorting fields by label
    private class FieldWrapper implements Comparable {
        public String label { get; set; }
        public String value { get; set; }
        
        public FieldWrapper(String label, String value) {
            this.label = label;
            this.value = value;
        }
        
        public Integer compareTo(Object obj) {
            FieldWrapper other = (FieldWrapper) obj;
            return this.label.compareTo(other.label);
        }
    }
}