public with sharing class NetSuiteSalesOrderService {
  public class SyncSummary {
    @AuraEnabled public Integer recordsProcessed { get; set; }
    @AuraEnabled public Integer recordsFailed { get; set; }
    @AuraEnabled public String message { get; set; }
    public SyncSummary() {
      recordsProcessed = 0;
      recordsFailed = 0;
    }
  }

  public static SyncSummary syncSalesOrders(Datetime sinceDatetime, Integer batchSize) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableSalesOrderSync != true) {
      summary.message = 'NetSuite sales order sync is disabled.';
      return summary;
    }
    Datetime effectiveSince = NetSuiteSyncStateService.effectiveSince(sinceDatetime, config);
    List<Map<String, Object>> rows = NetSuiteApiClient.configured().suiteql(buildQuery('transaction', 'SalesOrd', effectiveSince, batchSize), null);
    List<Order> orders = new List<Order>();
    Map<String, Map<String, Object>> sourceByExternalId = new Map<String, Map<String, Object>>();
    for (Map<String, Object> row : rows) {
      Order orderRecord = (Order) NetSuiteRecordMapper.toSalesforceRecord('Order', 'SalesOrder', row);
      if (orderRecord.EffectiveDate == null) {
        orderRecord.EffectiveDate = Date.today();
      }
      if (String.isBlank(orderRecord.Status)) {
        orderRecord.Status = 'Draft';
      }
      orders.add(orderRecord);
      sourceByExternalId.put(orderRecord.External_Id__c, row);
    }
    if (!orders.isEmpty()) {
      List<SObject> candidates = new List<SObject>();
      candidates.addAll(orders);
      NetSuiteSyncStateService.FilterResult filtered = NetSuiteSyncStateService.filterInboundConflicts(
        'Order',
        'External_Id__c',
        candidates,
        sourceByExternalId,
        config.lastSuccessfulSyncAt,
        'NetSuiteSalesOrderService.syncSalesOrders'
      );
      summary.recordsFailed += filtered.conflictCount;
      orders.clear();
      for (SObject filteredRecord : filtered.records) {
        orders.add((Order) filteredRecord);
      }
      Database.UpsertResult[] results = Database.upsert(orders, Order.External_Id__c, false);
      ErrorLogUtility.logUpsertResults('NetSuite', 'NetSuiteSalesOrderService.syncSalesOrders', 'upsert', orders, results, null, null);
      count(results, summary);
    }
    NetSuiteSyncStateService.advanceWatermarkIfClean(rows, summary.recordsFailed);
    summary.message = 'NetSuite sales order sync processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  public static SyncSummary exportOrders(Set<Id> orderIds) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableSalesOrderSync != true || orderIds == null || orderIds.isEmpty()) {
      summary.message = 'NetSuite sales order export skipped.';
      return summary;
    }
    List<Order> orders = [
      SELECT Id, AccountId, Account.External_Id__c, EffectiveDate, Status, OrderReferenceNumber, External_Id__c, TotalAmount
      FROM Order
      WHERE Id IN :orderIds
    ];
    List<Order> updates = new List<Order>();
    for (Order orderRecord : orders) {
      try {
        Map<String, Object> payload = NetSuiteRecordMapper.toNetSuitePayload(orderRecord, 'Order', 'SalesOrder');
        String customerId = orderRecord.Account == null ? null : NetSuiteTransactionUtil.internalIdFromExternalId(orderRecord.Account.External_Id__c);
        NetSuiteTransactionUtil.putReference(payload, 'entity', customerId);
        applyTransactionDefaults(payload, config);
        String internalId = NetSuiteTransactionUtil.writeRecord('salesOrder', orderRecord.External_Id__c, payload);
        if (String.isNotBlank(internalId) && String.isBlank(orderRecord.External_Id__c)) {
          updates.add(new Order(Id = orderRecord.Id, External_Id__c = 'netsuite:' + internalId));
        }
        summary.recordsProcessed++;
      } catch (Exception e) {
        summary.recordsFailed++;
        NetSuiteErrorMapper.logException('NetSuiteSalesOrderService.exportOrders', e);
      }
    }
    if (!updates.isEmpty()) {
      Database.update(updates, false);
    }
    summary.message = 'NetSuite sales order export processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  private static String buildQuery(String tableName, String typeValue, Datetime sinceDatetime, Integer batchSize) {
    Integer limitSize = batchSize == null || batchSize <= 0 ? 100 : Math.min(batchSize, 1000);
    String query = 'SELECT id, tranid, trandate, status, foreigntotal AS total, lastmodifieddate FROM ' + tableName + ' WHERE type = \'' + typeValue + '\'';
    if (sinceDatetime != null) {
      query += ' AND lastmodifieddate >= \'' + sinceDatetime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '\'';
    }
    return query + ' ORDER BY lastmodifieddate ASC FETCH FIRST ' + limitSize + ' ROWS ONLY';
  }

  private static void applyTransactionDefaults(Map<String, Object> payload, NetSuiteConfigService.Config config) {
    NetSuiteTransactionUtil.putReference(payload, 'subsidiary', config.defaultSubsidiary);
    NetSuiteTransactionUtil.putReference(payload, 'department', config.defaultDepartment);
    NetSuiteTransactionUtil.putReference(payload, 'class', config.defaultClass);
    NetSuiteTransactionUtil.putReference(payload, 'location', config.defaultLocation);
  }

  private static void count(Database.UpsertResult[] results, SyncSummary summary) {
    for (Database.UpsertResult result : results) {
      if (result.isSuccess()) summary.recordsProcessed++;
      else summary.recordsFailed++;
    }
  }
}