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
    IntegrationUsageService.assertCanConsumeTask(
      'QuickBooks',
      scope == null ? 1 : scope.size()
    );
    List<Purchase_Order__c> recordsToUpsert = new List<Purchase_Order__c>();

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
    }
  }

  public void finish(Database.BatchableContext bc) {
    System.debug('QBPurchaseOrderInboundBatch completed');
  }
}