public with sharing class NetSuiteCustomerService {
  public class SyncSummary {
    @AuraEnabled public Integer recordsProcessed { get; set; }
    @AuraEnabled public Integer recordsFailed { get; set; }
    @AuraEnabled public String message { get; set; }

    public SyncSummary() {
      recordsProcessed = 0;
      recordsFailed = 0;
    }
  }

  public static SyncSummary syncCustomers(Datetime sinceDatetime, Integer batchSize) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableCustomerSync != true) {
      summary.message = 'NetSuite customer sync is disabled.';
      return summary;
    }

    List<Map<String, Object>> rows = NetSuiteApiClient.configured().suiteql(buildCustomerQuery(sinceDatetime, batchSize), null);
    List<Account> accounts = new List<Account>();
    Map<String, Map<String, Object>> sourceByExternalId = new Map<String, Map<String, Object>>();
    for (Map<String, Object> row : rows) {
      String externalId = externalId(row.get('id'));
      if (String.isBlank(externalId)) {
        summary.recordsFailed++;
        continue;
      }
      Account accountRecord = new Account();
      accountRecord.External_Id__c = externalId;
      accountRecord.Name = firstNonBlank(stringValue(row.get('companyname')), fullName(row));
      accountRecord.Phone = stringValue(row.get('phone'));
      accountRecord.BillingCity = stringValue(row.get('billcity'));
      if (String.isBlank(accountRecord.Name)) {
        accountRecord.Name = 'NetSuite Customer ' + stringValue(row.get('id'));
      }
      accounts.add(accountRecord);
      sourceByExternalId.put(externalId, row);
    }

    if (!accounts.isEmpty()) {
      Database.UpsertResult[] results = Database.upsert(accounts, Account.External_Id__c, false);
      ErrorLogUtility.logUpsertResults('NetSuite', 'NetSuiteCustomerService.syncCustomers', 'upsert', accounts, results, null, null);
      List<Contact> contacts = new List<Contact>();
      for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
          summary.recordsProcessed++;
          Map<String, Object> row = sourceByExternalId.get(accounts[i].External_Id__c);
          Contact contactRecord = contactFromRow(row, results[i].getId());
          if (contactRecord != null) {
            contacts.add(contactRecord);
          }
        } else {
          summary.recordsFailed++;
        }
      }
      upsertContacts(contacts, summary);
    }
    summary.message = 'NetSuite customer sync processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  public static SyncSummary exportCustomers(Set<Id> accountIds) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableCustomerSync != true || accountIds == null || accountIds.isEmpty()) {
      summary.message = 'NetSuite customer export skipped.';
      return summary;
    }
    List<Account> accounts = [
      SELECT Id, Name, Phone, BillingCity, External_Id__c, LastModifiedDate
      FROM Account
      WHERE Id IN :accountIds
    ];
    List<Account> updates = new List<Account>();
    for (Account accountRecord : accounts) {
      try {
        Map<String, Object> payload = NetSuiteRecordMapper.toNetSuitePayload(accountRecord, 'Account', 'Customer');
        if (String.isNotBlank(config.defaultSubsidiary)) {
          NetSuiteTransactionUtil.putReference(payload, 'subsidiary', config.defaultSubsidiary);
        }
        String internalId = NetSuiteTransactionUtil.writeRecord('customer', accountRecord.External_Id__c, payload);
        if (String.isNotBlank(internalId) && String.isBlank(accountRecord.External_Id__c)) {
          updates.add(new Account(Id = accountRecord.Id, External_Id__c = 'netsuite:' + internalId));
        }
        summary.recordsProcessed++;
      } catch (Exception e) {
        summary.recordsFailed++;
        NetSuiteErrorMapper.logException('NetSuiteCustomerService.exportCustomers', e);
      }
    }
    if (!updates.isEmpty()) {
      Database.update(updates, false);
    }
    summary.message = 'NetSuite customer export processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  public static SyncSummary exportContacts(Set<Id> contactIds) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableCustomerSync != true || contactIds == null || contactIds.isEmpty()) {
      summary.message = 'NetSuite contact export skipped.';
      return summary;
    }
    List<Contact> contacts = [
      SELECT Id, AccountId, FirstName, LastName, Email, Phone, External_Id__c
      FROM Contact
      WHERE Id IN :contactIds
    ];
    List<Contact> updates = new List<Contact>();
    for (Contact contactRecord : contacts) {
      try {
        Map<String, Object> payload = NetSuiteRecordMapper.toNetSuitePayload(contactRecord, 'Contact', 'Customer');
        if (!payload.containsKey('companyname')) {
          payload.put('companyname', firstNonBlank(contactRecord.LastName, 'Salesforce Contact'));
        }
        String internalId = NetSuiteTransactionUtil.writeRecord('customer', contactRecord.External_Id__c, payload);
        if (String.isNotBlank(internalId) && String.isBlank(contactRecord.External_Id__c)) {
          updates.add(new Contact(Id = contactRecord.Id, External_Id__c = 'netsuite:contact:' + internalId));
        }
        summary.recordsProcessed++;
      } catch (Exception e) {
        summary.recordsFailed++;
        NetSuiteErrorMapper.logException('NetSuiteCustomerService.exportContacts', e);
      }
    }
    if (!updates.isEmpty()) {
      Database.update(updates, false);
    }
    summary.message = 'NetSuite contact export processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  private static void upsertContacts(List<Contact> contacts, SyncSummary summary) {
    if (contacts.isEmpty()) {
      return;
    }
    Database.UpsertResult[] results = Database.upsert(contacts, Contact.External_Id__c, false);
    ErrorLogUtility.logUpsertResults('NetSuite', 'NetSuiteCustomerService.upsertContacts', 'upsert', contacts, results, null, null);
    for (Database.UpsertResult result : results) {
      if (!result.isSuccess()) {
        summary.recordsFailed++;
      }
    }
  }

  private static Contact contactFromRow(Map<String, Object> row, Id accountId) {
    String email = stringValue(row.get('email'));
    String firstName = stringValue(row.get('firstname'));
    String lastName = stringValue(row.get('lastname'));
    if (String.isBlank(email) && String.isBlank(firstName) && String.isBlank(lastName)) {
      return null;
    }
    Contact contactRecord = new Contact();
    contactRecord.AccountId = accountId;
    contactRecord.External_Id__c = 'netsuite:contact:' + stringValue(row.get('id'));
    contactRecord.FirstName = firstName;
    contactRecord.LastName = String.isBlank(lastName) ? firstNonBlank(stringValue(row.get('companyname')), 'NetSuite Contact') : lastName;
    contactRecord.Email = email;
    contactRecord.Phone = stringValue(row.get('phone'));
    return contactRecord;
  }

  private static String buildCustomerQuery(Datetime sinceDatetime, Integer batchSize) {
    Integer limitSize = batchSize == null || batchSize <= 0 ? 100 : Math.min(batchSize, 1000);
    String query = 'SELECT id, entityid, companyname, firstname, lastname, email, phone, billcity, lastmodifieddate FROM customer';
    if (sinceDatetime != null) {
      query += ' WHERE lastmodifieddate >= \'' + sinceDatetime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '\'';
    }
    return query + ' ORDER BY lastmodifieddate ASC FETCH FIRST ' + limitSize + ' ROWS ONLY';
  }

  private static String externalId(Object idValue) {
    String idText = stringValue(idValue);
    return String.isBlank(idText) ? null : 'netsuite:' + idText;
  }

  private static String fullName(Map<String, Object> row) {
    return String.join(new List<String>{
      stringValue(row.get('firstname')),
      stringValue(row.get('lastname'))
    }, ' ').trim();
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static String firstNonBlank(String firstValue, String secondValue) {
    return String.isBlank(firstValue) ? secondValue : firstValue;
  }
}
