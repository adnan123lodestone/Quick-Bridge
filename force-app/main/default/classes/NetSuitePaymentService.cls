public with sharing class NetSuitePaymentService {
  public class SyncSummary {
    @AuraEnabled public Integer recordsProcessed { get; set; }
    @AuraEnabled public Integer recordsFailed { get; set; }
    @AuraEnabled public String message { get; set; }
    public SyncSummary() {
      recordsProcessed = 0;
      recordsFailed = 0;
    }
  }

  public static SyncSummary syncPayments(Datetime sinceDatetime, Integer batchSize) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enablePaymentSync != true) {
      summary.message = 'NetSuite payment sync is disabled.';
      return summary;
    }
    List<Map<String, Object>> rows = NetSuiteApiClient.configured().suiteql(buildQuery(sinceDatetime, batchSize), null);
    List<Portal_Payment_Transaction__c> payments = new List<Portal_Payment_Transaction__c>();
    for (Map<String, Object> row : rows) {
      Portal_Payment_Transaction__c paymentRecord = new Portal_Payment_Transaction__c();
      paymentRecord.Payment_Type__c = 'Unknown';
      paymentRecord.Gateway_Reference_Number__c = stringValue(row.get('tranid'));
      paymentRecord.Gateway_Amount__c = decimalValue(row.get('payment'));
      paymentRecord.Gateway_Event_Id__c = 'netsuite:' + stringValue(row.get('id'));
      payments.add(paymentRecord);
    }
    if (!payments.isEmpty()) {
      Database.SaveResult[] results = Database.insert(payments, false);
      for (Database.SaveResult result : results) {
        if (result.isSuccess()) summary.recordsProcessed++;
        else summary.recordsFailed++;
      }
    }
    summary.message = 'NetSuite payment sync processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  public static SyncSummary exportPayments(Set<Id> paymentIds) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enablePaymentSync != true || paymentIds == null || paymentIds.isEmpty()) {
      summary.message = 'NetSuite payment export skipped.';
      return summary;
    }
    List<Portal_Payment_Transaction__c> payments = [
      SELECT Id, Gateway_Amount__c, Gateway_Reference_Number__c, Gateway_Event_Id__c, Payment_Type__c, Order__c, Order__r.Account.External_Id__c
      FROM Portal_Payment_Transaction__c
      WHERE Id IN :paymentIds
    ];
    for (Portal_Payment_Transaction__c paymentRecord : payments) {
      try {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('payment', paymentRecord.Gateway_Amount__c);
        payload.put('tranid', paymentRecord.Gateway_Reference_Number__c);
        String customerId = paymentRecord.Order__r == null || paymentRecord.Order__r.Account == null
          ? null
          : NetSuiteTransactionUtil.internalIdFromExternalId(paymentRecord.Order__r.Account.External_Id__c);
        NetSuiteTransactionUtil.putReference(payload, 'customer', customerId);
        NetSuiteTransactionUtil.putReference(payload, 'account', config.paymentAccountReference);
        NetSuiteTransactionUtil.writeRecord('customerPayment', paymentRecord.Gateway_Event_Id__c, payload);
        summary.recordsProcessed++;
      } catch (Exception e) {
        summary.recordsFailed++;
        NetSuiteErrorMapper.logException('NetSuitePaymentService.exportPayments', e);
      }
    }
    summary.message = 'NetSuite payment export processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  private static String buildQuery(Datetime sinceDatetime, Integer batchSize) {
    Integer limitSize = batchSize == null || batchSize <= 0 ? 100 : Math.min(batchSize, 1000);
    String query = 'SELECT id, tranid, payment, lastmodifieddate FROM transaction WHERE type = \'CustPymt\'';
    if (sinceDatetime != null) {
      query += ' AND lastmodifieddate >= \'' + sinceDatetime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '\'';
    }
    return query + ' ORDER BY lastmodifieddate ASC FETCH FIRST ' + limitSize + ' ROWS ONLY';
  }

  private static Decimal decimalValue(Object value) {
    return value == null ? null : Decimal.valueOf(String.valueOf(value));
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }
}
