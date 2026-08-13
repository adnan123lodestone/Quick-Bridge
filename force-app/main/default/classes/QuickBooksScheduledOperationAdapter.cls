public with sharing class QuickBooksScheduledOperationAdapter implements ScheduledOperationAdapter, DeferredScheduledOperationAdapter {
  @TestVisible
  private static Boolean skipExecutionForTests = false;

  public void execute(Scheduled_Integration_Job__c job) {
    if (Test.isRunningTest() && skipExecutionForTests == true) {
      return;
    }
    run(job.Source_Object__c, job.Direction__c);
  }

  /**
   * Transfers terminal schedule ownership only for validated shared QBO
   * operations. Every other operation continues through execute/run.
   */
  public ConnectorScheduleDispatchResult dispatch(
    Scheduled_Integration_Job__c job,
    String leaseToken
  ) {
    if (Test.isRunningTest() && skipExecutionForTests == true) {
      return ConnectorScheduleDispatchResult.synchronous();
    }
    if (job == null) {
      return ConnectorScheduleDispatchResult.failed(
        'A QuickBooks scheduled integration job is required.'
      );
    }

    String targetObject = job.Source_Object__c;
    if (!isSharedTarget(targetObject, job.Direction__c)) {
      execute(job);
      return ConnectorScheduleDispatchResult.synchronous();
    }

    try {
      String safeDirection = String.isBlank(job.Direction__c)
        ? 'Out'
        : job.Direction__c;
      Set<Id> recordIds = safeDirection == 'In'
        ? new Set<Id>()
        : outboundRecordIds(targetObject);
      if (safeDirection != 'In' && recordIds.isEmpty()) {
        return ConnectorScheduleDispatchResult.synchronous();
      }

      ConnectorExecutionRequest request = buildSharedRequest(
          job,
          leaseToken,
          recordIds
        )
        .normalizedCopy();
      Id asyncJobId = request.direction ==
        ConnectorExecutionRequest.DIRECTION_INBOUND
        ? Database.executeBatch(new ConnectorInboundBatch(request), 1)
        : Database.executeBatch(
            new ConnectorOutboundBatch(request),
            request.scopeSize
          );
      return ConnectorScheduleDispatchResult.deferred(asyncJobId);
    } catch (Exception exceptionValue) {
      ErrorLogUtility.logException(
        'QuickBooks',
        'QuickBooksScheduledOperationAdapter.run',
        exceptionValue,
        null,
        null
      );
      return ConnectorScheduleDispatchResult.failed(
        ConnectorExecutionResult.sanitizeError(exceptionValue.getMessage())
      );
    }
  }

  @TestVisible
  private static ConnectorExecutionRequest buildSharedRequest(
    Scheduled_Integration_Job__c job,
    String leaseToken,
    Set<Id> recordIds
  ) {
    if (
      job == null ||
      !isSharedTarget(job.Source_Object__c, job.Direction__c)
    ) {
      throw new QuickBooksScheduledOperationException(
        'A supported QuickBooks Account, Vendor, Product, outbound Order, outbound Purchase Order, or outbound Quote schedule is required.'
      );
    }
    String safeDirection = String.isBlank(job.Direction__c)
      ? 'Out'
      : job.Direction__c;
    Boolean inbound = safeDirection == 'In';
    Boolean customerOperation =
      job.Source_Object__c == 'Account' ||
      job.Source_Object__c == 'Accounts';
    Boolean vendorOperation =
      job.Source_Object__c == 'Vendor' ||
      job.Source_Object__c == 'Vendors';
    Boolean accountOperation = customerOperation || vendorOperation;
    Boolean orderOperation =
      job.Source_Object__c == 'Order' ||
      job.Source_Object__c == 'Orders';
    Boolean purchaseOrderOperation =
      job.Source_Object__c == 'PurchaseOrders' ||
      job.Source_Object__c == 'Purchase Order';
    Boolean quoteOperation =
      job.Source_Object__c == 'Quote' ||
      job.Source_Object__c == 'Quotes';

    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = 'qbo';
    request.operationKey = quoteOperation
      ? 'Quote'
      : purchaseOrderOperation
      ? 'PurchaseOrder'
      : orderOperation
      ? 'Order'
      : vendorOperation
      ? 'Vendor'
      : (customerOperation ? 'Customer' : 'Item');
    request.direction = inbound
      ? ConnectorExecutionRequest.DIRECTION_INBOUND
      : ConnectorExecutionRequest.DIRECTION_OUTBOUND;
    request.salesforceObject = quoteOperation
      ? 'Quote'
      : purchaseOrderOperation
      ? 'Purchase_Order__c'
      : orderOperation
      ? 'Order'
      : (accountOperation ? 'Account' : 'Product2');
    request.externalEntity = quoteOperation
      ? 'Estimate'
      : purchaseOrderOperation
      ? 'PurchaseOrder'
      : orderOperation
      ? 'Invoice'
      : vendorOperation
      ? 'Vendor'
      : (customerOperation ? 'Customer' : 'Item');
    request.recordIds = recordIds == null
      ? new List<Id>()
      : new List<Id>(recordIds);
    request.sinceValue = inbound ? Datetime.now().addDays(-1) : null;
    request.initialSync = !inbound;
    request.scopeSize = inbound
      ? 50
      : (accountOperation || orderOperation || purchaseOrderOperation || quoteOperation ? 1 : 50);
    request.scheduleId = job.Id;
    request.leaseToken = leaseToken;
    request.correlationKey = job.Id == null ? null : String.valueOf(job.Id);
    request.pageNumber = 1;
    return request;
  }

  private static Boolean isSharedTarget(
    String targetObject,
    String direction
  ) {
    String safeDirection = String.isBlank(direction) ? 'Out' : direction;
    Boolean sharedBothDirections = targetObject == 'Account' ||
      targetObject == 'Accounts' ||
      targetObject == 'Vendor' ||
      targetObject == 'Vendors' ||
      targetObject == 'Product' ||
      targetObject == 'Products';
    Boolean sharedOutboundOrder =
      safeDirection != 'In' &&
      (targetObject == 'Order' || targetObject == 'Orders');
    Boolean sharedOutboundPurchaseOrder =
      safeDirection != 'In' &&
      (targetObject == 'PurchaseOrders' || targetObject == 'Purchase Order');
    Boolean sharedOutboundQuote =
      safeDirection != 'In' &&
      (targetObject == 'Quote' || targetObject == 'Quotes');
    return sharedBothDirections ||
      sharedOutboundOrder ||
      sharedOutboundPurchaseOrder ||
      sharedOutboundQuote;
  }

  private static Set<Id> outboundRecordIds(String targetObject) {
    Set<Id> recordIds = new Set<Id>();
    if (targetObject == 'Account' || targetObject == 'Accounts') {
      for (Account accountRecord : [
        SELECT Id
        FROM Account
        WHERE QuickbookID__c = NULL AND IsPersonAccount = FALSE
      ]) {
        recordIds.add(accountRecord.Id);
      }
    } else if (targetObject == 'Vendor' || targetObject == 'Vendors') {
      List<RecordType> vendorRecordTypes = [
        SELECT Id
        FROM RecordType
        WHERE
          SobjectType = 'Account' AND
          IsActive = TRUE AND
          (Name = 'Vendor' OR DeveloperName = 'Vendor')
        LIMIT 1
      ];
      if (!vendorRecordTypes.isEmpty()) {
        for (Account accountRecord : [
          SELECT Id
          FROM Account
          WHERE
            QuickbookID__c = NULL AND
            RecordTypeId = :vendorRecordTypes[0].Id
        ]) {
          recordIds.add(accountRecord.Id);
        }
      }
    } else if (targetObject == 'Order' || targetObject == 'Orders') {
      for (Order orderRecord : [
        SELECT Id
        FROM Order
        WHERE QuickbookID__c = NULL AND Status IN ('Draft', 'Activated')
      ]) {
        recordIds.add(orderRecord.Id);
      }
    } else if (
      targetObject == 'PurchaseOrders' ||
      targetObject == 'Purchase Order'
    ) {
      for (Purchase_Order__c purchaseOrderRecord : [
        SELECT Id
        FROM Purchase_Order__c
        WHERE External_Id__c = NULL
      ]) {
        recordIds.add(purchaseOrderRecord.Id);
      }
    } else if (targetObject == 'Quote' || targetObject == 'Quotes') {
      for (Quote quoteRecord : [
        SELECT Id
        FROM Quote
        WHERE QuickbookID__c = NULL
      ]) {
        recordIds.add(quoteRecord.Id);
      }
    } else {
      for (Product2 productRecord : [
        SELECT Id
        FROM Product2
        WHERE QuickbookID__c = NULL AND IsActive = TRUE
      ]) {
        recordIds.add(productRecord.Id);
      }
    }
    return recordIds;
  }

  public static List<Account> loadAccountsForSharedExecution(
    Set<Id> accountIds
  ) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new List<Account>();
    }
    return QBAccountSelector.selectForOutbound(accountIds);
  }

  public static void run(String targetObject, String direction) {
    try {
      String safeDirection = String.isBlank(direction) ? 'Out' : direction;

      if (targetObject == 'Account' || targetObject == 'Accounts') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBCustomerToAccountSyncBatch(), 50);
        } else {
          String accountFields = buildAccountQueryFields();
          List<Account> unsynced = Database.query(
            'SELECT ' +
              accountFields +
              ' FROM Account WHERE QuickBridgeTLG__QuickbookID__c = NULL AND IsPersonAccount = FALSE'
          );
          if (!unsynced.isEmpty()) {
            Database.executeBatch(new QBAccountBatch(unsynced, true), 1);
          }
        }
      } else if (targetObject == 'Vendor' || targetObject == 'Vendors') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBVendorToAccountSyncBatch(), 50);
        } else {
          List<RecordType> vendorRTs = [
            SELECT Id
            FROM RecordType
            WHERE
              SobjectType = 'Account'
              AND IsActive = TRUE
              AND (Name = 'Vendor'
              OR DeveloperName = 'Vendor')
            LIMIT 1
          ];
          if (!vendorRTs.isEmpty()) {
            String accountFields = buildAccountQueryFields();
            List<Account> unsynced = Database.query(
              'SELECT ' +
                accountFields +
                ' FROM Account WHERE QuickBridgeTLG__QuickbookID__c = NULL AND RecordTypeId = \'' +
                vendorRTs[0].Id +
                '\''
            );
            if (!unsynced.isEmpty()) {
              Database.executeBatch(new QBAccountBatch(unsynced, true), 1);
            }
          }
        }
      } else if (targetObject == 'Product' || targetObject == 'Products') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBItemToProductSyncBatch(), 50);
        } else {
          List<Product2> unsynced = [
            SELECT Id
            FROM Product2
            WHERE QuickbookID__c = NULL AND IsActive = TRUE
          ];
          if (!unsynced.isEmpty()) {
            Database.executeBatch(new QBProductBatch(unsynced, true), 50);
          }
        }
      } else if (targetObject == 'Order' || targetObject == 'Orders') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBInvoiceToOrderSyncBatch(), 10);
        } else {
          List<Order> unsyncedOrders = [
            SELECT Id
            FROM Order
            WHERE QuickbookID__c = NULL AND Status IN ('Draft', 'Activated')
          ];
          if (!unsyncedOrders.isEmpty()) {
            Database.executeBatch(
              new QBSalesOrderSyncBatch(
                new Map<Id, Order>(unsyncedOrders).keySet(),
                true
              ),
              1
            );
          }
        }
      } else if (targetObject == 'Invoices' || targetObject == 'Invoice') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBInvoiceToOrderSyncBatch(), 10);
        } else {
          String mappedObj = QBObjectMappings.getInvoiceSourceObject();
          String query =
            'SELECT Id FROM ' +
            mappedObj +
            ' WHERE External_Id__c = null';
          List<SObject> unsyncedRecords = Database.query(query);

          if (!unsyncedRecords.isEmpty()) {
            Database.executeBatch(
              new QuickBooksInvoiceBatch(
                new Map<Id, SObject>(unsyncedRecords).keySet(),
                true
              ),
              10
            );
          }
        }
      } else if (
        targetObject == 'CreditMemos' ||
        targetObject == 'Credit Memo'
      ) {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBCreditMemoInboundBatch(), 10);
        } else {
          String cmObjName = Schema.getGlobalDescribe().containsKey('QuickBridgeTLG__Credit_Memo__c') ? 'QuickBridgeTLG__Credit_Memo__c' : 'Credit_Memo__c';
          List<SObject> unsyncedMemos = Database.query('SELECT Id FROM ' + cmObjName + ' WHERE External_Id__c = null');
          if (!unsyncedMemos.isEmpty()) {
            Database.executeBatch(
              new QuickBooksCreditMemoBatch(new Map<Id, SObject>(unsyncedMemos).keySet(), true),
              10
            );
          }
        }
      } else if (
        targetObject == 'PurchaseOrders' ||
        targetObject == 'Purchase Order'
      ) {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBPurchaseOrderInboundBatch(), 10);
        } else {
          String poObjName = Schema.getGlobalDescribe().containsKey('QuickBridgeTLG__Purchase_Order__c') ? 'QuickBridgeTLG__Purchase_Order__c' : 'Purchase_Order__c';
          List<SObject> unsyncedPurchaseOrders = Database.query('SELECT Id FROM ' + poObjName + ' WHERE External_Id__c = null');
          if (!unsyncedPurchaseOrders.isEmpty()) {
            Database.executeBatch(
              new QuickBooksPurchaseOrderBatch(
                new Map<Id, SObject>(unsyncedPurchaseOrders).keySet(),
                true
              ),
              10
            );
          }
        }
      } else if (
        targetObject == 'ItemSalesTax' ||
        targetObject == 'Item Sales Tax'
      ) {
        Database.executeBatch(new QBOItemSalesTaxBatch(), 1);
      } else if (targetObject == 'Quote' || targetObject == 'Quotes') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBEstimateToQuoteSyncBatch(), 1);
        } else {
          List<Quote> unsyncedQuotes = [
            SELECT Id
            FROM Quote
            WHERE QuickbookID__c = NULL
          ];
          if (!unsyncedQuotes.isEmpty()) {
            Database.executeBatch(
              new QBQuoteToEstimateSyncBatch(
                new Map<Id, Quote>(unsyncedQuotes).keySet(),
                true
              ),
              1
            );
          }
        }
      } else if (
        targetObject == 'OrderSummary' ||
        targetObject == 'OrderSummaries'
      ) {
        if (Schema.getGlobalDescribe().containsKey('OrderSummary')) {
          if (safeDirection == 'In') {
            String query = 'SELECT Id FROM OrderSummary WHERE QuickbookID__c != NULL';
            List<SObject> syncedSummaries = Database.query(query);
            for (SObject s : syncedSummaries) {
              try {
                QBOrderSummaryRecordActionController.syncFromQuickBooks(s.Id);
              } catch (Exception ex) {
                ErrorLogUtility.logException(
                  'QuickBooks',
                  'QuickBooksScheduledOperationAdapter.run.OrderSummary.Inbound',
                  ex,
                  'OrderSummary',
                  s.Id
                );
              }
            }
          } else {
            String query = 'SELECT Id FROM OrderSummary WHERE QuickbookID__c = NULL';
            List<SObject> unsyncedSummaries = Database.query(query);
            for (SObject s : unsyncedSummaries) {
              try {
                QBOrderSummaryRecordActionController.syncToQuickBooks(s.Id);
              } catch (Exception ex) {
                ErrorLogUtility.logException(
                  'QuickBooks',
                  'QuickBooksScheduledOperationAdapter.run.OrderSummary.Outbound',
                  ex,
                  'OrderSummary',
                  s.Id
                );
              }
            }
          }
        }
      }
    } catch (Exception e) {
      ErrorLogUtility.logException(
        'QuickBooks',
        'QuickBooksScheduledOperationAdapter.run',
        e,
        null,
        null
      );
      throw e;
    }
  }

  // Builds the Account SELECT field list for outbound sync queries.
  // Derives SF fields from the active field mapping so the query always matches
  // what QBAccountService reads. Extra identity/relationship fields are added
  // unconditionally; person-account fields are included only when they exist.
  private static String buildAccountQueryFields() {
    Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Account.fields.getMap();
    Set<String> fieldApiNames = new Set<String>{
      'Id', 'Name', 'RecordTypeId', 'QuickbookID__c'
    };

    // Add all SF-side fields from the active mapping (Customer and Vendor)
    for (
      String sfField : QBObjectMappings.getAccountToCustomerMapping().keySet()
    ) {
      fieldApiNames.add(sfField);
    }
    for (
      String sfField : QBObjectMappings.getAccountToVendorMapping().keySet()
    ) {
      fieldApiNames.add(sfField);
    }

    // Person-account fields — only include when enabled in this org
    List<String> personAccountFields = new List<String>{
      'IsPersonAccount',
      'FirstName',
      'LastName',
      'PersonEmail',
      'GivenName__c',
      'FamilyName__c'
    };
    for (String f : personAccountFields) {
      if (
        schemaFields.containsKey(f.toLowerCase()) ||
        schemaFields.containsKey('QuickBridgeTLG__' + f.toLowerCase())
      ) {
        fieldApiNames.add(f);
      }
    }

    // Resolve each name to its actual schema API name (handles namespace prefix correctly)
    Set<String> resolvedFields = new Set<String>();
    for (String fieldName : fieldApiNames) {
      String keyLower = fieldName.toLowerCase();
      Schema.SObjectField token = schemaFields.get(keyLower);
      if (token == null) {
        token = schemaFields.get('QuickBridgeTLG__' + keyLower);
      }
      if (token != null) {
        resolvedFields.add(token.getDescribe().getName());
      }
    }

    return String.join(new List<String>(resolvedFields), ', ');
  }

  public class QuickBooksScheduledOperationException extends Exception {
  }
}