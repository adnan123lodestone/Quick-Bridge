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
        'QuickBooksScheduledOperationAdapter',
        'ShopifyScheduledOperationAdapter',
        'KlaviyoScheduledOperationAdapter',
        'QBSchedulerConfigValidator',
        'QBAccountWorker',
        'QBProductWorker',
        'QBInvoiceWorker',
        'QBCreditMemoWorker',
        'QBPurchaseOrderWorker',
        'ShopifyIntegrationWorker',
        'UsageIntegrationWorker',
        'CarrierIntegrationWorker',
        'PaymentIntegrationWorker',
        'QRIntegrationWorker',
        'QBORetryHandler',
        'ShopifyRetryHandler'
    };

    /**
     * @description Throws when a configured adapter class is not approved for dynamic use.
     * Approval is satisfied by either the hardcoded ALLOWED set above or by any active
     * Integration_Connector_Capability__mdt record whose Adapter_Class__c matches the class name.
     * Adding a new adapter only requires deploying the capability metadata record; no code change needed.
     * @param className Apex class name from connector metadata.
     */
    public static void assertAllowed(String className) {
        if (String.isBlank(className)) {
            return;
        }
        // Strip namespace prefix if present, for example QuickBridgeTLG.StripePaymentAdapter.
        String unqualified = className.contains('.') ? className.substringAfterLast('.') : className;
        if (ALLOWED.contains(unqualified) || ALLOWED.contains(className)) {
            return;
        }
        // Secondary check: any active capability metadata record registers the class automatically.
        List<Integration_Connector_Capability__mdt> metaMatch = [
            SELECT Id
            FROM Integration_Connector_Capability__mdt
            WHERE Adapter_Class__c = :unqualified
            AND Enabled__c = true
            LIMIT 1
        ];
        if (!metaMatch.isEmpty()) {
            return;
        }
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