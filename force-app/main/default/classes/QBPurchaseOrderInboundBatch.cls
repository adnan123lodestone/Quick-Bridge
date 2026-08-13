public class QBPurchaseOrderInboundBatch implements Database.Batchable<String>, Database.AllowsCallouts {
  private String lastSyncDate;

  public QBPurchaseOrderInboundBatch() {
    Datetime yesterday = Datetime.now().addDays(-1);
    this.lastSyncDate = yesterday.format('yyyy-MM-dd');
  }

  public QBPurchaseOrderInboundBatch(String syncDate) {
    this.lastSyncDate = syncDate;
  }

  public Iterable<String> start(Database.BatchableContext bc) {
    List<String> payloads = new List<String>();
    try {
      payloads = QuickBooksBulkQueryService.serializeRecords(
        QuickBooksBulkQueryService.queryUpdatedSince(
          'PurchaseOrder',
          lastSyncDate
        )
      );
    } catch (Exception e) {
      ErrorLogUtility.logException(
        'QuickBooks',
        'QBPurchaseOrderInboundBatch.start',
        e,
        null,
        null
      );
    }
    return payloads;
  }

  public void execute(Database.BatchableContext bc, List<String> scope) {
    List<Purchase_Order__c> recordsToUpsert = new List<Purchase_Order__c>();
    Map<String, List<Map<String, Object>>> poLinesByQbId = new Map<String, List<Map<String, Object>>>();

    for (String payload : scope) {
      try {
        Map<String, Object> qbRecord = (Map<String, Object>) JSON.deserializeUntyped(
          payload
        );
        String qbId = (String) qbRecord.get('Id');
        if (String.isBlank(qbId))
          continue;

        Purchase_Order__c po = new Purchase_Order__c();
        po.External_Id__c = qbId;
        po.Is_Synced__c = true;

        Object docNumber = qbRecord.get('DocNumber');
        if (docNumber != null) {
          po.PO_Number__c = String.valueOf(docNumber);
        }

        Object txnDate = qbRecord.get('TxnDate');
        if (txnDate != null) {
          try {
            po.PO_Date__c = Date.valueOf(String.valueOf(txnDate));
          } catch (Exception e) {
          }
        }

        Object expectedDate = qbRecord.get('ExpectedDate');
        if (expectedDate != null) {
          try {
            po.Delivery_Date__c = Date.valueOf(String.valueOf(expectedDate));
          } catch (Exception e) {
          }
        }

        Object dueDate = qbRecord.get('DueDate');
        if (dueDate != null) {
          try {
            po.Due_Date__c = Date.valueOf(String.valueOf(dueDate));
          } catch (Exception e) {
          }
        }

        // Link to Account (Vendor) via VendorRef
        Object vendorRefObj = qbRecord.get('VendorRef');
        if (vendorRefObj instanceof Map<String, Object>) {
          String vendorId = (String) ((Map<String, Object>) vendorRefObj)
            .get('value');
          if (String.isNotBlank(vendorId)) {
            List<Account> matchingVendors = [
              SELECT Id
              FROM Account
              WHERE QuickbookID__c = :vendorId
              LIMIT 1
            ];
            if (!matchingVendors.isEmpty()) {
              po.Supplier__c = matchingVendors[0].Id;
            }
          }
        }

        // Collect line items for processing after PO header upsert
        Object lineObj = qbRecord.get('Line');
        if (lineObj instanceof List<Object>) {
          List<Map<String, Object>> lines = new List<Map<String, Object>>();
          for (Object l : (List<Object>) lineObj) {
            if (l instanceof Map<String, Object>) {
              Map<String, Object> lineMap = (Map<String, Object>) l;
              if ('ItemBasedExpenseLineDetail' == (String) lineMap.get('DetailType')) {
                lines.add(lineMap);
              }
            }
          }
          if (!lines.isEmpty()) {
            poLinesByQbId.put(qbId, lines);
          }
        }

        recordsToUpsert.add(po);
      } catch (Exception e) {
        ErrorLogUtility.logException(
          'QuickBooks',
          'QBPurchaseOrderInboundBatch.execute.processRow',
          e,
          'Purchase_Order__c',
          null
        );
      }
    }

    if (!recordsToUpsert.isEmpty()) {
      Database.UpsertResult[] results = Database.upsert(
        recordsToUpsert,
        Purchase_Order__c.External_Id__c,
        false
      );
      Integer successCount = 0;
      for (Database.UpsertResult r : results) {
        if (r.isSuccess())
          successCount++;
      }
      if (successCount > 0) {
        IntegrationUsageService.recordSuccessfulRecordSync(
          'QuickBooks',
          successCount
        );
      }
      ErrorLogUtility.logUpsertResults(
        'QuickBooks',
        'QBPurchaseOrderInboundBatch.execute.upsert',
        'upsert',
        recordsToUpsert,
        results,
        null,
        null
      );

      // Build QB Id -> SF record Id map for line item parent linkage
      Map<String, Id> qbIdToPoId = new Map<String, Id>();
      for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
          qbIdToPoId.put(recordsToUpsert[i].External_Id__c, results[i].getId());
        }
      }

      processLineItems(poLinesByQbId, qbIdToPoId);
    }
  }

  private void processLineItems(
    Map<String, List<Map<String, Object>>> poLinesByQbId,
    Map<String, Id> qbIdToPoId
  ) {
    if (poLinesByQbId.isEmpty()) return;

    // Bulk resolve products by QB Id
    Set<String> productQbIds = new Set<String>();
    for (List<Map<String, Object>> lines : poLinesByQbId.values()) {
      for (Map<String, Object> line : lines) {
        Map<String, Object> detail = (Map<String, Object>) line.get('ItemBasedExpenseLineDetail');
        if (detail != null) {
          Map<String, Object> itemRef = (Map<String, Object>) detail.get('ItemRef');
          if (itemRef != null && itemRef.get('value') != null) {
            productQbIds.add((String) itemRef.get('value'));
          }
        }
      }
    }
    Map<String, Id> productQbIdToSfId = new Map<String, Id>();
    if (!productQbIds.isEmpty()) {
      for (Product2 p : [SELECT Id, QuickbookID__c FROM Product2 WHERE QuickbookID__c IN :productQbIds]) {
        productQbIdToSfId.put(p.QuickbookID__c, p.Id);
      }
    }

    // The fallback mapping paths are prefixed with 'Line.' (designed for root PO traversal).
    // Strip that prefix so paths resolve correctly against individual line item maps.
    Map<String, String> rawPoLineMapping = QBObjectMappings.getQBOToPurchaseOrderLineMapping();
    Map<String, String> poLineMapping = new Map<String, String>();
    for (String qbPath : rawPoLineMapping.keySet()) {
      String normalizedPath = qbPath.startsWith('Line.') ? qbPath.substring(5) : qbPath;
      poLineMapping.put(normalizedPath, rawPoLineMapping.get(qbPath));
    }
    List<Purchase_Order_Line__c> linesToUpsert = new List<Purchase_Order_Line__c>();

    for (String poQbId : poLinesByQbId.keySet()) {
      Id poSfId = qbIdToPoId.get(poQbId);
      if (poSfId == null) continue;
      for (Map<String, Object> line : poLinesByQbId.get(poQbId)) {
        String lineId = (String) line.get('Id');
        if (String.isBlank(lineId)) continue;
        try {
          Purchase_Order_Line__c pol = new Purchase_Order_Line__c();
          // Apply dynamic field mapping (handles Quantity__c, Cost_Price__c, Product_Description__c
          // from fallback, plus any custom Field_Mapping__mdt records)
          applyDynamicMapping(pol, line, poLineMapping);
          // Set identity and relationship fields after dynamic mapping to prevent overwrite
          pol.External_Id__c = poQbId + '_' + lineId;
          pol.Purchase_Order__c = poSfId;
          pol.PO_External_Id__c = poQbId;
          pol.Is_Synced__c = true;
          // Product__c and Total_Cost__c are not in the fallback mapping — set explicitly.
          // Total_Cost__c is a formula field (Quantity__c * Cost_Price__c) and cannot be written.
          Map<String, Object> detail = (Map<String, Object>) line.get('ItemBasedExpenseLineDetail');
          if (detail != null) {
            Map<String, Object> itemRef = (Map<String, Object>) detail.get('ItemRef');
            if (itemRef != null) {
              String itemQbId = (String) itemRef.get('value');
              if (String.isNotBlank(itemQbId) && productQbIdToSfId.containsKey(itemQbId)) {
                pol.Product__c = productQbIdToSfId.get(itemQbId);
              }
            }
          }
          linesToUpsert.add(pol);
        } catch (Exception e) {
          ErrorLogUtility.logException(
            'QuickBooks',
            'QBPurchaseOrderInboundBatch.execute.processLine',
            e,
            'Purchase_Order_Line__c',
            null
          );
        }
      }
    }

    if (!linesToUpsert.isEmpty()) {
      Database.UpsertResult[] lineResults = Database.upsert(
        linesToUpsert,
        Purchase_Order_Line__c.External_Id__c,
        false
      );
      ErrorLogUtility.logUpsertResults(
        'QuickBooks',
        'QBPurchaseOrderInboundBatch.execute.upsertLines',
        'upsert',
        linesToUpsert,
        lineResults,
        null,
        null
      );
    }
  }

  private void applyDynamicMapping(SObject record, Map<String, Object> qbData, Map<String, String> mapping) {
    if (record == null || qbData == null || mapping == null) {
      return;
    }
    for (String qbField : mapping.keySet()) {
      Object qbValue = getNestedValue(qbData, qbField);
      if (qbValue != null) {
        try {
          putFieldValue(record, mapping.get(qbField), qbValue);
        } catch (Exception e) {}
      }
    }
  }

  private Object getNestedValue(Map<String, Object> data, String path) {
    String[] pathParts = path.split('\\.');
    Object current = data;
    for (String part : pathParts) {
      if (current instanceof Map<String, Object>) {
        current = ((Map<String, Object>) current).get(part);
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
    // fields.getMap() keys are fully-qualified lowercased API names (e.g. quantity__c).
    // The mapping values may omit the namespace prefix (e.g. Quantity__c) — try both forms.
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

  public void finish(Database.BatchableContext bc) {
    System.debug('QBPurchaseOrderInboundBatch completed');
  }
}