public with sharing class NetSuiteIntegrationWorker implements IntegrationWorkHandler {
  public void handle(Integration_Work_Item__c item) {
    if (item == null) {
      throw new NetSuiteIntegrationWorkerException('Integration work item is required.');
    }
    String operation = normalize(item.Operation__c);
    if (operation == 'customersync') {
      NetSuiteCustomerService.syncCustomers(null, null);
      return;
    }
    if (operation == 'itemsync') {
      NetSuiteItemService.syncItems(null, null);
      return;
    }
    if (operation == 'salesordersync') {
      NetSuiteSalesOrderService.syncSalesOrders(null, null);
      return;
    }
    if (operation == 'invoicesync') {
      NetSuiteInvoiceService.syncInvoices(null, null);
      return;
    }
    if (operation == 'paymentsync') {
      NetSuitePaymentService.syncPayments(null, null);
      return;
    }
    if (operation == 'fulfillmentsync') {
      NetSuiteFulfillmentService.syncFulfillments(null, null);
      return;
    }
    throw new NetSuiteIntegrationWorkerException('Unsupported NetSuite operation: ' + item.Operation__c);
  }

  private static String normalize(String value) {
    return String.isBlank(value) ? '' : value.toLowerCase().replaceAll('[^a-z0-9]', '');
  }

  public class NetSuiteIntegrationWorkerException extends Exception {}
}
