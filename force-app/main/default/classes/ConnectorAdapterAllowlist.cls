/**
 * @description Enforces the approved adapter class list for dynamic connector instantiation.
 */
public with sharing class ConnectorAdapterAllowlist {
  private static final Set<String> ALLOWED = new Set<String>{
    'StripePaymentAdapter',
    'PayPalPaymentAdapter',
    'AuthorizeNetPaymentAdapter',
    'FedExCarrierAdapter',
    'UPSCarrierAdapter',
    'DHLCarrierAdapter',
    'QuickBooksScheduledOperationAdapter',
    'ShopifyScheduledOperationAdapter',
    'KlaviyoScheduledOperationAdapter',
    'QBSchedulerConfigValidator',
    'QBAccountWorker',
    'QBProductWorker',
    'QBInvoiceWorker',
    'QBCreditMemoWorker',
    'QBPurchaseOrderWorker',
    'QBQuoteWorker',
    'ShopifyIntegrationWorker',
    'MetaIntegrationWorker',
    'MetaScheduledOperationAdapter',
    'NetSuiteIntegrationWorker',
    'NetSuiteScheduledOperationAdapter',
    'UsageIntegrationWorker',
    'CarrierIntegrationWorker',
    'PaymentIntegrationWorker',
    'QRIntegrationWorker',
    'QBORetryHandler',
    'ShopifyRetryHandler'
  };

  /**
   * @description Throws when a configured adapter class is not approved for dynamic use.
   * @param className Apex class name from connector metadata.
   */
  public static void assertAllowed(String className) {
    if (String.isBlank(className)) {
      return;
    }
    // Strip namespace prefix if present, for example QuickBridge_Int.StripePaymentAdapter.
    String unqualified = className.contains('.')
      ? className.substringAfterLast('.')
      : className;
    if (!ALLOWED.contains(unqualified) && !ALLOWED.contains(className)) {
      ErrorLogUtility.logException(
        'QuickBridge',
        'ConnectorAdapterAllowlist.assertAllowed',
        new IllegalArgumentException('Unapproved adapter class: ' + className),
        null,
        null
      );
      throw new AuraHandledException(
        'Configuration error: unapproved adapter class \'' + className + '\'.'
      );
    }
  }
}