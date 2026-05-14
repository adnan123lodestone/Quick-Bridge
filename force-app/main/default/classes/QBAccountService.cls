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
                ErrorLogUtility.logException(
                    'QuickBooks',
                    'QBAccountService.syncAccountsToQuickBooks',
                    e,
                    'Account',
                    acc == null ? null : acc.Id
                );
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
                } catch (DmlException e) {
                    for (Integer i = 0; i < e.getNumDml(); i++) {
                        ErrorLogUtility.logDmlFailure(
                            'QuickBooks',
                            'QBAccountService.syncAccountToQuickBooks.updateAccountQuickBooksId',
                            'update',
                            'Account',
                            acc.Id,
                            e.getDmlMessage(i),
                            null,
                            null
                        );
                    }
                    throw e;
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
        Map<String, Object> customerMap = new Map<String, Object>();
        Map<String, String> fieldMap = QBObjectMappings.getAccountToCustomerMapping();
        
        for (String sfField : fieldMap.keySet()) {
            String qbField = fieldMap.get(sfField);
            Object value = getFieldValue(acc, sfField);
            
            if (value != null) {
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
        
        if (!customerMap.containsKey('DisplayName')) {
            customerMap.put('DisplayName', acc.Name);
        }
        if (!customerMap.containsKey('FullyQualifiedName')) {
            customerMap.put('FullyQualifiedName', acc.Name);
        }
        
        String endpoint = '/customer'; // Default
        String recordTypeName = 'Customer'; 
        
        if (acc.RecordTypeId != null) {
            recordTypeName = Schema.SObjectType.Account.getRecordTypeInfosById().get(acc.RecordTypeId).getName();
            if (recordTypeName == 'Vendor') {
                endpoint = '/vendor';
            }
        }
        
        Boolean isPersonAccountEnabled = Schema.sObjectType.Account.fields.getMap().containsKey('IsPersonAccount');
        Boolean isPersonAccount = false;
        
        if (recordTypeName != 'Vendor') {
            try {
                if (isPersonAccountEnabled && acc.getPopulatedFieldsAsMap().containsKey('IsPersonAccount')) {
                    isPersonAccount = (Boolean)acc.get('IsPersonAccount');
                }
            } catch (Exception e) {}
        }
        
        if (isPersonAccount) {
            if (acc.getPopulatedFieldsAsMap().containsKey('FirstName') && acc.get('FirstName') != null) {
                customerMap.put('GivenName', acc.get('FirstName'));
            }
            if (acc.getPopulatedFieldsAsMap().containsKey('LastName') && acc.get('LastName') != null) {
                customerMap.put('FamilyName', acc.get('LastName'));
            }
            customerMap.put('CompanyName', '');
            
            if (acc.getPopulatedFieldsAsMap().containsKey('PersonEmail') && acc.get('PersonEmail') != null) {
                Map<String, Object> emailMap = new Map<String, Object>();
                emailMap.put('Address', acc.get('PersonEmail'));
                customerMap.put('PrimaryEmailAddr', emailMap);
            }
        } else {
            if (!customerMap.containsKey('CompanyName')) {
                customerMap.put('CompanyName', acc.Name);
            }
        }
        
        customerMap.put('Notes', String.valueOf(acc.Id));
        String requestBody = JSON.serialize(customerMap);
        System.debug('Creating record in QuickBooks: ' + requestBody);
        
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', endpoint, requestBody);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            
            String responseKey = (endpoint == '/vendor') ? 'Vendor' : 'Customer';
            Map<String, Object> customerResponse = (Map<String, Object>)responseMap.get(responseKey);
            
            return (String)customerResponse.get('Id');
        } else {
            ErrorLogUtility.logCalloutFailure(
                'QuickBooks',
                'QBAccountService.createCustomerInQuickBooks',
                'Error creating record in QuickBooks: ' + res.getStatusCode() + ' ' + res.getBody(),
                res.getStatusCode(),
                'Account',
                acc == null ? null : acc.Id
            );
            throw new QBIntegrationException('Error creating record in QuickBooks: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }
    
    private static void updateCustomerInQuickBooks(Account acc) {
        String endpoint = '/customer';
        String recordTypeName = 'Customer'; 
        
        if (acc.RecordTypeId != null) {
            recordTypeName = Schema.SObjectType.Account.getRecordTypeInfosById().get(acc.RecordTypeId).getName();
            if (recordTypeName == 'Vendor') {
                endpoint = '/vendor';
            }
        }
        
        HttpResponse queryRes = QuickBooksAuthHandler.makeApiCall('GET', endpoint + '/' + acc.QuickbookID__c, null);
        
        if (queryRes.getStatusCode() != 200) {
            ErrorLogUtility.logCalloutFailure(
                'QuickBooks',
                'QBAccountService.updateCustomerInQuickBooks.query',
                'Error querying record in QuickBooks: ' + queryRes.getStatusCode() + ' ' + queryRes.getBody(),
                queryRes.getStatusCode(),
                'Account',
                acc == null ? null : acc.Id
            );
            throw new QBIntegrationException('Error querying record in QuickBooks: ' + queryRes.getStatusCode() + ' ' + queryRes.getBody());
        }
        
        Map<String, Object> existingCustomer = (Map<String, Object>)JSON.deserializeUntyped(queryRes.getBody());
        String responseKey = (endpoint == '/vendor') ? 'Vendor' : 'Customer';
        Map<String, Object> customerMap = (Map<String, Object>)existingCustomer.get(responseKey);
        
        Map<String, String> fieldMap = QBObjectMappings.getAccountToCustomerMapping();
        
        for (String sfField : fieldMap.keySet()) {
            String qbField = fieldMap.get(sfField);
            Object value = getFieldValue(acc, sfField);
            
            if (value != null) {
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
        
        Boolean isPersonAccountEnabled = Schema.sObjectType.Account.fields.getMap().containsKey('IsPersonAccount');
        Boolean isPersonAccount = false;
        
        if (recordTypeName != 'Vendor') {
            try {
                if (isPersonAccountEnabled && acc.getPopulatedFieldsAsMap().containsKey('IsPersonAccount')) {
                    isPersonAccount = (Boolean)acc.get('IsPersonAccount');
                }
            } catch (Exception e) {}
        }
        
        if (isPersonAccount) {
            if (acc.getPopulatedFieldsAsMap().containsKey('FirstName') && acc.get('FirstName') != null) {
                customerMap.put('GivenName', acc.get('FirstName'));
            }
            if (acc.getPopulatedFieldsAsMap().containsKey('LastName') && acc.get('LastName') != null) {
                customerMap.put('FamilyName', acc.get('LastName'));
            }
            customerMap.put('CompanyName', '');
            
            if (acc.getPopulatedFieldsAsMap().containsKey('PersonEmail') && acc.get('PersonEmail') != null) {
                Map<String, Object> emailMap = new Map<String, Object>();
                emailMap.put('Address', acc.get('PersonEmail'));
                customerMap.put('PrimaryEmailAddr', emailMap);
            }
        } else {
            if (!customerMap.containsKey('CompanyName')) {
                customerMap.put('CompanyName', acc.Name);
            }
        }
        
        customerMap.put('sparse', false);
        customerMap.put('Notes', String.valueOf(acc.Id));
        String requestBody = JSON.serialize(customerMap);
        System.debug('Updating record in QuickBooks: ' + requestBody);
        
        HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', endpoint, requestBody);
        
        if (updateRes.getStatusCode() != 200) {
            ErrorLogUtility.logCalloutFailure(
                'QuickBooks',
                'QBAccountService.updateCustomerInQuickBooks.update',
                'Error updating record in QuickBooks: ' + updateRes.getStatusCode() + ' ' + updateRes.getBody(),
                updateRes.getStatusCode(),
                'Account',
                acc == null ? null : acc.Id
            );
            throw new QBIntegrationException('Error updating record in QuickBooks: ' + updateRes.getStatusCode() + ' ' + updateRes.getBody());
        }
    }
    
    private static Object getFieldValue(SObject obj, String fieldPath) {
        try {
            if (obj == null || String.isBlank(fieldPath)) {
                return null;
            }
            
            List<String> fields = fieldPath.split('\\.');
            SObject currentObj = obj;
            
            for (Integer i = 0; i < fields.size() - 1; i++) {
                String field = fields[i];
                if (!currentObj.getSObjectType().getDescribe().fields.getMap().containsKey(field)) {
                    return null;
                }
                currentObj = currentObj.getSObject(field);
                if (currentObj == null) {
                    return null;
                }
            }
            
            String leafField = fields[fields.size() - 1];
            if (!currentObj.getSObjectType().getDescribe().fields.getMap().containsKey(leafField)) {
                return null;
            }
            return currentObj.get(leafField);
        } catch (Exception e) {
            return null;
        }
    }
}