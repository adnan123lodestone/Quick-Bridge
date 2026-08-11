/**
 * Compatibility strategy for provider implementations that already expose a
 * deterministic outbound scope operation. The shared batch owns querying,
 * retry chaining, and schedule completion; provider classes retain payload and
 * response semantics during phased migration.
 */
public inherited sharing class ConnectorOutboundOperationExecutor implements ConnectorExecutionService.OperationExecutor {
  public ConnectorExecutionResult executeInboundPage(
    ConnectorExecutionRequest request
  ) {
    return ConnectorExecutionResult.failed(
      'The outbound compatibility strategy does not support inbound execution.',
      false,
      null
    );
  }

  public ConnectorExecutionResult executeOutboundScope(
    ConnectorExecutionRequest request,
    List<SObject> scope
  ) {
    try {
      String connector = normalize(
        request == null ? null : request.connectorKey
      );
      String entity = normalize(
        request == null ? null : request.externalEntity
      );
      if (connector == 'shopify' && entity == 'customer') {
        return ShopifyCustomersOutboundBatch.executeSharedScope(request, scope);
      }
      if (connector == 'shopify' && entity == 'product') {
        return ShopifyProductsOutboundBatch.executeSharedScope(request, scope);
      }
      if (connector == 'shopify' && entity == 'order') {
        return ShopifyOrdersOutboundBatch.executeSharedScope(request, scope);
      }
      if (connector == 'qbo' && (entity == 'customer' || entity == 'vendor')) {
        return executeQuickBooksAccounts(request, scope);
      }
      if (connector == 'qbo' && entity == 'item') {
        return executeQuickBooksProducts(request, scope);
      }
      if (
        connector == 'qbo' &&
        entity == 'invoice' &&
        normalize(request.salesforceObject) == 'order'
      ) {
        return executeQuickBooksOrders(request, scope);
      }
      if (
        connector == 'qbo' &&
        entity == 'purchaseorder' &&
        normalize(request.salesforceObject) == 'purchaseorderc'
      ) {
        return executeQuickBooksPurchaseOrders(request, scope);
      }
      if (
        connector == 'qbo' &&
        entity == 'estimate' &&
        normalize(request.salesforceObject) == 'quote'
      ) {
        return executeQuickBooksQuotes(request, scope);
      }
      return ConnectorExecutionResult.failed(
        'The registered outbound operation is not implemented by the compatibility strategy.',
        false,
        null
      );
    } catch (Exception exceptionValue) {
      return ConnectorExecutionResult.failed(
        exceptionValue.getMessage(),
        false,
        null
      );
    }
  }

  private static ConnectorExecutionResult executeQuickBooksAccounts(
    ConnectorExecutionRequest request,
    List<SObject> scope
  ) {
    List<Account> accounts = new List<Account>();
    Set<Id> accountIds = new Set<Id>();
    for (SObject recordValue : scope == null ? new List<SObject>() : scope) {
      if (recordValue != null && recordValue.Id != null) {
        accountIds.add(recordValue.Id);
      }
    }
    accounts.addAll(
      QuickBooksScheduledOperationAdapter.loadAccountsForSharedExecution(
        accountIds
      )
    );
    if (!accounts.isEmpty()) {
      IntegrationUsageService.assertCanConsumeTask(
        'QuickBooks',
        accounts.size()
      );
      return QBAccountService.syncAccountsToQuickBooksShared(
        accounts,
        request.initialSync == true
      );
    }
    return successfulResult(0);
  }

  private static ConnectorExecutionResult executeQuickBooksProducts(
    ConnectorExecutionRequest request,
    List<SObject> scope
  ) {
    List<Product2> products = new List<Product2>();
    for (SObject recordValue : scope == null ? new List<SObject>() : scope) {
      products.add((Product2) recordValue);
    }
    if (!products.isEmpty()) {
      IntegrationUsageService.assertCanConsumeTask(
        'QuickBooks',
        products.size()
      );
      return QBProductService.syncProductsToQuickBooksShared(
        products,
        request.initialSync == true
      );
    }
    return successfulResult(0);
  }

  private static ConnectorExecutionResult executeQuickBooksOrders(
    ConnectorExecutionRequest request,
    List<SObject> scope
  ) {
    Set<Id> orderIds = new Set<Id>();
    for (SObject recordValue : scope == null ? new List<SObject>() : scope) {
      if (recordValue != null && recordValue.Id != null) {
        orderIds.add(recordValue.Id);
      }
    }
    List<Order> orders = QBSalesOrderSyncBatch.loadOrdersForSharedExecution(
      orderIds
    );
    if (orders.isEmpty()) {
      return successfulResult(0);
    }
    return new QBSalesOrderSyncBatch(orderIds, request.initialSync == true)
      .executeSharedScope(orders);
  }

  private static ConnectorExecutionResult executeQuickBooksPurchaseOrders(
    ConnectorExecutionRequest request,
    List<SObject> scope
  ) {
    Set<Id> recordIds = new Set<Id>();
    for (SObject recordValue : scope == null ? new List<SObject>() : scope) {
      if (recordValue != null && recordValue.Id != null) {
        recordIds.add(recordValue.Id);
      }
    }
    if (recordIds.isEmpty()) {
      return successfulResult(0);
    }
    return new QuickBooksPurchaseOrderBatch(
        recordIds,
        request.initialSync == true
      )
      .executeSharedScope(scope);
  }

  private static ConnectorExecutionResult executeQuickBooksQuotes(
    ConnectorExecutionRequest request,
    List<SObject> scope
  ) {
    Set<Id> quoteIds = new Set<Id>();
    for (SObject recordValue : scope == null ? new List<SObject>() : scope) {
      if (recordValue != null && recordValue.Id != null) {
        quoteIds.add(recordValue.Id);
      }
    }
    List<Quote> quotes = QBQuoteToEstimateSyncBatch.loadQuotesForSharedExecution(
      quoteIds
    );
    if (quotes.isEmpty()) {
      return successfulResult(0);
    }
    return new QBQuoteToEstimateSyncBatch(quoteIds, request.initialSync == true)
      .executeSharedScope(quotes);
  }

  private static ConnectorExecutionResult successfulResult(Integer countValue) {
    ConnectorExecutionResult result = ConnectorExecutionResult.success();
    result.processedCount = countValue == null ? 0 : countValue;
    result.successfulCount = result.processedCount;
    return result;
  }

  public ConnectorExecutionResult executeSingle(
    ConnectorExecutionRequest request
  ) {
    if (
      request == null ||
      request.recordIds == null ||
      request.recordIds.size() != 1
    ) {
      return ConnectorExecutionResult.failed(
        'Single-record connector execution requires exactly one Salesforce record ID.',
        false,
        null
      );
    }
    Schema.SObjectType objectType = Schema.getGlobalDescribe()
      .get(request.salesforceObject);
    if (objectType == null) {
      return ConnectorExecutionResult.failed(
        'The registered Salesforce object is unavailable.',
        false,
        null
      );
    }
    return executeOutboundScope(
      request,
      new List<SObject>{ objectType.newSObject(request.recordIds[0]) }
    );
  }

  private static String normalize(String value) {
    return String.isBlank(value)
      ? ''
      : value.toLowerCase().replaceAll('[^a-z0-9]', '');
  }
}
