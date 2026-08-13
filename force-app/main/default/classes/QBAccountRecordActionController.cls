public with sharing class QBAccountRecordActionController {
    public class ActionResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String quickBooksId { get; set; }
    }

    @AuraEnabled
    public static ActionResponse syncToQuickBooks(Id accountId) {
        try {
            Account accountToSync = getAccountForOutboundSync(accountId);
            QBAccountService.SyncResult result = QBAccountService.syncAccountToQuickBooks(
                accountToSync,
                accountToSync.QuickbookID__c == null
            );
            String accountName = String.isNotBlank(accountToSync.Name) ? accountToSync.Name : result.quickBooksId;

            ActionResponse response = new ActionResponse();
            response.success = true;
            response.quickBooksId = result.quickBooksId;
            response.message = result.created
                ? 'Account synced to QuickBooks ' + accountName + '.'
                : 'Account updated in QuickBooks ' + accountName + '.';
            return response;
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBAccountRecordActionController.syncToQuickBooks',
                e,
                'Account',
                accountId
            );
            throw buildActionException(e);
        }
    }

    @AuraEnabled
    public static ActionResponse syncFromQuickBooks(Id accountId) {
        try {
            Account existingAccount = [
                SELECT Id, Name, QuickbookID__c, RecordTypeId
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];

            if (String.isBlank(existingAccount.QuickbookID__c)) {
                throw new AuraHandledException('This Account does not have a QuickBooks ID yet. Run Sync To QB first.');
            }

            Boolean isVendorAccount = isVendorAccount(existingAccount);
            String qbEntityName = isVendorAccount ? 'vendor' : 'customer';
            String responseKey = isVendorAccount ? 'Vendor' : 'Customer';

            HttpResponse response = QuickBooksAuthHandler.makeApiCall(
                'GET',
                '/' + qbEntityName + '/' + existingAccount.QuickbookID__c,
                null
            );

            if (response == null || response.getStatusCode() != 200) {
                throw new AuraHandledException(
                    getQuickBooksErrorMessage(response, 'QuickBooks ' + qbEntityName + ' could not be retrieved.')
                );
            }

            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
            Map<String, Object> accountData = responseMap == null
                ? null
                : (Map<String, Object>)responseMap.get(responseKey);

            if (accountData == null) {
                throw new AuraHandledException('QuickBooks returned an empty ' + qbEntityName + ' response.');
            }

            QBTriggerHandler.isAccountProcessing = true;
            try {
                Account accountToUpdate = new Account(
                    Id = existingAccount.Id,
                    QuickbookID__c = existingAccount.QuickbookID__c,
                    RecordTypeId = existingAccount.RecordTypeId
                );

                if (isVendorAccount) {
                    applyVendorToAccount(accountToUpdate, accountData);
                } else {
                    applyCustomerToAccount(accountToUpdate, accountData);
                }
                update accountToUpdate;

                if (!isVendorAccount && !isPersonAccountRecordType(existingAccount.RecordTypeId)) {
                    Contact contactToUpsert = buildContactFromCustomer(accountData, existingAccount.Id);
                    if (contactToUpsert != null) {
                        upsert contactToUpsert Contact.Email__c;
                    }
                }
            } finally {
                QBTriggerHandler.isAccountProcessing = false;
            }

            Account updatedAcc = [SELECT Id, Name FROM Account WHERE Id = :existingAccount.Id LIMIT 1];
            String accountName = String.isNotBlank(updatedAcc.Name) ? updatedAcc.Name : existingAccount.Name;

            ActionResponse actionResponse = new ActionResponse();
            actionResponse.success = true;
            actionResponse.quickBooksId = existingAccount.QuickbookID__c;
            actionResponse.message = 'Account synced from QuickBooks ' + accountName + '.';
            return actionResponse;
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBAccountRecordActionController.syncFromQuickBooks',
                e,
                'Account',
                accountId
            );
            throw buildActionException(e);
        }
    }

    private static Account getAccountForOutboundSync(Id accountId) {
        return QBAccountSelector.selectForOutbound(accountId);
    }

    // private static void applyCustomerToAccount(Account accountToUpdate, Map<String, Object> customerData) {
    //     Map<String, String> mapping = QBObjectMappings.getCustomerToAccountMapping();

    //     for (String qbField : mapping.keySet()) {
    //         Object qbValue = getNestedValue(customerData, qbField);
    //         if (qbValue != null) {
    //             accountToUpdate.put(mapping.get(qbField), qbValue);
    //         }
    //     }
    // }

    private static void applyCustomerToAccount(Account accountToUpdate, Map<String, Object> customerData) {
        Map<String, String> mapping = QBObjectMappings.getCustomerToAccountMapping();
        Id personRecordTypeId = isPersonAccountRecordType(accountToUpdate.RecordTypeId)
            ? accountToUpdate.RecordTypeId
            : null;
        QBCustomerAccountMapper.applyCustomer(
            accountToUpdate,
            customerData,
            mapping,
            personRecordTypeId
        );
    }

    private static void applyVendorToAccount(Account accountToUpdate, Map<String, Object> vendorData) {
        Map<String, String> mapping = QBObjectMappings.getVendorToAccountMapping();
        applyQuickBooksAccountData(accountToUpdate, vendorData, mapping);
    }

    private static void applyQuickBooksAccountData(Account accountToUpdate, Map<String, Object> accountData, Map<String, String> mapping) {
        Map<String, Schema.SObjectField> sfFieldMap = Schema.SObjectType.Account.fields.getMap();
        Boolean isPersonAccountRecord = isPersonAccountRecordType(accountToUpdate.RecordTypeId);

        for (String qbField : mapping.keySet()) {
            String sfField = mapping.get(qbField);
            Object qbValue = getNestedValue(accountData, qbField);
            
            if (qbValue != null && sfFieldMap.containsKey(sfField)) {
                Schema.DescribeFieldResult fieldDescribe = sfFieldMap.get(sfField).getDescribe();
                String resolvedFieldName = fieldDescribe.getName();
                Boolean isPersonOnlyField = resolvedFieldName.startsWith('Person')
                    || resolvedFieldName == 'FirstName'
                    || resolvedFieldName == 'LastName'
                    || resolvedFieldName.endsWith('__pc');
                if (isPersonOnlyField && !isPersonAccountRecord) {
                    continue;
                }

                Schema.DisplayType fieldType = fieldDescribe.getType();
                
                try {
                    if (fieldType == Schema.DisplayType.CURRENCY || fieldType == Schema.DisplayType.DOUBLE || fieldType == Schema.DisplayType.PERCENT) {
                        accountToUpdate.put(sfField, Decimal.valueOf(String.valueOf(qbValue)));
                    } 
                    else if (fieldType == Schema.DisplayType.DATE) {
                        accountToUpdate.put(sfField, Date.valueOf(String.valueOf(qbValue)));
                    } 
                    else if (fieldType == Schema.DisplayType.DATETIME) {
                        accountToUpdate.put(sfField, Datetime.valueOf(String.valueOf(qbValue)));
                    } 
                    else if (fieldType == Schema.DisplayType.BOOLEAN) {
                        accountToUpdate.put(sfField, Boolean.valueOf(String.valueOf(qbValue)));
                    } 
                    else {
                        accountToUpdate.put(sfField, qbValue);
                    }
                } catch (Exception e) {
                    System.debug('Error converting field ' + sfField + ': ' + e.getMessage());
                }
            }
        }
    }

    private static Boolean isPersonAccountRecordType(Id recordTypeId) {
        if (recordTypeId == null) {
            return false;
        }

        List<RecordType> recordTypes = [
            SELECT IsPersonType
            FROM RecordType
            WHERE Id = :recordTypeId
            LIMIT 1
        ];
        return !recordTypes.isEmpty() && recordTypes[0].IsPersonType;
    }

    private static Boolean isVendorAccount(Account accountRecord) {
        if (accountRecord == null || accountRecord.RecordTypeId == null) {
            return false;
        }

        try {
            List<RecordType> vendorRecordTypes = [
                SELECT Name, DeveloperName
                FROM RecordType
                WHERE Id = :accountRecord.RecordTypeId
                LIMIT 1
            ];

            if (vendorRecordTypes.isEmpty()) {
                return false;
            }

            RecordType accountRecordType = vendorRecordTypes[0];
            return accountRecordType.Name == 'Vendor' || accountRecordType.DeveloperName == 'Vendor';
        } catch (Exception e) {
            System.debug('Unable to resolve Account record type for QuickBooks sync: ' + e.getMessage());
            return false;
        }
    }
    
    private static Contact buildContactFromCustomer(Map<String, Object> customerData, Id accountId) {
        String qbId = (String)customerData.get('Id');
        if (String.isBlank(qbId)) {
            return null;
        }

        String emailAddress = '';
        Map<String, Object> primaryEmailAddr = (Map<String, Object>)customerData.get('PrimaryEmailAddr');
        if (primaryEmailAddr != null && primaryEmailAddr.get('Address') != null) {
            emailAddress = (String)primaryEmailAddr.get('Address');
        }

        Contact contact = new Contact();
        contact.Email__c = qbId + ':' + emailAddress;
        contact.AccountId = accountId;

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

        if (String.isNotBlank(emailAddress)) {
            contact.Email = emailAddress;
        }

        Map<String, Object> primaryPhone = (Map<String, Object>)customerData.get('PrimaryPhone');
        if (primaryPhone != null && primaryPhone.get('FreeFormNumber') != null) {
            contact.Phone = (String)primaryPhone.get('FreeFormNumber');
        }

        Map<String, Object> billAddr = (Map<String, Object>)customerData.get('BillAddr');
        if (billAddr != null) {
            if (billAddr.get('Line1') != null) {
                contact.MailingStreet = (String)billAddr.get('Line1');
            }
            if (billAddr.get('City') != null) {
                contact.MailingCity = (String)billAddr.get('City');
            }
            if (billAddr.get('CountrySubDivisionCode') != null) {
                contact.MailingState = (String)billAddr.get('CountrySubDivisionCode');
            }
            if (billAddr.get('PostalCode') != null) {
                contact.MailingPostalCode = (String)billAddr.get('PostalCode');
            }
            if (billAddr.get('Country') != null) {
                contact.MailingCountry = (String)billAddr.get('Country');
            }
        }

        if (customerData.get('Title') != null) {
            contact.Title = (String)customerData.get('Title');
        }

        return contact;
    }

    private static Object getNestedValue(Map<String, Object> data, String path) {
        Object current = data;

        for (String part : path.split('\\.')) {
            if (!(current instanceof Map<String, Object>)) {
                return null;
            }
            current = ((Map<String, Object>)current).get(part);
        }

        return current;
    }

    private static String getQuickBooksErrorMessage(HttpResponse response, String fallbackMessage) {
        if (response == null) {
            return fallbackMessage;
        }

        String body = response.getBody();
        if (String.isBlank(body)) {
            return fallbackMessage + ' HTTP ' + response.getStatusCode() + '.';
        }

        try {
            Map<String, Object> parsed = (Map<String, Object>)JSON.deserializeUntyped(body);
            if (parsed != null && parsed.containsKey('Fault')) {
                Map<String, Object> fault = (Map<String, Object>)parsed.get('Fault');
                List<Object> errors = fault == null ? null : (List<Object>)fault.get('Error');
                if (errors != null && !errors.isEmpty()) {
                    Map<String, Object> firstError = (Map<String, Object>)errors[0];
                    if (firstError.get('Detail') != null) {
                        return String.valueOf(firstError.get('Detail'));
                    }
                    if (firstError.get('Message') != null) {
                        return String.valueOf(firstError.get('Message'));
                    }
                }
            }
        } catch (Exception ex) {
            System.debug('Unable to parse QuickBooks error response: ' + ex.getMessage());
        }

        return fallbackMessage + ' HTTP ' + response.getStatusCode() + ': ' + body;
    }

    private static AuraHandledException buildActionException(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException)e;
        }

        return new AuraHandledException(e.getMessage());
    }
}