public class QBOErrorHandler {
  public static String handle(Error_Log__c log) {
    Id recordId = log.Source_Record_Id__c;
    String method = log.Class_Method_Name__c;

    if (recordId == null) {
      throw new AuraHandledException(
        'Cannot retry: Source Record ID is missing. This error log may not be linked to a specific Salesforce record.'
      );
    }

    // Outbound syncs (Salesforce → QBO)
    if (
      method.contains('QBAccountService.syncAccountToQuickBooks') ||
      method.contains('QBAccountBatch.execute')
    ) {
      Account acc = [
        SELECT Id, QuickbookID__c
        FROM Account
        WHERE Id = :recordId
      ];
      QBAccountService.SyncResult res = QBAccountService.syncAccountToQuickBooks(
        acc,
        acc.QuickbookID__c == null
      );
      return 'Account retried: ' + res.quickBooksId;
    } else if (
      method.contains('QBProductService.syncProductsToQuickBooks') ||
      method.contains('QBProductBatch.execute')
    ) {
      Product2 prod = [
        SELECT Id, QuickbookID__c
        FROM Product2
        WHERE Id = :recordId
      ];
      QBProductService.syncProductsToQuickBooks(
        new List<Product2>{ prod },
        prod.QuickbookID__c == null
      );
      return 'Product retried.';
    } else if (method.contains('QBSalesOrderSyncBatch.execute')) {
      QBSalesOrderSyncBatch batch = new QBSalesOrderSyncBatch(
        new Set<Id>{ recordId },
        false
      );
      Database.executeBatch(batch, 1);
      return 'Order sync batch enqueued.';
    } else if (
      method.contains('QuickBooksInvoiceBatch.execute') ||
      method.contains('QBInvoiceWorker.process')
    ) {
      QuickBooksInvoiceBatch batch = new QuickBooksInvoiceBatch(
        new Set<Id>{ recordId },
        false
      );
      Database.executeBatch(batch, 1);
      return 'Invoice sync batch enqueued.';
    } else if (method.contains('QuickBooksCreditMemoBatch.execute')) {
      QuickBooksCreditMemoBatch batch = new QuickBooksCreditMemoBatch(
        new Set<Id>{ recordId },
        false
      );
      Database.executeBatch(batch, 1);
      return 'Credit memo batch enqueued.';
    } else if (method.contains('QuickBooksPurchaseOrderBatch.execute')) {
      QuickBooksPurchaseOrderBatch batch = new QuickBooksPurchaseOrderBatch(
        new Set<Id>{ recordId },
        false
      );
      Database.executeBatch(batch, 1);
      return 'Purchase order batch enqueued.';
    }
    // Inbound syncs (QBO → Salesforce)
    else if (method.contains('QBItemToProductSyncBatch.execute')) {
      String externalId = log.Source_Record_Id__c; // QBO Item ID
      new QBItemToProductSyncBatch().syncItemFromQBO(externalId);
      return 'Item synced from QBO.';
    } else if (method.contains('QBCustomerToAccountSyncBatch.execute')) {
      String externalId = log.Source_Record_Id__c; // QBO Customer ID
      new QBCustomerToAccountSyncBatch()
        .processSingleCustomer(log.Source_Record_Id__c);
      return 'Customer synced from QBO.';
    } else if (method.contains('QBVendorToAccountSyncBatch.execute')) {
      String externalId = log.Source_Record_Id__c; // QBO Vendor ID
      new QBVendorToAccountSyncBatch().syncVendorFromQBO(externalId);
      return 'Vendor synced from QBO.';
    } else if (method.contains('QBInvoiceToOrderSyncBatch.execute')) {
      String externalId = log.Source_Record_Id__c; // QBO Invoice ID
      QBInvoiceToOrderSyncBatch.processSingleInvoice(externalId);
      return 'Invoice converted to Order.';
    } else if (method.contains('QBOInvoiceSyncQueueable.execute')) {
      String externalId = log.Source_Record_Id__c; // QBO Invoice ID
      System.enqueueJob(
        new QBOInvoiceSyncQueueable(new Set<String>{ externalId })
      );
      return 'Invoice sync queueable enqueued.';
    } else {
      throw new AuraHandledException('Unsupported QBO operation: ' + method);
    }
  }
}
