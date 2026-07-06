public with sharing class NetSuiteInvoiceService {
  public class SyncSummary {
    @AuraEnabled public Integer recordsProcessed { get; set; }
    @AuraEnabled public Integer recordsFailed { get; set; }
    @AuraEnabled public String message { get; set; }
    public SyncSummary() {
      recordsProcessed = 0;
      recordsFailed = 0;
    }
  }

  public static SyncSummary syncInvoices(Datetime sinceDatetime, Integer batchSize) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableInvoiceSync != true) {
      summary.message = 'NetSuite invoice sync is disabled.';
      return summary;
    }
    List<Map<String, Object>> rows = NetSuiteApiClient.configured().suiteql(buildQuery(sinceDatetime, batchSize), null);
    List<Invoice__c> invoices = new List<Invoice__c>();
    for (Map<String, Object> row : rows) {
      invoices.add((Invoice__c) NetSuiteRecordMapper.toSalesforceRecord('Invoice__c', 'Invoice', row));
    }
    if (!invoices.isEmpty()) {
      Database.UpsertResult[] results = Database.upsert(invoices, Invoice__c.External_Id__c, false);
      ErrorLogUtility.logUpsertResults('NetSuite', 'NetSuiteInvoiceService.syncInvoices', 'upsert', invoices, results, null, null);
      count(results, summary);
    }
    summary.message = 'NetSuite invoice sync processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  public static SyncSummary exportInvoices(Set<Id> invoiceIds) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableInvoiceSync != true || invoiceIds == null || invoiceIds.isEmpty()) {
      summary.message = 'NetSuite invoice export skipped.';
      return summary;
    }
    List<Invoice__c> invoices = [
      SELECT Id, Amount__c, Due_Date__c, Email__c, External_Id__c, Invoice_Date__c, Reference_number__c, Status__c, Related_Account__c, Related_Account__r.External_Id__c
      FROM Invoice__c
      WHERE Id IN :invoiceIds
    ];
    List<Invoice__c> updates = new List<Invoice__c>();
    for (Invoice__c invoiceRecord : invoices) {
      try {
        Map<String, Object> payload = NetSuiteRecordMapper.toNetSuitePayload(invoiceRecord, 'Invoice__c', 'Invoice');
        String customerId = invoiceRecord.Related_Account__r == null ? null : NetSuiteTransactionUtil.internalIdFromExternalId(invoiceRecord.Related_Account__r.External_Id__c);
        NetSuiteTransactionUtil.putReference(payload, 'entity', customerId);
        NetSuiteTransactionUtil.putReference(payload, 'account', config.arAccountReference);
        String internalId = NetSuiteTransactionUtil.writeRecord('invoice', invoiceRecord.External_Id__c, payload);
        if (String.isNotBlank(internalId) && String.isBlank(invoiceRecord.External_Id__c)) {
          updates.add(new Invoice__c(Id = invoiceRecord.Id, External_Id__c = 'netsuite:' + internalId));
        }
        summary.recordsProcessed++;
      } catch (Exception e) {
        summary.recordsFailed++;
        NetSuiteErrorMapper.logException('NetSuiteInvoiceService.exportInvoices', e);
      }
    }
    if (!updates.isEmpty()) {
      Database.update(updates, false);
    }
    summary.message = 'NetSuite invoice export processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  private static String buildQuery(Datetime sinceDatetime, Integer batchSize) {
    Integer limitSize = batchSize == null || batchSize <= 0 ? 100 : Math.min(batchSize, 1000);
    String query = 'SELECT id, tranid, trandate, status, foreigntotal AS total, amountremaining, lastmodifieddate FROM transaction WHERE type = \'CustInvc\'';
    if (sinceDatetime != null) {
      query += ' AND lastmodifieddate >= \'' + sinceDatetime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '\'';
    }
    return query + ' ORDER BY lastmodifieddate ASC FETCH FIRST ' + limitSize + ' ROWS ONLY';
  }

  private static void count(Database.UpsertResult[] results, SyncSummary summary) {
    for (Database.UpsertResult result : results) {
      if (result.isSuccess()) summary.recordsProcessed++;
      else summary.recordsFailed++;
    }
  }
}
