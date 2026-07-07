public with sharing class NetSuiteFulfillmentService {
  public class SyncSummary {
    @AuraEnabled public Integer recordsProcessed { get; set; }
    @AuraEnabled public Integer recordsFailed { get; set; }
    @AuraEnabled public String message { get; set; }
    public SyncSummary() {
      recordsProcessed = 0;
      recordsFailed = 0;
    }
  }

  public static SyncSummary syncFulfillments(Datetime sinceDatetime, Integer batchSize) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableFulfillmentSync != true) {
      summary.message = 'NetSuite fulfillment sync is disabled.';
      return summary;
    }
    Datetime effectiveSince = NetSuiteSyncStateService.effectiveSince(sinceDatetime, config);
    List<Map<String, Object>> rows = NetSuiteApiClient.configured().suiteql(buildQuery(effectiveSince, batchSize), null);
    List<Carrier_Shipment__c> shipments = new List<Carrier_Shipment__c>();
    Map<String, Map<String, Object>> sourceByExternalId = new Map<String, Map<String, Object>>();
    for (Map<String, Object> row : rows) {
      Carrier_Shipment__c shipment = new Carrier_Shipment__c();
      shipment.External_Shipment_Id__c = 'netsuite:' + stringValue(row.get('id'));
      shipment.Master_Tracking_Number__c = stringValue(row.get('trackingnumbers'));
      shipment.Shipment_Status__c = stringValue(row.get('status'));
      shipment.Integration_Type__c = 'netsuite';
      shipments.add(shipment);
      sourceByExternalId.put(shipment.External_Shipment_Id__c, row);
    }
    if (!shipments.isEmpty()) {
      List<SObject> candidates = new List<SObject>();
      candidates.addAll(shipments);
      NetSuiteSyncStateService.FilterResult filtered = NetSuiteSyncStateService.filterInboundConflicts(
        'Carrier_Shipment__c',
        'External_Shipment_Id__c',
        candidates,
        sourceByExternalId,
        config.lastSuccessfulSyncAt,
        'NetSuiteFulfillmentService.syncFulfillments'
      );
      summary.recordsFailed += filtered.conflictCount;
      shipments.clear();
      for (SObject filteredRecord : filtered.records) {
        shipments.add((Carrier_Shipment__c) filteredRecord);
      }
      List<Carrier_Shipment__c> inserts = new List<Carrier_Shipment__c>();
      List<Carrier_Shipment__c> updates = new List<Carrier_Shipment__c>();
      Map<String, Carrier_Shipment__c> existingByExternalId = existingShipments(shipments);
      for (Carrier_Shipment__c shipment : shipments) {
        Carrier_Shipment__c existing = existingByExternalId.get(shipment.External_Shipment_Id__c);
        if (existing == null) {
          inserts.add(shipment);
        } else {
          shipment.Id = existing.Id;
          updates.add(shipment);
        }
      }
      List<Database.SaveResult> results = new List<Database.SaveResult>();
      if (!inserts.isEmpty()) {
        results.addAll(Database.insert(inserts, false));
      }
      if (!updates.isEmpty()) {
        results.addAll(Database.update(updates, false));
      }
      for (Database.SaveResult result : results) {
        if (result.isSuccess()) summary.recordsProcessed++;
        else summary.recordsFailed++;
      }
    }
    NetSuiteSyncStateService.advanceWatermarkIfClean(rows, summary.recordsFailed);
    summary.message = 'NetSuite fulfillment sync processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  private static Map<String, Carrier_Shipment__c> existingShipments(List<Carrier_Shipment__c> shipments) {
    Set<String> externalIds = new Set<String>();
    for (Carrier_Shipment__c shipment : shipments) {
      if (String.isNotBlank(shipment.External_Shipment_Id__c)) {
        externalIds.add(shipment.External_Shipment_Id__c);
      }
    }
    Map<String, Carrier_Shipment__c> existingByExternalId = new Map<String, Carrier_Shipment__c>();
    if (externalIds.isEmpty()) {
      return existingByExternalId;
    }
    for (Carrier_Shipment__c shipment : [
      SELECT Id, External_Shipment_Id__c
      FROM Carrier_Shipment__c
      WHERE External_Shipment_Id__c IN :externalIds
    ]) {
      existingByExternalId.put(shipment.External_Shipment_Id__c, shipment);
    }
    return existingByExternalId;
  }

  public static SyncSummary exportFulfillments(Set<Id> shipmentIds) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableFulfillmentSync != true || shipmentIds == null || shipmentIds.isEmpty()) {
      summary.message = 'NetSuite fulfillment export skipped.';
      return summary;
    }
    List<Carrier_Shipment__c> shipments = [
      SELECT Id, External_Shipment_Id__c, Master_Tracking_Number__c, Shipment_Status__c, Source_Object__c, Source_Record_Id__c
      FROM Carrier_Shipment__c
      WHERE Id IN :shipmentIds
    ];
    Map<Id, Order> ordersById = loadOrders(shipments);
    for (Carrier_Shipment__c shipment : shipments) {
      try {
        Order sourceOrder = sourceOrder(shipment, ordersById);
        String salesOrderId = sourceOrder == null ? null : NetSuiteTransactionUtil.internalIdFromExternalId(sourceOrder.External_Id__c);
        if (String.isBlank(salesOrderId)) {
          throw new NetSuiteFulfillmentException('Outbound NetSuite fulfillment requires a related NetSuite sales order external ID.');
        }
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('trackingnumbers', shipment.Master_Tracking_Number__c);
        NetSuiteTransactionUtil.putReference(payload, 'createdFrom', salesOrderId);
        NetSuiteTransactionUtil.putReference(payload, 'location', config.defaultFulfillmentLocation);
        NetSuiteTransactionUtil.writeRecord('itemFulfillment', shipment.External_Shipment_Id__c, payload);
        summary.recordsProcessed++;
      } catch (NetSuiteFulfillmentException e) {
        throw e;
      } catch (Exception e) {
        summary.recordsFailed++;
        NetSuiteErrorMapper.logException('NetSuiteFulfillmentService.exportFulfillments', e);
      }
    }
    summary.message = 'NetSuite fulfillment export processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  private static Map<Id, Order> loadOrders(List<Carrier_Shipment__c> shipments) {
    Set<Id> orderIds = new Set<Id>();
    for (Carrier_Shipment__c shipment : shipments) {
      if (shipment.Source_Object__c == 'Order' && String.isNotBlank(shipment.Source_Record_Id__c)) {
        try {
          orderIds.add((Id) shipment.Source_Record_Id__c);
        } catch (Exception ignored) {
        }
      }
    }
    return orderIds.isEmpty()
      ? new Map<Id, Order>()
      : new Map<Id, Order>([SELECT Id, External_Id__c FROM Order WHERE Id IN :orderIds]);
  }

  private static Order sourceOrder(Carrier_Shipment__c shipment, Map<Id, Order> ordersById) {
    if (shipment.Source_Object__c != 'Order' || String.isBlank(shipment.Source_Record_Id__c)) {
      return null;
    }
    try {
      return ordersById.get((Id) shipment.Source_Record_Id__c);
    } catch (Exception ignored) {
      return null;
    }
  }

  private static String buildQuery(Datetime sinceDatetime, Integer batchSize) {
    Integer limitSize = batchSize == null || batchSize <= 0 ? 100 : Math.min(batchSize, 1000);
    String query = 'SELECT id, tranid, trackingnumbers, status, lastmodifieddate FROM transaction WHERE type = \'ItemShip\'';
    if (sinceDatetime != null) {
      query += ' AND lastmodifieddate >= \'' + sinceDatetime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '\'';
    }
    return query + ' ORDER BY lastmodifieddate ASC FETCH FIRST ' + limitSize + ' ROWS ONLY';
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  public class NetSuiteFulfillmentException extends Exception {}
}