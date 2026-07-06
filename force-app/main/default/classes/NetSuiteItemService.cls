public with sharing class NetSuiteItemService {
  public class SyncSummary {
    @AuraEnabled public Integer recordsProcessed { get; set; }
    @AuraEnabled public Integer recordsFailed { get; set; }
    @AuraEnabled public String message { get; set; }

    public SyncSummary() {
      recordsProcessed = 0;
      recordsFailed = 0;
    }
  }

  public static SyncSummary syncItems(Datetime sinceDatetime, Integer batchSize) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableItemSync != true) {
      summary.message = 'NetSuite item sync is disabled.';
      return summary;
    }

    List<Map<String, Object>> rows = NetSuiteApiClient.configured().suiteql(buildItemQuery(sinceDatetime, batchSize), null);
    List<Product2> products = new List<Product2>();
    for (Map<String, Object> row : rows) {
      String externalId = externalId(row.get('id'));
      if (String.isBlank(externalId)) {
        summary.recordsFailed++;
        continue;
      }
      Product2 productRecord = new Product2();
      productRecord.External_Id__c = externalId;
      productRecord.ProductCode = stringValue(row.get('itemid'));
      productRecord.Name = firstNonBlank(stringValue(row.get('displayname')), productRecord.ProductCode);
      productRecord.Description = stringValue(row.get('salesdescription'));
      productRecord.IsActive = !isNetSuiteFalse(row.get('isinactive'));
      if (String.isBlank(productRecord.Name)) {
        productRecord.Name = 'NetSuite Item ' + stringValue(row.get('id'));
      }
      products.add(productRecord);
    }

    if (!products.isEmpty()) {
      Database.UpsertResult[] results = Database.upsert(products, Product2.External_Id__c, false);
      ErrorLogUtility.logUpsertResults('NetSuite', 'NetSuiteItemService.syncItems', 'upsert', products, results, null, null);
      for (Database.UpsertResult result : results) {
        if (result.isSuccess()) {
          summary.recordsProcessed++;
        } else {
          summary.recordsFailed++;
        }
      }
    }
    summary.message = 'NetSuite item sync processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  public static SyncSummary exportItems(Set<Id> productIds) {
    NetSuiteConfigService.Config config = NetSuiteConfigService.requireConfigured();
    SyncSummary summary = new SyncSummary();
    if (config.enableItemSync != true || productIds == null || productIds.isEmpty()) {
      summary.message = 'NetSuite item export skipped.';
      return summary;
    }
    List<Product2> products = [
      SELECT Id, Name, ProductCode, Description, IsActive, External_Id__c
      FROM Product2
      WHERE Id IN :productIds
    ];
    List<Product2> updates = new List<Product2>();
    String recordType = String.isBlank(config.defaultItemRecordType) ? 'inventoryItem' : config.defaultItemRecordType;
    for (Product2 productRecord : products) {
      try {
        Map<String, Object> payload = NetSuiteRecordMapper.toNetSuitePayload(productRecord, 'Product2', 'Item');
        if (payload.containsKey('isinactive')) {
          payload.put('isinactive', productRecord.IsActive == false);
        }
        String internalId = NetSuiteTransactionUtil.writeRecord(recordType, productRecord.External_Id__c, payload);
        if (String.isNotBlank(internalId) && String.isBlank(productRecord.External_Id__c)) {
          updates.add(new Product2(Id = productRecord.Id, External_Id__c = 'netsuite:' + internalId));
        }
        summary.recordsProcessed++;
      } catch (Exception e) {
        summary.recordsFailed++;
        NetSuiteErrorMapper.logException('NetSuiteItemService.exportItems', e);
      }
    }
    if (!updates.isEmpty()) {
      Database.update(updates, false);
    }
    summary.message = 'NetSuite item export processed ' + summary.recordsProcessed + ' records.';
    return summary;
  }

  private static String buildItemQuery(Datetime sinceDatetime, Integer batchSize) {
    Integer limitSize = batchSize == null || batchSize <= 0 ? 100 : Math.min(batchSize, 1000);
    String query = 'SELECT id, itemid, displayname, salesdescription, isinactive, lastmodifieddate FROM item';
    if (sinceDatetime != null) {
      query += ' WHERE lastmodifieddate >= \'' + sinceDatetime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '\'';
    }
    return query + ' ORDER BY lastmodifieddate ASC FETCH FIRST ' + limitSize + ' ROWS ONLY';
  }

  private static Boolean isNetSuiteFalse(Object value) {
    if (value == null) {
      return false;
    }
    String text = String.valueOf(value);
    return text == 'T' || text.equalsIgnoreCase('true');
  }

  private static String externalId(Object idValue) {
    String idText = stringValue(idValue);
    return String.isBlank(idText) ? null : 'netsuite:' + idText;
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static String firstNonBlank(String firstValue, String secondValue) {
    return String.isBlank(firstValue) ? secondValue : firstValue;
  }
}
