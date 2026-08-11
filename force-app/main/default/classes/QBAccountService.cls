public class QBAccountService {

    private Id defaultAccountRecordTypeId;
    public class SyncResult {
        public Id accountId { get; set; }
        public Boolean created { get; set; }
        public String quickBooksId { get; set; }
    }
    
    public static void syncAccountsToQuickBooks(List<Account> accounts, Boolean isInsert) {
        syncAccountsToQuickBooksShared(accounts, isInsert);
    }

    public static ConnectorExecutionResult syncAccountsToQuickBooksShared(List<Account> accounts, Boolean isInsert) {
        ConnectorExecutionResult result = ConnectorExecutionResult.success();
        result.processedCount = accounts == null ? 0 : accounts.size();
        for (Account acc : accounts) {
            try {
                syncAccountToQuickBooksInternal(acc, isInsert, true);
                result.successfulCount++;
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
                result.failedCount++;
                result.addError(e.getMessage());
                if (IntegrationRetryPolicy.isRetryable(e)) {
                    result.retryable = true;
                    result.retryDelaySeconds = 60;
                    if (acc != null && acc.Id != null) {
                        result.retryRecordIds.add(acc.Id);
                    }
                }
            }
        }
        return result;
    }
    
    public static SyncResult syncAccountToQuickBooks(Account acc, Boolean forceCreate) {
        return syncAccountToQuickBooksInternal(acc, forceCreate, false);
    }

    private static SyncResult syncAccountToQuickBooksInternal(
        Account acc,
        Boolean forceCreate,
        Boolean surfaceTypedFailure
    ) {
        if (acc == null) {
            throw new QBIntegrationException('Account is required for QuickBooks sync.');
        }
        
        SyncResult result = new SyncResult();
        result.accountId = acc.Id;
        
        if (forceCreate || acc.QuickbookID__c == null) {
            String qbCustomerId = createCustomerInQuickBooks(acc, surfaceTypedFailure);
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
            updateCustomerInQuickBooks(acc, surfaceTypedFailure);
            result.created = false;
            result.quickBooksId = acc.QuickbookID__c;
        }
        
        return result;
    }
    
    private static String createCustomerInQuickBooks(
        Account acc,
        Boolean surfaceTypedFailure
    ) {
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
            String errorMessage = 'Error creating record in QuickBooks: ' + res.getStatusCode() + ' ' + res.getBody();
            if (surfaceTypedFailure == true) {
                throw IntegrationRetryPolicy.exceptionForStatus(
                    res.getStatusCode(),
                    errorMessage
                );
            }
            throw new QBIntegrationException(errorMessage);
        }
    }
    
    private static void updateCustomerInQuickBooks(
        Account acc,
        Boolean surfaceTypedFailure
    ) {
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
            String errorMessage = 'Error querying record in QuickBooks: ' + queryRes.getStatusCode() + ' ' + queryRes.getBody();
            if (surfaceTypedFailure == true) {
                throw IntegrationRetryPolicy.exceptionForStatus(
                    queryRes.getStatusCode(),
                    errorMessage
                );
            }
            throw new QBIntegrationException(errorMessage);
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
            String errorMessage = 'Error updating record in QuickBooks: ' + updateRes.getStatusCode() + ' ' + updateRes.getBody();
            if (surfaceTypedFailure == true) {
                throw IntegrationRetryPolicy.exceptionForStatus(
                    updateRes.getStatusCode(),
                    errorMessage
                );
            }
            throw new QBIntegrationException(errorMessage);
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
