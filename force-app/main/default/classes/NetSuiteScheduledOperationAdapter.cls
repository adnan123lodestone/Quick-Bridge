public with sharing class NetSuiteScheduledOperationAdapter implements ScheduledOperationAdapter {
  @TestVisible private static Boolean skipExecutionForTests = false;

  public void execute(Scheduled_Integration_Job__c job) {
    if (Test.isRunningTest() && skipExecutionForTests == true) {
      return;
    }
    String targetObject = job == null ? null : job.Source_Object__c;
    run(targetObject, job == null ? null : job.Direction__c);
  }

  public static void run(String targetObject, String direction) {
    String normalizedTarget = String.isBlank(targetObject)
      ? 'customer'
      : targetObject.toLowerCase().replaceAll('[^a-z0-9]', '');
    try {
      if (normalizedTarget == 'customer' || normalizedTarget == 'customers' || normalizedTarget == 'account') {
        NetSuiteCustomerService.syncCustomers(null, null);
      } else if (normalizedTarget == 'item' || normalizedTarget == 'items' || normalizedTarget == 'product' || normalizedTarget == 'product2') {
        NetSuiteItemService.syncItems(null, null);
      } else if (normalizedTarget == 'salesorder' || normalizedTarget == 'salesorders' || normalizedTarget == 'order') {
        NetSuiteSalesOrderService.syncSalesOrders(null, null);
      } else if (normalizedTarget == 'invoice' || normalizedTarget == 'invoices') {
        NetSuiteInvoiceService.syncInvoices(null, null);
      } else if (normalizedTarget == 'payment' || normalizedTarget == 'payments') {
        NetSuitePaymentService.syncPayments(null, null);
      } else if (normalizedTarget == 'fulfillment' || normalizedTarget == 'fulfillments' || normalizedTarget == 'shipment') {
        NetSuiteFulfillmentService.syncFulfillments(null, null);
      } else {
        throw new NetSuiteScheduledOperationException('Unsupported NetSuite scheduled object: ' + targetObject);
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

  public class NetSuiteScheduledOperationException extends Exception {}
}