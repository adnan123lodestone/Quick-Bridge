public class QBAccountService {
    public class SyncResult {
        public Id accountId { get; set; }
        public Boolean created { get; set; }
        public String quickBooksId { get; set; }
    }

    public static void syncAccountsToQuickBooks(List<Account> accounts, Boolean isInsert) {
        for (Account acc : accounts) {
            try {
                syncAccountToQuickBooks(acc, isInsert);
            } catch (Exception e) {
                System.debug('Error syncing account ID ' + acc.Id + ': ' + e.getMessage());
                System.debug(e.getStackTraceString());
                // Consider adding error handling to notify admins
            }
        }
    }

    public static SyncResult syncAccountToQuickBooks(Account acc, Boolean forceCreate) {
        if (acc == null) {
            throw new QBIntegrationException('Account is required for QuickBooks sync.');
        }

        SyncResult result = new SyncResult();
        result.accountId = acc.Id;

        if (forceCreate || acc.QuickbookID__c == null) {
            String qbCustomerId = createCustomerInQuickBooks(acc);
            result.created = true;
            result.quickBooksId = qbCustomerId;

            if (acc.Id != null) {
                QBTriggerHandler.isAccountProcessing = true;
                try {
                    update new Account(
                        Id = acc.Id,
                        QuickbookID__c = qbCustomerId
                    );
                } finally {
                    QBTriggerHandler.isAccountProcessing = false;
                }
            }
        } else {
            updateCustomerInQuickBooks(acc);
            result.created = false;
            result.quickBooksId = acc.QuickbookID__c;
        }

        return result;
    }
    
    private static String createCustomerInQuickBooks(Account acc) {
        // Build the request body using field mappings
        Map<String, Object> customerMap = new Map<String, Object>();
        Map<String, String> fieldMap = QBObjectMappings.getAccountToCustomerMapping();
        
        for (String sfField : fieldMap.keySet()) {
            String qbField = fieldMap.get(sfField);
            Object value = getFieldValue(acc, sfField);
            
            if (value != null) {
                // Handle nested fields (e.g., PrimaryEmailAddr.Address)
                if (qbField.contains('.')) {
                    List<String> fieldPath = qbField.split('\\.');
                    Map<String, Object> currentMap = customerMap;
                    
                    for (Integer i = 0; i < fieldPath.size() - 1; i++) {
                        String pathPart = fieldPath[i];
                        if (!currentMap.containsKey(pathPart)) {
                            currentMap.put(pathPart, new Map<String, Object>());
                        }
                        currentMap = (Map<String, Object>)currentMap.get(pathPart);
                    }
                    
                    currentMap.put(fieldPath[fieldPath.size() - 1], value);
                } else {
                    customerMap.put(qbField, value);
                }
            }
        }
        
        // Add required fields if not mapped
        if (!customerMap.containsKey('DisplayName')) {
            customerMap.put('DisplayName', acc.Name);
        }
        if (!customerMap.containsKey('FullyQualifiedName')) {
            customerMap.put('FullyQualifiedName', acc.Name);
        }
        
        String requestBody = JSON.serialize(customerMap);
        System.debug('Creating customer in QuickBooks: ' + requestBody);
        
        // Make API call
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/customer', requestBody);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            Map<String, Object> customerResponse = (Map<String, Object>)responseMap.get('Customer');
            return (String)customerResponse.get('Id');
        } else {
            throw new QBIntegrationException('Error creating customer in QuickBooks: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }
    
    private static void updateCustomerInQuickBooks(Account acc) {
        // First query the customer to get SyncToken
        HttpResponse queryRes = QuickBooksAuthHandler.makeApiCall('GET', '/customer/' + acc.QuickbookID__c, null);
        
        if (queryRes.getStatusCode() != 200) {
            throw new QBIntegrationException('Error querying customer in QuickBooks: ' + queryRes.getStatusCode() + ' ' + queryRes.getBody());
        }
        
        Map<String, Object> existingCustomer = (Map<String, Object>)JSON.deserializeUntyped(queryRes.getBody());
        Map<String, Object> customerMap = (Map<String, Object>)existingCustomer.get('Customer');
        
        // Update fields from Salesforce
        Map<String, String> fieldMap = QBObjectMappings.getAccountToCustomerMapping();
        
        for (String sfField : fieldMap.keySet()) {
            String qbField = fieldMap.get(sfField);
            Object value = getFieldValue(acc, sfField);
            
            if (value != null) {
                // Handle nested fields
                if (qbField.contains('.')) {
                    List<String> fieldPath = qbField.split('\\.');
                    Map<String, Object> currentMap = customerMap;
                    
                    for (Integer i = 0; i < fieldPath.size() - 1; i++) {
                        String pathPart = fieldPath[i];
                        if (!currentMap.containsKey(pathPart)) {
                            currentMap.put(pathPart, new Map<String, Object>());
                        }
                        currentMap = (Map<String, Object>)currentMap.get(pathPart);
                    }
                    
                    currentMap.put(fieldPath[fieldPath.size() - 1], value);
                } else {
                    customerMap.put(qbField, value);
                }
            }
        }

        if (String.isNotBlank(acc.Name)) {
            customerMap.put('DisplayName', acc.Name);
            customerMap.put('FullyQualifiedName', acc.Name);
        }

        // Ensure sparse is set to false for full updates
        customerMap.put('sparse', false);
        
        String requestBody = JSON.serialize(customerMap);
        System.debug('Updating customer in QuickBooks: ' + requestBody);
        
        // Make API call
        HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/customer', requestBody);
        
        if (updateRes.getStatusCode() != 200) {
            throw new QBIntegrationException('Error updating customer in QuickBooks: ' + updateRes.getStatusCode() + ' ' + updateRes.getBody());
        }
    }
    
    private static Object getFieldValue(SObject obj, String fieldPath) {
        List<String> fields = fieldPath.split('\\.');
        SObject currentObj = obj;
        
        for (Integer i = 0; i < fields.size() - 1; i++) {
            String field = fields[i];
            currentObj = currentObj.getSObject(field);
            if (currentObj == null) return null;
        }
        
        return currentObj.get(fields[fields.size() - 1]);
    }
}