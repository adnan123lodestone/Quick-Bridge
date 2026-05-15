public class QBCustomerToAccountSyncBatch implements Database.Batchable<String>, Database.AllowsCallouts {
    
    private List<String> customerIds;
    private String lastSyncDate;
    private Id defaultAccountRecordTypeId;
    
    public QBCustomerToAccountSyncBatch() {
        Datetime yesterday = Datetime.now().addDays(-1);
        this.lastSyncDate = yesterday.format('yyyy-MM-dd');
    }
    
    public QBCustomerToAccountSyncBatch(String syncDate) {
        this.lastSyncDate = syncDate;
    }
    
    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> customerIdsList = new List<String>();
        
        try {
            String query = 'select * from Customer Where Metadata.LastUpdatedTime > \'' + lastSyncDate + '\'';
            String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
            String resourcePath = '/query?query=' + encodedQuery + '&minorversion=65';
            
            HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', resourcePath, null);
            
            if (response != null && response.getStatusCode() == 200 && String.isNotBlank(response.getBody())) {
                Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                
                if (responseMap != null && responseMap.containsKey('QueryResponse')) {
                    Map<String, Object> queryResponse = (Map<String, Object>)responseMap.get('QueryResponse');
                    
                    if (queryResponse != null && queryResponse.containsKey('Customer')) {
                        List<Object> customers = (List<Object>)queryResponse.get('Customer');
                        if (customers != null) {
                            for (Object customerObj : customers) {
                                if (customerObj != null) {
                                    Map<String, Object> customer = (Map<String, Object>)customerObj;
                                    if (customer.containsKey('Id')) {
                                        customerIdsList.add((String)customer.get('Id'));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error querying QuickBooks customers: ' + e.getMessage());
            ErrorLogUtility.logException(
                'QuickBooks',
            'QBCustomerToAccountSyncBatch.start',
            e,
            null,
            null
                );
        }
        
        return customerIdsList;
    }
    
    public void execute(Database.BatchableContext bc, List<String> scope) {
        IntegrationUsageService.assertCanConsumeTask('QuickBooks', scope == null ? 1 : scope.size());
        QBTriggerHandler.isAccountProcessing = true;
        
        try {
            List<Account> accountsToUpsert = new List<Account>();
            List<Contact> contactsToUpsert = new List<Contact>();
            Map<String, Map<String, Object>> customerDataMap = new Map<String, Map<String, Object>>();
            
            Boolean isPersonAccountEnabled = Schema.sObjectType.Account.fields.getMap().containsKey('IsPersonAccount');
            if (Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().containsKey('Customer')) {
                defaultAccountRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Customer').getRecordTypeId();
            }
            Id personAccountRecordTypeId = null;
            if (isPersonAccountEnabled) {
                List<RecordType> personRTs = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1];
                if (!personRTs.isEmpty()) {
                    personAccountRecordTypeId = personRTs[0].Id;
                }
            }
            
            for (String customerId : scope) {
                try {
                    HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', '/customer/' + customerId, null);
                    
                    if (response.getStatusCode() == 200) {
                        Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                        Map<String, Object> customerData = (Map<String, Object>)responseMap.get('Customer');
                        
                        if (customerData != null) {
                            customerDataMap.put(customerId, customerData);
                            Account accountToSync = processCustomerData(customerData);
                            
                            if (accountToSync != null) {
                                String companyName = (String)customerData.get('CompanyName');
                                
                                if (isPersonAccountEnabled && personAccountRecordTypeId != null && String.isBlank(companyName)) {
                                    accountToSync.RecordTypeId = personAccountRecordTypeId;
                                    
                                    String fName = (String)customerData.get('GivenName');
                                    String lName = (String)customerData.get('FamilyName');
                                    
                                    if (String.isNotBlank(lName)) {
                                        accountToSync.put('LastName', lName);
                                        if (String.isNotBlank(fName)) accountToSync.put('FirstName', fName);
                                    } else if (String.isNotBlank(fName)) {
                                        accountToSync.put('LastName', fName);
                                    } else {
                                        accountToSync.put('LastName', 'Unknown');
                                    }
                                    
                                    Map<String, Object> primaryEmailAddr = (Map<String, Object>)customerData.get('PrimaryEmailAddr');
                                    if (primaryEmailAddr != null && primaryEmailAddr.get('Address') != null) {
                                        accountToSync.put('PersonEmail', (String)primaryEmailAddr.get('Address'));
                                    }
                                }
                                
                                accountsToUpsert.add(accountToSync);
                            }
                        }
                    }
                } catch (Exception e) {
                    System.debug('Error processing customer ' + customerId + ': ' + e.getMessage());
                    ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
                    context.gatewayName = 'QuickBooks';
                    context.classMethodName = 'QBCustomerToAccountSyncBatch.execute.processCustomer';
                    context.errorMessage = e.getTypeName() + ': ' + e.getMessage();
                    context.stackTrace = e.getStackTraceString();
                    context.sourceObjectApiName = 'Account';
                    context.sourceRecordIdText = customerId;
                    context.errorCategory = 'Code Exception';
                    context.externalReference = customerId;
                    ErrorLogUtility.logError(context);
                }
            }
            
            Map<String, Id> qbIdToAccountIdMap = new Map<String, Id>();
            Map<String, Boolean> qbIdToIsPersonMap = new Map<String, Boolean>();
            
            if (!accountsToUpsert.isEmpty()) {
                Database.UpsertResult[] results = Database.upsert(accountsToUpsert, Account.QuickbookID__c, false);
                ErrorLogUtility.logUpsertResults(
                    'QuickBooks',
                'QBCustomerToAccountSyncBatch.execute.upsertAccounts',
                'upsert',
                accountsToUpsert,
                results,
                null,
                null
                    );
                Integer successCount = 0;
                
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        successCount++;
                        Account upsertedAccount = accountsToUpsert[i];
                        qbIdToAccountIdMap.put(upsertedAccount.QuickbookID__c, results[i].getId());
                        
                        Boolean isPerson = isPersonAccountEnabled && upsertedAccount.RecordTypeId == personAccountRecordTypeId;
                        qbIdToIsPersonMap.put(upsertedAccount.QuickbookID__c, isPerson);
                    }
                }
                IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', successCount);
            }
            
            for (String customerId : customerDataMap.keySet()) {
                if (qbIdToAccountIdMap.containsKey(customerId)) {
                    Boolean isPerson = qbIdToIsPersonMap.get(customerId) == true;
                    
                    if (!isPerson) {
                        Contact contactToSync = processContactData(customerDataMap.get(customerId), qbIdToAccountIdMap.get(customerId));
                        if (contactToSync != null) {
                            contactsToUpsert.add(contactToSync);
                        }
                    }
                }
            }
            
            if (!contactsToUpsert.isEmpty()) {
                Database.UpsertResult[] contactResults = Database.upsert(contactsToUpsert, Contact.External_Id__c, false);
                ErrorLogUtility.logUpsertResults(
                    'QuickBooks',
                'QBCustomerToAccountSyncBatch.execute.upsertContacts',
                'upsert',
                contactsToUpsert,
                contactResults,
                null,
                null
                    );
            }
            
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('QBCustomerToAccountSyncBatch completed');
    }
    
    private Account processCustomerData(Map<String, Object> customerData) {
        String qbId = (String)customerData.get('Id');
        
        List<Account> existingAccounts = [SELECT Id, RecordTypeId, QuickbookID__c FROM Account WHERE QuickbookID__c = :qbId LIMIT 1];
        
        Account account;
        if (!existingAccounts.isEmpty()) {
            account = existingAccounts[0];
        } else {
            account = new Account();
            if (defaultAccountRecordTypeId != null) {
                account.RecordTypeId = defaultAccountRecordTypeId;
            }
        }
        
        account.Is_Synced__c = true;
        
        Map<String, String> mapping = QBObjectMappings.getCustomerToAccountMapping();
        
        for (String qbField : mapping.keySet()) {
            String sfField = mapping.get(qbField);
            Object qbValue = getNestedValue(customerData, qbField);
            
            if (qbValue != null) {
                try {
                    putFieldValue(account, sfField, qbValue);
                } catch(Exception e) {}
            }
        }
        
        account.QuickbookID__c = qbId;
        
        return account;
    }
    
    private Contact processContactData(Map<String, Object> customerData, Id accountId) {
        String qbId = (String)customerData.get('Id');
        String contactExternalId = qbId + '_primary';
        
        List<Contact> existingContacts = [SELECT Id, External_Id__c FROM Contact WHERE External_Id__c = :contactExternalId LIMIT 1];
        
        Contact contact;
        if (!existingContacts.isEmpty()) {
            contact = existingContacts[0];
        } else {
            contact = new Contact();
            contact.External_Id__c = contactExternalId;
        }
        
        contact.AccountId = accountId;
        contact.Account_External_Id__c = qbId;
        contact.Is_Synced__c = true;
        contact.Is_Primary__c = true;
        
        String firstName = (String)customerData.get('GivenName');
        String lastName = (String)customerData.get('FamilyName');
        
        if (String.isNotBlank(lastName)) {
            contact.LastName = lastName;
        } else if (String.isNotBlank(firstName)) {
            contact.LastName = firstName;
        } else {
            contact.LastName = 'Unknown';
        }
        
        if (String.isNotBlank(firstName)) {
            contact.FirstName = firstName;
        }
        
        Map<String, Object> primaryEmailAddr = (Map<String, Object>)customerData.get('PrimaryEmailAddr');
        if (primaryEmailAddr != null && primaryEmailAddr.get('Address') != null) {
            contact.Email = (String)primaryEmailAddr.get('Address');
        }
        
        Map<String, Object> primaryPhone = (Map<String, Object>)customerData.get('PrimaryPhone');
        if (primaryPhone != null && primaryPhone.get('FreeFormNumber') != null) {
            contact.Phone = (String)primaryPhone.get('FreeFormNumber');
        }
        
        Map<String, Object> billAddr = (Map<String, Object>)customerData.get('BillAddr');
        if (billAddr != null) {
            if (billAddr.get('Line1') != null) contact.MailingStreet = (String)billAddr.get('Line1');
            if (billAddr.get('City') != null) contact.MailingCity = (String)billAddr.get('City');
            if (billAddr.get('CountrySubDivisionCode') != null) contact.MailingState = (String)billAddr.get('CountrySubDivisionCode');
            if (billAddr.get('PostalCode') != null) contact.MailingPostalCode = (String)billAddr.get('PostalCode');
            if (billAddr.get('Country') != null) contact.MailingCountry = (String)billAddr.get('Country');
        }
        
        if (customerData.get('Title') != null) {
            contact.Title = (String)customerData.get('Title');
        }
        
        return contact;
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