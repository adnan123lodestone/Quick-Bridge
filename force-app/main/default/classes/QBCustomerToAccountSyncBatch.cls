public class QBCustomerToAccountSyncBatch implements Database.Batchable<String>, Database.AllowsCallouts {
    
    private List<String> customerIds;
   private String lastSyncDate;
    
public QBCustomerToAccountSyncBatch() {
    // Set lastSyncDate to yesterday in 'YYYY-MM-DD' format
    Datetime yesterday = Datetime.now().addDays(-1);
    this.lastSyncDate = yesterday.format('YYYY-MM-d');
}
    
public QBCustomerToAccountSyncBatch(String syncDate) {
    this.lastSyncDate = syncDate;
}
    
public Iterable<String> start(Database.BatchableContext bc) {
    List<String> customerIdsList = new List<String>();
    
    try {
        // Construct the query
        String query = 'select * from Customer Where Metadata.LastUpdatedTime > \'' + lastSyncDate + '\'';
        
        // URL encode the query and construct the full resource path
        String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
        String resourcePath = '/query?query=' + encodedQuery + '&minorversion=65';
        
        // Make the API call
        HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', resourcePath, null);
            
            // Process the response
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
                                    } else {
                                        System.debug('Customer record missing Id field: ' + JSON.serialize(customer));
                                    }
                                }
                            }
                        }
                    }
                }
            } else if (response != null) {
                System.debug('QuickBooks API returned status code: ' + response.getStatusCode());
                System.debug('Response body: ' + response.getBody());
            }
        } catch (Exception e) {
            System.debug('Error querying QuickBooks customers: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
        
        return customerIdsList;
    }
    
    public void execute(Database.BatchableContext bc, List<String> scope) {
        // Set trigger prevention flag
        QBTriggerHandler.isAccountProcessing = true;
        
        try {
            List<Account> accountsToUpsert = new List<Account>();
            List<Contact> contactsToUpsert = new List<Contact>();
            Map<String, Map<String, Object>> customerDataMap = new Map<String, Map<String, Object>>();
            
            // First, get all customer data
            for (String customerId : scope) {
                try {
                    // Get detailed customer data from QuickBooks
                    HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', '/customer/' + customerId, null);
                    
                    if (response.getStatusCode() == 200) {
                        Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                        Map<String, Object> customerData = (Map<String, Object>)responseMap.get('Customer');
                        
                        if (customerData != null) {
                            customerDataMap.put(customerId, customerData);
                            
                            Account accountToSync = processCustomerData(customerData);
                            if (accountToSync != null) {
                                accountsToUpsert.add(accountToSync);
                            }
                        }
                    }
                } catch (Exception e) {
                    System.debug('Error processing customer ' + customerId + ': ' + e.getMessage());
                }
            }
            
            // Upsert accounts first
            Map<String, Id> qbIdToAccountIdMap = new Map<String, Id>();
            if (!accountsToUpsert.isEmpty()) {
                Database.UpsertResult[] results = Database.upsert(accountsToUpsert, Account.QuickbookID__c, false);
                
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        Account upsertedAccount = accountsToUpsert[i];
                        qbIdToAccountIdMap.put(upsertedAccount.QuickbookID__c, results[i].getId());
                    } else {
                        System.debug('Failed to upsert account: ' + results[i].getErrors());
                    }
                }
            }
            
            // Now create contacts for each successfully upserted account
            for (String customerId : customerDataMap.keySet()) {
                if (qbIdToAccountIdMap.containsKey(customerId)) {
                    Contact contactToSync = processContactData(customerDataMap.get(customerId), qbIdToAccountIdMap.get(customerId));
                    if (contactToSync != null) {
                        contactsToUpsert.add(contactToSync);
                    }
                }
            }
            
            // Upsert contacts
            if (!contactsToUpsert.isEmpty()) {
                Database.UpsertResult[] contactResults = Database.upsert(contactsToUpsert, Contact.Email__c, false);
                
                for (Integer i = 0; i < contactResults.size(); i++) {
                    if (!contactResults[i].isSuccess()) {
                        System.debug('Failed to upsert contact: ' + contactResults[i].getErrors());
                    }
                }
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
        
        // Check if account already exists
        List<Account> existingAccounts = [SELECT Id, QuickbookID__c FROM Account WHERE QuickbookID__c = :qbId LIMIT 1];
        
        Account account;
        if (!existingAccounts.isEmpty()) {
            account = existingAccounts[0];
        } else {
            account = new Account();
            account.QuickbookID__c = qbId;
        }
        
        // Map QuickBooks customer fields to Salesforce account fields
        Map<String, String> mapping = QBObjectMappings.getCustomerToAccountMapping();
        
        for (String qbField : mapping.keySet()) {
            String sfField = mapping.get(qbField);
            Object qbValue = getNestedValue(customerData, qbField);
            
            if (qbValue != null) {
                account.put(sfField, qbValue);
            }
        }
        
        return account;
    }
    
    private Contact processContactData(Map<String, Object> customerData, Id accountId) {
        String qbId = (String)customerData.get('Id');
        
        // Create unique email identifier to avoid duplicates
        String emailAddress = '';
        Map<String, Object> primaryEmailAddr = (Map<String, Object>)customerData.get('PrimaryEmailAddr');
        if (primaryEmailAddr != null && primaryEmailAddr.get('Address') != null) {
            emailAddress = (String)primaryEmailAddr.get('Address');
        }
        
        String uniqueEmailId = qbId + ':' + emailAddress;
        
        // Check if contact already exists
        List<Contact> existingContacts = [SELECT Id, Email__c FROM Contact WHERE Email__c = :uniqueEmailId LIMIT 1];
        
        Contact contact;
        if (!existingContacts.isEmpty()) {
            contact = existingContacts[0];
        } else {
            contact = new Contact();
            contact.Email__c = uniqueEmailId; // External ID field
        }
        
        // Set Account relationship
        contact.AccountId = accountId;
        
        // Map basic contact fields
        String firstName = (String)customerData.get('GivenName');
        String lastName = (String)customerData.get('FamilyName');
        
        // Handle Last Name requirement - if FamilyName not available, use GivenName
        if (String.isNotBlank(lastName)) {
            contact.LastName = lastName;
        } else if (String.isNotBlank(firstName)) {
            contact.LastName = firstName; // Use GivenName as LastName if FamilyName is not available
        } else {
            contact.LastName = 'Unknown'; // Fallback if neither is available
        }
        
        if (String.isNotBlank(firstName)) {
            contact.FirstName = firstName;
        }
        
        // Map email
        if (String.isNotBlank(emailAddress)) {
            contact.Email = emailAddress;
        }
        
        // Map phone
        Map<String, Object> primaryPhone = (Map<String, Object>)customerData.get('PrimaryPhone');
        if (primaryPhone != null && primaryPhone.get('FreeFormNumber') != null) {
            contact.Phone = (String)primaryPhone.get('FreeFormNumber');
        }
        
        // Map address fields
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
}