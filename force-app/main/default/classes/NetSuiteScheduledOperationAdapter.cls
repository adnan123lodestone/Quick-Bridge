public with sharing class NetSuiteScheduledOperationAdapter implements ScheduledOperationAdapter, DeferredScheduledOperationAdapter {
  @TestVisible private static Boolean skipExecutionForTests = false;

  public void execute(Scheduled_Integration_Job__c job) {
    if (Test.isRunningTest() && skipExecutionForTests == true) {
      return;
    }
    String targetObject = job == null ? null : job.Source_Object__c;
    run(targetObject, job == null ? null : job.Direction__c);
  }

  public ConnectorScheduleDispatchResult dispatch(
    Scheduled_Integration_Job__c job,
    String leaseToken
  ) {
    try {
      return ConnectorWorkOrchestrationService.dispatchScheduled(
        job,
        leaseToken,
        buildRequest(job, leaseToken)
      );
    } catch (Exception exceptionValue) {
      return ConnectorScheduleDispatchResult.failed(exceptionValue.getMessage());
    }
  }

  @TestVisible
  private static IntegrationWorkRequest buildRequest(
    Scheduled_Integration_Job__c job,
    String leaseToken
  ) {
    String targetObject = job == null ? null : job.Source_Object__c;
    String operation = operationFor(targetObject);
    IntegrationWorkRequest request = ConnectorWorkOrchestrationService.scheduledRequest(
      job,
      leaseToken,
      'NetSuite',
      operation,
      canonicalSourceObject(operation),
      NetSuiteConfigService.CONNECTOR_KEY + ':' + operation,
      'NetSuite:' + operation,
      new Map<String, Object>{
        'targetObject' => targetObject,
        'direction' => job == null ? null : job.Direction__c
      }
    );
    return request;
  }

  public static void run(String targetObject, String direction) {
    try {
      String operation = operationFor(targetObject);
      if (operation == 'CustomerSync') {
        NetSuiteCustomerService.syncCustomers(null, null);
      } else if (operation == 'ItemSync') {
        NetSuiteItemService.syncItems(null, null);
      } else if (operation == 'SalesOrderSync') {
        NetSuiteSalesOrderService.syncSalesOrders(null, null);
      } else if (operation == 'InvoiceSync') {
        NetSuiteInvoiceService.syncInvoices(null, null);
      } else if (operation == 'PaymentSync') {
        NetSuitePaymentService.syncPayments(null, null);
      } else if (operation == 'FulfillmentSync') {
        NetSuiteFulfillmentService.syncFulfillments(null, null);
      }
      QuickBridgeAdminGuard.audit(
        'SCHEDULED_SYNC',
        NetSuiteConfigService.CONNECTOR_KEY,
        'Completed',
        'Target object: ' + targetObject + ', direction: ' + direction,
        null
      );
    } catch (Exception e) {
      QuickBridgeAdminGuard.audit(
        'SCHEDULED_SYNC',
        NetSuiteConfigService.CONNECTOR_KEY,
        'Failure',
        NetSuiteErrorMapper.sanitize(e.getMessage()),
        null
      );
      throw e;
    }
  }

  @TestVisible
  private static String operationFor(String targetObject) {
    String normalizedTarget = String.isBlank(targetObject)
      ? 'customer'
      : targetObject.toLowerCase().replaceAll('[^a-z0-9]', '');
    if (normalizedTarget == 'customer' || normalizedTarget == 'customers' || normalizedTarget == 'account') {
      return 'CustomerSync';
    }
    if (normalizedTarget == 'item' || normalizedTarget == 'items' || normalizedTarget == 'product' || normalizedTarget == 'product2') {
      return 'ItemSync';
    }
    if (normalizedTarget == 'salesorder' || normalizedTarget == 'salesorders' || normalizedTarget == 'order') {
      return 'SalesOrderSync';
    }
    if (normalizedTarget == 'invoice' || normalizedTarget == 'invoices') {
      return 'InvoiceSync';
    }
    if (normalizedTarget == 'payment' || normalizedTarget == 'payments') {
      return 'PaymentSync';
    }
    if (normalizedTarget == 'fulfillment' || normalizedTarget == 'fulfillments' || normalizedTarget == 'shipment') {
      return 'FulfillmentSync';
    }
    throw new NetSuiteScheduledOperationException(
      'Unsupported NetSuite scheduled object: ' + targetObject
    );
  }

  private static String canonicalSourceObject(String operation) {
    if (operation == 'CustomerSync') return 'Customer';
    if (operation == 'ItemSync') return 'Item';
    if (operation == 'SalesOrderSync') return 'SalesOrder';
    if (operation == 'InvoiceSync') return 'Invoice';
    if (operation == 'PaymentSync') return 'Payment';
    return 'Fulfillment';
  }

  public class NetSuiteScheduledOperationException extends Exception {}
}