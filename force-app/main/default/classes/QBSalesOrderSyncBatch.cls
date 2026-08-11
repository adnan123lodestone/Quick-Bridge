public class QBSalesOrderSyncBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {
  private Set<Id> orderIds;
  private Boolean isInitialSync;
  private Boolean mapDraftOrdersAsEstimates;
  private ConnectorExecutionResult sharedExecutionResult;
  private Set<Id> sharedSuccessfulOrderIds = new Set<Id>();
  private Set<Id> sharedFailedOrderIds = new Set<Id>();

  // QBO Invoice/Estimate properties that are server-calculated and must never be sent;
  // including them causes ValidationFault 2010 ("unsupported property").
  private static final Set<String> QBO_READONLY_PROPS = new Set<String>{
    'TotalAmt',
    'Balance',
    'HomeTotalAmt',
    'HomeBalance'
  };

  public QBSalesOrderSyncBatch(Set<Id> ids, Boolean isInitial) {
    this.orderIds = ids;
    this.isInitialSync = isInitial;
    this.mapDraftOrdersAsEstimates = getConfigValue();
  }

  private Boolean getConfigValue() {
    try {
      return ConnectorConfigResolver.getBoolean('qbo', 'Map_Draft_Orders_as_Estimates__c');
    } catch (Exception e) {
      System.debug('Could not load Draft Order setting: ' + e.getMessage());
      return false;
    }
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(buildOrderScopeQuery());
  }

  public static List<Order> loadOrdersForSharedExecution(Set<Id> ids) {
    if (ids == null || ids.isEmpty()) {
      return new List<Order>();
    }
    Set<Id> orderIds = ids;
    return (List<Order>) Database.query(buildOrderScopeQuery());
  }

  private static String buildOrderScopeQuery() {
    String orderFields = buildOrderQueryFields();
    String accountFields = getAccountQboIdQueryFields();
    String productFields = getProductQboIdQueryFields();
    String query =
      'SELECT ' + orderFields +
      (String.isNotBlank(accountFields) ? ', ' + accountFields : '') +
      ', (SELECT Id, Product2Id, Quantity, UnitPrice, Description, TotalPrice' +
      getOrderItemQbLineIdQueryFields() +
      (String.isNotBlank(productFields) ? ', ' + productFields : '') +
      buildOrderItemQueryFields() +
      ' FROM OrderItems)' +
      ' FROM Order WHERE Id IN :orderIds';
    return query;
  }

  public ConnectorExecutionResult executeSharedScope(List<Order> scope) {
    sharedExecutionResult = ConnectorExecutionResult.success();
    sharedSuccessfulOrderIds.clear();
    sharedFailedOrderIds.clear();
    execute(null, scope);
    sharedExecutionResult.processedCount = scope == null ? 0 : scope.size();
    sharedExecutionResult.failedCount = sharedFailedOrderIds.size();
    sharedSuccessfulOrderIds.removeAll(sharedFailedOrderIds);
    sharedExecutionResult.successfulCount = sharedSuccessfulOrderIds.size();
    ConnectorExecutionResult result = sharedExecutionResult;
    sharedExecutionResult = null;
    return result;
  }

  private static String getOrderItemQbLineIdQueryFields() {
    Map<String, Schema.SObjectField> flds = Schema.SObjectType.OrderItem.fields.getMap();
    List<String> res = new List<String>();
    if (flds.containsKey('qb_lineitemid__c')) res.add('QB_LineiTemID__c');
    if (flds.containsKey('quickbridgetlg__qb_lineitemid__c')) res.add('QuickBridgeTLG__QB_LineiTemID__c');
    return res.isEmpty() ? '' : ', ' + String.join(res, ', ');
  }

  private static String getAccountQboIdQueryFields() {
    Map<String, Schema.SObjectField> flds = Schema.SObjectType.Account.fields.getMap();
    List<String> res = new List<String>();
    if (flds.containsKey('quickbookid__c')) res.add('Account.QuickbookID__c');
    if (flds.containsKey('quickbridgetlg__quickbookid__c')) res.add('Account.QuickBridgeTLG__QuickbookID__c');
    return String.join(res, ', ');
  }

  private static String getProductQboIdQueryFields() {
    Map<String, Schema.SObjectField> flds = Schema.SObjectType.Product2.fields.getMap();
    List<String> res = new List<String>();
    if (flds.containsKey('quickbookid__c')) res.add('Product2.QuickbookID__c');
    if (flds.containsKey('quickbridgetlg__quickbookid__c')) res.add('Product2.QuickBridgeTLG__QuickbookID__c');
    return String.join(res, ', ');
  }

  public static String buildOrderQueryFields() {
    Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Order.fields.getMap();
    Set<String> names = new Set<String>{ 'Id', 'Status', 'AccountId', 'EffectiveDate', 'Description', 'Pricebook2Id', 'QuickbookID__c', 'SyncToken__c' };
    for (String sfField : QBObjectMappings.getOrderToInvoiceMapping().keySet()) {
      if (!sfField.contains('.')) {
        names.add(sfField);
      }
    }
    Set<String> resolved = new Set<String>();
    for (String f : names) {
      String key = f.toLowerCase();
      Schema.SObjectField token = schemaFields.get(key);
      if (token == null) {
        token = schemaFields.get('quickbridgetlg__' + key);
      }
      if (token != null) {
        resolved.add(token.getDescribe().getName());
      }
    }
    return String.join(new List<String>(resolved), ', ');
  }

  public static String buildOrderItemQueryFields() {
    Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.OrderItem.fields.getMap();
    Set<String> extra = new Set<String>();
    for (String sfField : QBObjectMappings.getOrderItemMapping().keySet()) {
      if (!sfField.contains('.')) {
        extra.add(sfField);
      }
    }
    // Base fields already listed in the SELECT; only append truly new ones.
    Set<String> base = new Set<String>{ 'id', 'quantity', 'unitprice', 'description', 'totalprice',
      'product2id', 'qb_lineitemid__c', 'quickbridgetlg__qb_lineitemid__c' };
    List<String> additional = new List<String>();
    for (String f : extra) {
      if (!base.contains(f.toLowerCase())) {
        Schema.SObjectField token = schemaFields.get(f.toLowerCase());
        if (token == null) {
          token = schemaFields.get('quickbridgetlg__' + f.toLowerCase());
        }
        if (token != null) {
          String apiName = token.getDescribe().getName();
          additional.add(apiName);
          base.add(apiName.toLowerCase());
        }
      }
    }
    return additional.isEmpty() ? '' : ', ' + String.join(additional, ', ');
  }

  public void execute(Database.BatchableContext bc, List<Order> scope) {
    // Disable order triggers during DML updates to prevent redundant/recursive sync work
    QuickBooksInvoiceHandler.setBatchContext(true);

    try {
      List<Order> ordersToUpdate = new List<Order>();
      List<OrderItem> itemsToUpdate = new List<OrderItem>();

      Map<String, String> headerMap = QBObjectMappings.getOrderToInvoiceMapping();
      Map<String, String> lineMap = QBObjectMappings.getOrderItemMapping();

      Set<Id> allAccountIds = new Set<Id>();
      Set<Id> allProductIds = new Set<Id>();
      for (Order ord : scope) {
        if (ord.AccountId != null) {
          allAccountIds.add(ord.AccountId);
        }
        if (ord.OrderItems != null) {
          for (OrderItem item : ord.OrderItems) {
            if (item.Product2Id != null) {
              allProductIds.add(item.Product2Id);
            }
          }
        }
      }
      Map<Id, Account> accountMap = new Map<Id, Account>();
      if (!allAccountIds.isEmpty()) {
        String aQuery = 'SELECT Id, ' + (getAccountQboIdQueryFields().replace('Account.', '')) + ' FROM Account WHERE Id IN :allAccountIds';
        for (Account a : (List<Account>) Database.query(aQuery)) {
          accountMap.put(a.Id, a);
        }
      }
      Map<Id, Product2> productMap = new Map<Id, Product2>();
      if (!allProductIds.isEmpty()) {
        String pQuery = 'SELECT Id, ' + (getProductQboIdQueryFields().replace('Product2.', '')) + ' FROM Product2 WHERE Id IN :allProductIds';
        for (Product2 p : (List<Product2>) Database.query(pQuery)) {
          productMap.put(p.Id, p);
        }
      }

      for (Order ord : scope) {
        try {
          if (ord.OrderItems == null || ord.OrderItems.isEmpty()) {
            System.debug(
              'Skipping Order ' + ord.Id + ' because it has no Line Items.'
            );
            recordSharedFailure(ord.Id, 'Order has no line items.', false, null);
            continue;
          }

          // Preflight: Account must have a QBO customer id before we can build CustomerRef.
          Account accRec = accountMap.get(ord.AccountId);
          String accQboId = getQboId(accRec);
          if (accRec == null || String.isBlank(accQboId)) {
            IntegrationWorkService.enqueueQuickBooksWork(
              'AccountUpsert',
              'Account',
              ord.AccountId,
              'Account:' + ord.AccountId,
              true
            );
            ErrorLogUtility.logCalloutFailure(
              'QuickBooks',
              'QBSalesOrderSyncBatch.execute',
              'Skipping Order ' + ord.Id + ': Account ' + ord.AccountId +
                ' has no QBO Customer ID. AccountUpsert work queued; re-sync after Account syncs.',
              null,
              'Order',
              ord.Id
            );
            recordSharedFailure(
              ord.Id,
              'Order Account has no QBO Customer ID.',
              true,
              null
            );
            continue;
          }

          // Preflight: every line product must have a QBO item id before we can build ItemRef.
          Set<Id> missingProductIds = new Set<Id>();
          Map<Id, String> prodQboIdMap = new Map<Id, String>();
          for (OrderItem item : ord.OrderItems) {
            Product2 prodRec = productMap.get(item.Product2Id);
            String prodQboId = getQboId(prodRec);
            if (prodRec == null || String.isBlank(prodQboId)) {
              missingProductIds.add(item.Product2Id);
            } else {
              prodQboIdMap.put(item.Product2Id, prodQboId);
            }
          }
          if (!missingProductIds.isEmpty()) {
            for (Id prodId : missingProductIds) {
              IntegrationWorkService.enqueueQuickBooksWork(
                'ProductUpsert',
                'Product2',
                prodId,
                'Product2:' + prodId,
                true
              );
            }
            ErrorLogUtility.logCalloutFailure(
              'QuickBooks',
              'QBSalesOrderSyncBatch.execute',
              'Skipping Order ' + ord.Id + ': ' + missingProductIds.size() +
                ' product(s) have no QBO Item ID. ProductUpsert work queued; re-sync after products sync.',
              null,
              'Order',
              ord.Id
            );
            recordSharedFailure(
              ord.Id,
              'One or more Order products have no QBO Item ID.',
              true,
              null
            );
            continue;
          }

          String endpointPath = '';
          String qboObjectName = '';

          if (ord.Status == 'Draft') {
            if (mapDraftOrdersAsEstimates) {
              // Create Estimate
              endpointPath = '/estimate';
              qboObjectName = 'Estimate';
            } else {
              // Create Invoice directly
              endpointPath = '/invoice';
              qboObjectName = 'Invoice';
            }
          } else if (ord.Status == 'Activated') { System.debug('Activate selected');
            endpointPath = '/invoice';
            qboObjectName = 'Invoice';
          } else {
            continue;
          }

          // Build request body
          Map<String, Object> requestBody = new Map<String, Object>();

          String ordQboId = getQboId(ord);
          Boolean isCreate = String.isBlank(ordQboId) || isInitialSync;
          for (String sfField : headerMap.keySet()) {
            String qboFieldMapping = headerMap.get(sfField);
            if (String.isBlank(qboFieldMapping)) {
              continue;
            }
            // CustomerRef is set explicitly below from the related Account.
            if (
              qboFieldMapping == 'CustomerRef.value' ||
              qboFieldMapping == 'CustomerRef'
            ) {
              continue;
            }
            String rootProp = qboFieldMapping.contains('.')
              ? qboFieldMapping.substringBefore('.')
              : qboFieldMapping;
            if (QBO_READONLY_PROPS.contains(rootProp)) {
              continue; // never push server-calculated totals
            }
            if (rootProp == 'Id' && isCreate) {
              continue; // Id is only valid on update
            }
            Object val = getFieldValue(ord, sfField);
            if (val != null) {
              if (val instanceof Date) {
                val = DateTime.newInstance(
                    (Date) val,
                    Time.newInstance(0, 0, 0, 0)
                  )
                  .format('yyyy-MM-dd');
              }
              putPath(requestBody, qboFieldMapping, val);
            }
          }

          Object effDateObj = getFieldValue(ord, 'EffectiveDate');
          if (!requestBody.containsKey('TxnDate') && effDateObj != null && effDateObj instanceof Date) {
              putPath(requestBody, 'TxnDate', DateTime.newInstance((Date) effDateObj, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd'));
          }
          Object descObj = getFieldValue(ord, 'Description');
          if (!requestBody.containsKey('CustomerMemo') && descObj != null && String.isNotBlank(String.valueOf(descObj))) {
              putPath(requestBody, 'CustomerMemo.value', String.valueOf(descObj));
          }

          // Customer Reference
          requestBody.put(
            'CustomerRef',
            new Map<String, String>{ 'value' => accQboId }
          );

          // Line items
          List<Map<String, Object>> lines = new List<Map<String, Object>>();
          for (OrderItem item : ord.OrderItems) {
            Map<String, Object> line = new Map<String, Object>();
            line.put('DetailType', 'SalesItemLineDetail');

            Map<String, Object> itemDetail = new Map<String, Object>();
            Decimal quantity = item.Quantity != null ? item.Quantity : 1;
            Decimal unitPrice = item.UnitPrice != null ? item.UnitPrice : 0;

            for (String sfField : lineMap.keySet()) {
              Object val = getFieldValue(item, sfField);
              String qboField = lineMap.get(sfField);
              if (val == null || String.isBlank(qboField)) {
                continue;
              }
              // Mappings may be stored as full nested paths
              // (e.g. 'Line.SalesItemLineDetail.Qty'); normalize to the leaf so
              // they land on the correct QBO node instead of becoming a literal
              // dotted property name (which QBO rejects with fault 2010).
              String leaf = normalizeLineLeaf(qboField);
              if (leaf == 'Qty') {
                quantity = (Decimal) val;
                itemDetail.put('Qty', quantity);
              } else if (leaf == 'UnitPrice') {
                unitPrice = (Decimal) val;
                itemDetail.put('UnitPrice', unitPrice);
              } else if (leaf == 'Description') {
                line.put('Description', val);
              } else if (leaf == 'Amount') {
                // Line amount is computed below from quantity * unitPrice.
                continue;
              } else if (leaf == 'ItemRef.value' || leaf == 'ItemRef') {
                // ItemRef is set below from Product2.QuickbookID__c; never push a
                // raw Salesforce Id here.
                continue;
              } else if (!leaf.contains('.')) {
                itemDetail.put(leaf, val);
              }
            }
            line.put('Amount', quantity * unitPrice);
            String itemQboId = prodQboIdMap.get(item.Product2Id);
            if (String.isNotBlank(itemQboId)) {
              itemDetail.put(
                'ItemRef',
                new Map<String, String>{ 'value' => itemQboId }
              );
            }
            line.put('SalesItemLineDetail', itemDetail);
            String itemQbLineId = (String) getFieldValue(item, qbLineItemIdField());
            if (
              String.isNotBlank(itemQbLineId) &&
              itemQbLineId.contains(':')
            ) {
              if (qboObjectName != 'Invoice') {
                line.put('Id', itemQbLineId.split(':')[1]);
              }
            }
            lines.add(line);
          }
          requestBody.put('Line', lines);

          // Handle existing QBO ID for updates / conversion
          String existingOrdQboId = getQboId(ord);
          if (String.isNotBlank(existingOrdQboId) && !isInitialSync) {
            if (ord.Status == 'Activated' && qboObjectName == 'Invoice') {
              System.debug('Converting Estimate to Invoice.');
            } else {
              requestBody.put('Id', existingOrdQboId);
              Object syncTokVal = getFieldValue(ord, getSyncTokenField('Order'));
              String ordSyncToken = syncTokVal != null ? String.valueOf(syncTokVal) : null;
              requestBody.put(
                'SyncToken',
                String.isBlank(ordSyncToken) ? '0' : ordSyncToken
              );
              requestBody.put('sparse', true);
            }
          }

          // API Callout
          String jsonBody = JSON.serialize(requestBody);
          HttpResponse res = QuickBooksAuthHandler.makeApiCall(
            'POST',
            endpointPath,
            jsonBody
          );

          if (res != null && res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
              res.getBody()
            );
            System.debug('responseMap:'+ responseMap);
            Map<String, Object> qboResponseObj = (Map<String, Object>) responseMap.get(
              qboObjectName
            );

            Order ordToUpdate = new Order(Id = ord.Id);
            String newQbId = (String) qboResponseObj.get('Id');
            String newSyncToken = (String) qboResponseObj.get('SyncToken');
            try { ordToUpdate.put(getQboIdField('Order'), newQbId); } catch(Exception e){}
            try { ordToUpdate.put(getSyncTokenField('Order'), newSyncToken); } catch(Exception e){}
            ordersToUpdate.add(ordToUpdate);
            sharedSuccessfulOrderIds.add(ord.Id);

            List<Object> qboLines = (List<Object>) qboResponseObj.get('Line');
            if (qboLines != null) {
              Integer qboLineIndex = 0;
              for (OrderItem item : ord.OrderItems) {
                while (qboLineIndex < qboLines.size()) {
                  Map<String, Object> qbLine = (Map<String, Object>) qboLines[
                    qboLineIndex
                  ];
                  if (qbLine.get('DetailType') == 'SalesItemLineDetail') {
                    OrderItem itemToUpdate = new OrderItem(Id = item.Id);
                    try { itemToUpdate.put(qbLineItemIdField(), newQbId + ':' + (String) qbLine.get('Id')); } catch(Exception e){}
                    itemsToUpdate.add(itemToUpdate);
                    qboLineIndex++;
                    break;
                  }
                  qboLineIndex++;
                }
              }
            }
          } else {
            System.debug(
              'QBO Sync Error: ' +
              (res != null
                ? res.getStatusCode() + ' - ' + res.getBody()
                : 'Null Response')
            );
            ErrorLogUtility.logCalloutFailure(
              'QuickBooks',
              'QBSalesOrderSyncBatch.execute',
              'QBO sales order sync failed: ' +
              (res != null
                ? res.getStatusCode() + ' - ' + res.getBody()
                : 'Null Response'),
              res == null ? null : res.getStatusCode(),
              'Order',
              ord == null ? null : ord.Id
            );
            recordSharedFailure(
              ord == null ? null : ord.Id,
              'QBO sales order sync failed.',
              IntegrationRetryPolicy.isRetryable(
                res == null ? null : res.getStatusCode()
              ),
              res == null ? null : res.getStatusCode()
            );
          }
        } catch (Exception e) {
          System.debug(
            'Exception in QBSalesOrderSyncBatch: ' +
              e.getMessage() +
              ' at Line ' +
              e.getLineNumber()
          );
          ErrorLogUtility.logException(
            'QuickBooks',
            'QBSalesOrderSyncBatch.execute',
            e,
            'Order',
            ord == null ? null : ord.Id
          );
          recordSharedFailure(
            ord == null ? null : ord.Id,
            e.getMessage(),
            IntegrationRetryPolicy.isRetryable(e),
            null
          );
        }
      }

      // DML updates
      if (!ordersToUpdate.isEmpty()) {
        Database.SaveResult[] orderResults = Database.update(
          ordersToUpdate,
          false
        );
        ErrorLogUtility.logDmlResults(
          'QuickBooks',
          'QBSalesOrderSyncBatch.execute.updateOrders',
          'update',
          ordersToUpdate,
          orderResults,
          null,
          null
        );
        for (Integer i = 0; i < orderResults.size(); i++) {
          if (!orderResults[i].isSuccess()) {
            recordSharedFailure(
              ordersToUpdate[i].Id,
              orderResults[i].getErrors()[0].getMessage(),
              false,
              null
            );
          }
        }
      }
      if (!itemsToUpdate.isEmpty()) {
        Database.SaveResult[] itemResults = Database.update(itemsToUpdate, false);
        ErrorLogUtility.logDmlResults(
          'QuickBooks',
          'QBSalesOrderSyncBatch.execute.updateOrderItems',
          'update',
          itemsToUpdate,
          itemResults,
          null,
          null
        );
        for (Integer i = 0; i < itemResults.size(); i++) {
          if (!itemResults[i].isSuccess()) {
            recordSharedFailure(
              scope != null && scope.size() == 1 ? scope[0].Id : null,
              itemResults[i].getErrors()[0].getMessage(),
              false,
              null
            );
          }
        }
      }
    } finally {
      // Re-enable order triggers
      QuickBooksInvoiceHandler.setBatchContext(false);
    }
  }

  private void recordSharedFailure(
    Id orderId,
    String message,
    Boolean retryable,
    Integer statusCode
  ) {
    if (sharedExecutionResult == null) {
      return;
    }
    if (orderId != null) {
      sharedFailedOrderIds.add(orderId);
    }
    sharedExecutionResult.addError(message);
    if (retryable == true) {
      sharedExecutionResult.retryable = true;
      sharedExecutionResult.retryDelaySeconds = 60;
      if (orderId != null && !sharedExecutionResult.retryRecordIds.contains(orderId)) {
        sharedExecutionResult.retryRecordIds.add(orderId);
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    System.debug('Order Sync Completed Successfully.');
  }

  // Writes value into requestBody, creating nested maps for a dotted QBO path
  // (e.g. 'CustomerMemo.value' -> {"CustomerMemo":{"value": ...}}).
  private void putPath(
    Map<String, Object> root,
    String dottedPath,
    Object value
  ) {
    if (root == null || String.isBlank(dottedPath)) {
      return;
    }
    if (!dottedPath.contains('.')) {
      root.put(dottedPath, value);
      return;
    }
    List<String> parts = dottedPath.split('\\.');
    Map<String, Object> current = root;
    for (Integer i = 0; i < parts.size() - 1; i++) {
      String part = parts[i];
      if (!(current.get(part) instanceof Map<String, Object>)) {
        current.put(part, new Map<String, Object>());
      }
      current = (Map<String, Object>) current.get(part);
    }
    current.put(parts[parts.size() - 1], value);
  }

  // Reduces a line-item mapping path to the leaf the line builder understands,
  // stripping the leading 'Line.' wrapper and a 'SalesItemLineDetail.' prefix.
  // 'Line.SalesItemLineDetail.Qty' -> 'Qty'; 'Line.SalesItemLineDetail.ItemRef.value'
  // -> 'ItemRef.value'; 'Line.Description' -> 'Description'; 'Line.Amount' -> 'Amount'.
  private String normalizeLineLeaf(String qboField) {
    String leaf = qboField;
    if (leaf.startsWith('Line.')) {
      leaf = leaf.substringAfter('Line.');
    }
    if (leaf.startsWith('SalesItemLineDetail.')) {
      leaf = leaf.substringAfter('SalesItemLineDetail.');
    }
    return leaf;
  }

  private Object getFieldValue(SObject obj, String fieldPath) {
    if (!fieldPath.contains('.')) {
      try {
        return obj.get(fieldPath);
      } catch (Exception e) {
        return null;
      }
    }
    List<String> fields = fieldPath.split('\\.');
    SObject currentObj = obj;
    for (Integer i = 0; i < fields.size() - 1; i++) {
      currentObj = currentObj.getSObject(fields[i]);
      if (currentObj == null)
        return null;
    }
    return currentObj.get(fields[fields.size() - 1]);
  }

  private String getQboId(SObject record) {
    if (record == null) {
      return null;
    }
    Map<String, Schema.SObjectField> flds = record.getSObjectType().getDescribe().fields.getMap();
    for (String key : flds.keySet()) {
      if (key.endsWith('quickbookid__c')) {
        try {
          String val = (String) record.get(flds.get(key).getDescribe().getName());
          if (String.isNotBlank(val)) return val;
        } catch (Exception e) {}
      }
    }
    return null;
  }

  private static String qbLineItemIdField() {
    Map<String, Schema.SObjectField> flds = Schema.SObjectType.OrderItem.fields.getMap();
    for (String key : flds.keySet()) {
      if (key.endsWith('qb_lineitemid__c')) return flds.get(key).getDescribe().getName();
    }
    return 'QB_LineiTemID__c';
  }

  private String getQboIdField(String sObjectName) {
    Map<String, Schema.SObjectField> flds = sObjectName == 'Account'
      ? Schema.SObjectType.Account.fields.getMap()
      : sObjectName == 'Product2'
        ? Schema.SObjectType.Product2.fields.getMap()
        : Schema.SObjectType.Order.fields.getMap();
    for (String key : flds.keySet()) {
      if (key.endsWith('quickbookid__c')) return flds.get(key).getDescribe().getName();
    }
    return 'QuickbookID__c';
  }

  private String getSyncTokenField(String sObjectName) {
    Map<String, Schema.SObjectField> flds = Schema.SObjectType.Order.fields.getMap();
    for (String key : flds.keySet()) {
      if (key.endsWith('synctoken__c')) return flds.get(key).getDescribe().getName();
    }
    return 'SyncToken__c';
  }
}
