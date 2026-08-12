public class QBCustomerToAccountSyncBatch implements Database.Batchable<String>, Database.AllowsCallouts {
    
    private List<String> customerIds;
    private String lastSyncDate;
    private Id defaultAccountRecordTypeId;
    private Id personAccountRecordTypeId;
    private ConnectorExecutionResult sharedExecutionResult;
    private Set<String> sharedFailedReferences = new Set<String>();
    private Integer sharedAnonymousFailures = 0;
    
    public QBCustomerToAccountSyncBatch() {
        Datetime yesterday = Datetime.now().addDays(-1);
        this.lastSyncDate = yesterday.format('yyyy-MM-dd');
    }
    
    public QBCustomerToAccountSyncBatch(String syncDate) {
        this.lastSyncDate = syncDate;
    }

    /**
     * Executes the existing inbound behavior while exposing partial failures to
     * the shared runtime. The legacy Batchable entry points remain unchanged.
     */
    public ConnectorExecutionResult executeSharedScope(List<String> scope) {
        sharedExecutionResult = ConnectorExecutionResult.success();
        sharedFailedReferences.clear();
        sharedAnonymousFailures = 0;
        Integer submittedCount = scope == null ? 0 : scope.size();
        execute(null, scope);

        sharedExecutionResult.processedCount = submittedCount;
        Integer detectedFailures = Math.min(
            submittedCount,
            sharedFailedReferences.size() + sharedAnonymousFailures
        );
        if (String.isNotBlank(sharedExecutionResult.errorSummary) && detectedFailures == 0) {
            detectedFailures = Math.min(1, submittedCount);
        }
        sharedExecutionResult.failedCount = detectedFailures;
        sharedExecutionResult.successfulCount = Math.max(0, submittedCount - detectedFailures);
        ConnectorExecutionResult result = sharedExecutionResult;
        sharedExecutionResult = null;
        return result;
    }
    
    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> customerPayloads = new List<String>();

        try {
            customerPayloads = QuickBooksBulkQueryService.serializeRecords(
                QuickBooksBulkQueryService.queryUpdatedSince('Customer', lastSyncDate)
            );
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

        return customerPayloads;
    }
    
    public void execute(Database.BatchableContext bc, List<String> scope) {
        QBTriggerHandler.isAccountProcessing = true;
        
        try {
            List<Account> accountsToUpsert = new List<Account>();
            List<Contact> contactsToUpsert = new List<Contact>();
            Map<String, Map<String, Object>> customerDataMap = new Map<String, Map<String, Object>>();
            
            Boolean isPersonAccountEnabled = Schema.sObjectType.Account.fields.getMap().containsKey('IsPersonAccount');
            if (Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().containsKey('Customer')) {
                defaultAccountRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Customer').getRecordTypeId();
            }
            if (isPersonAccountEnabled && personAccountRecordTypeId == null) {
                List<RecordType> personRTs = [SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1];
                if (!personRTs.isEmpty()) {
                    personAccountRecordTypeId = personRTs[0].Id;
                }
            }
            
            for (String customerId : scope) {
                try {
                    Map<String, Object> customerData = hydrateCustomerData(customerId);
                    if (customerData != null) {
                        String resolvedCustomerId = (String) customerData.get('Id');
                        customerDataMap.put(resolvedCustomerId, customerData);
                        Account accountToSync = processCustomerData(customerData);
                            
                        if (accountToSync != null) {
                            accountsToUpsert.add(accountToSync);
                        } else {
                            recordSharedFailure(customerId, 'QuickBooks customer did not produce an Account record.');
                        }
                    } else {
                        recordSharedFailure(customerId, 'QuickBooks customer payload was blank or malformed.');
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
                    recordSharedFailure(
                        customerId,
                        e.getMessage(),
                        ConnectorInboundOperationExecutor.isRetryableException(e)
                    );
                }
            }
            
            Map<String, Id> qbIdToAccountIdMap = new Map<String, Id>();
            Map<String, Boolean> qbIdToIsPersonMap = new Map<String, Boolean>();
            
            if (!accountsToUpsert.isEmpty()) {
                Map<String, Account> dedupMap = new Map<String, Account>();
                for (Account a : accountsToUpsert) {
                    if (String.isNotBlank(a.QuickbookID__c)) {
                        dedupMap.put(a.QuickbookID__c, a);
                    }
                }
                List<Account> deduped = dedupMap.isEmpty() ? accountsToUpsert : dedupMap.values();
                Database.UpsertResult[] results = Database.upsert(deduped, Account.QuickbookID__c, false);
                ErrorLogUtility.logUpsertResults(
                    'QuickBooks',
                'QBCustomerToAccountSyncBatch.execute.upsertAccounts',
                'upsert',
                deduped,
                results,
                null,
                null
                    );
                Integer successCount = 0;

                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        successCount++;
                        Account upsertedAccount = deduped[i];
                        qbIdToAccountIdMap.put(upsertedAccount.QuickbookID__c, results[i].getId());

                        Boolean isPerson = isPersonAccountEnabled && upsertedAccount.RecordTypeId == personAccountRecordTypeId;
                        qbIdToIsPersonMap.put(upsertedAccount.QuickbookID__c, isPerson);
                    } else {
                        recordSharedFailure(
                            deduped[i].QuickbookID__c,
                            firstDatabaseError(results[i].getErrors())
                        );
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
                for (Integer i = 0; i < contactResults.size(); i++) {
                    if (!contactResults[i].isSuccess()) {
                        recordSharedFailure(
                            contactsToUpsert[i].External_Id__c,
                            firstDatabaseError(contactResults[i].getErrors())
                        );
                    }
                }
            }
            
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
        }
    }

    private void recordSharedFailure(String externalReference, String message) {
        recordSharedFailure(externalReference, message, false);
    }

    private void recordSharedFailure(String externalReference, String message, Boolean retryable) {
        if (sharedExecutionResult == null) {
            return;
        }
        if (String.isBlank(externalReference)) {
            sharedAnonymousFailures++;
        } else {
            sharedFailedReferences.add(externalReference);
        }
        sharedExecutionResult.addError(message);
        if (retryable == true) {
            sharedExecutionResult.retryable = true;
            sharedExecutionResult.retryDelaySeconds = 60;
        }
    }

    private static String firstDatabaseError(Database.Error[] errors) {
        return errors == null || errors.isEmpty()
            ? 'QuickBooks customer synchronization failed.'
            : errors[0].getStatusCode() + ': ' + errors[0].getMessage();
    }

    private Map<String, Object> hydrateCustomerData(String customerScopeValue) {
        if (String.isBlank(customerScopeValue)) {
            return null;
        }
        String trimmedValue = customerScopeValue.trim();
        if (trimmedValue.startsWith('{')) {
            return (Map<String, Object>) JSON.deserializeUntyped(trimmedValue);
        }
        // Scheduled/batch execution must receive hydrated payloads from start().
        // Single-record hydration remains in processSingleCustomer().
        return null;
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
            if (
                personAccountRecordTypeId != null &&
                QBCustomerAccountMapper.shouldCreatePersonAccount(customerData)
            ) {
                account.RecordTypeId = personAccountRecordTypeId;
            } else if (defaultAccountRecordTypeId != null) {
                account.RecordTypeId = defaultAccountRecordTypeId;
            }
        }
        
        account.Is_Synced__c = true;
        
        Map<String, String> mapping = QBObjectMappings.getCustomerToAccountMapping();
        
        QBCustomerAccountMapper.applyCustomer(
            account,
            customerData,
            mapping,
            personAccountRecordTypeId
        );
        
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
        String keyLower = fieldName.toLowerCase();
        Schema.SObjectField fieldToken = fields.get(keyLower);
        if (fieldToken == null) {
            fieldToken = fields.get('QuickBridgeTLG__' + keyLower);
        }
        if (fieldToken == null) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
        if (!fieldDescribe.isCreateable() && !fieldDescribe.isUpdateable()) {
            return;
        }

        // Skip person-account-only fields when this record is a business account.
        // Salesforce rejects DML with "Business Account may not use Person Account field X"
        // if any person-type field is set on a non-person account record type.
        // We detect this by checking whether the field's API name starts with 'Person'
        // (e.g. PersonEmail, PersonBirthdate) or is one of the shared name fields that
        // are only writable via person accounts (FirstName, LastName).
        String resolvedName = fieldDescribe.getName();
        Boolean isPersonOnlyField = resolvedName.startsWith('Person')
            || resolvedName == 'FirstName'
            || resolvedName == 'LastName'
            || resolvedName.endsWith('__pc');
        if (isPersonOnlyField) {
            Id rtId = (Id) record.get('RecordTypeId');
            if (personAccountRecordTypeId == null || rtId == null || rtId != personAccountRecordTypeId) {
                return;
            }
        }

        Schema.DisplayType displayType = fieldDescribe.getType();
        record.put(fieldDescribe.getName(), coerceValue(value, displayType));
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

    public void processSingleCustomer(String qboCustomerId) {
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', '/customer/' + qboCustomerId, null);
        if (res.getStatusCode() == 200) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> customer = (Map<String, Object>) data.get('Customer');
            Account acc = processCustomerData(customer);
            upsert acc Account.QuickbookID__c;
        } else {
            throw new CalloutException('Unable to fetch customer: ' + res.getBody());
        }
    }
}
