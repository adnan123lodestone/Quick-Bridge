public with sharing class ConnectorAdapterAllowlist {
    private static final Set<String> ALLOWED = new Set<String>{
        'StripePaymentAdapter',
        'PayPalPaymentAdapter',
        'AuthorizeNetPaymentAdapter',
        'FedExCarrierAdapter',
        'UPSCarrierAdapter',
        'QuickBooksScheduledOperationAdapter',
        'ShopifyScheduledOperationAdapter',
        'QBAccountWorker',
        'QBProductWorker',
        'QBInvoiceWorker',
        'QBCreditMemoWorker',
        'QBPurchaseOrderWorker',
        'ShopifyIntegrationWorker',
        'UsageIntegrationWorker',
        'CarrierIntegrationWorker',
        'PaymentIntegrationWorker',
        'QRIntegrationWorker'
    };

    public static void assertAllowed(String className) {
        if (String.isBlank(className)) {
            return;
        }
        // Strip namespace prefix if present (e.g. 'QuickBridgeTLG.StripePaymentAdapter' → 'StripePaymentAdapter')
        String unqualified = className.contains('.') ? className.substringAfterLast('.') : className;
        if (!ALLOWED.contains(unqualified) && !ALLOWED.contains(className)) {
            ErrorLogUtility.logException(
                'QuickBridge',
                'ConnectorAdapterAllowlist.assertAllowed',
                new IllegalArgumentException('Unapproved adapter class: ' + className),
                null,
                null
            );
            throw new AuraHandledException('Configuration error: unapproved adapter class \'' + className + '\'.');
        }
    }
}