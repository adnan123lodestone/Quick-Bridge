public with sharing class LegacyConnectorRegistryFallback {
    public static List<ConnectorRegistryService.ConnectorDescriptor> connectors() {
        return new List<ConnectorRegistryService.ConnectorDescriptor>{
            descriptor('qbo', 'quickbooks', 'QuickBooks', 'qbo,quickbooks,quickbooksonline,quickbooks online', 'Accounting', 'QuickBooks', 'QuickBooks_Is_Active__c', 'QuickBooks_End_Date__c', 'Company_Name__c,QuickBooks_Realm_ID__c,QuickBooks_Is_Active__c,QuickBooks_Start_Date__c,QuickBooks_End_Date__c', 10, true, true, true, true, false, false, false),
            descriptor('shopify', 'shopify', 'Shopify', 'shopify', 'Commerce', 'Shopify', 'Shopify_Is_Active__c', 'Shopify_End_Date__c', 'Company_Name__c,Shopify_Store_URL__c,Shopify_Access_Token__c,Shopify_API_Key__c,Shopify_API_Secret__c,Shopify_Is_Active__c,Shopify_Start_Date__c,Shopify_End_Date__c', 20, true, true, true, true, false, false, false),
            descriptor('stripe', 'stripe', 'Stripe', 'stripe', 'Payment', 'Stripe', 'Stripe_Active__c', 'Stripe_End_Date__c', 'Company_Name__c,Stripe_Publishable_Key__c,Stripe_Webhook_Signing_Secret__c,Stripe_Active__c,Stripe_Use_Sandbox__c,Stripe_Start_Date__c,Stripe_End_Date__c', 30, true, true, false, false, true, true, false),
            descriptor('authorizenet', 'authorizenet', 'Authorize.Net', 'authorizenet,authorize.net,authorize net,authnet', 'Payment', 'AuthorizeNet', 'AuthorizeNet_Active__c', 'AuthorizeNet_End_Date__c', 'Company_Name__c,AuthorizeNet_API_Login_ID__c,AuthorizeNet_Public_Client_Key__c,AuthorizeNet_Webhook_Signing_Key__c,AuthorizeNet_Active__c,AuthorizeNet_Use_Sandbox__c,AuthorizeNet_Start_Date__c,AuthorizeNet_End_Date__c', 40, true, true, false, false, true, true, false),
            descriptor('paypal', 'paypal', 'PayPal', 'paypal,pay pal', 'Payment', 'PayPal', 'PayPal_Active__c', 'PayPal_EndDate__c', 'Company_Name__c,PayPal_ClientId__c,WebhookId__c,PayPal_Active__c,PayPal_UseSandbox__c,PayPal_StartDate__c,PayPal_EndDate__c', 50, true, true, false, false, true, true, false),
            descriptor('fedex', 'fedex', 'FedEx', 'fedex', 'Carrier', 'FedEx', 'FedEx_Active__c', 'FedEx_End_Date__c', 'FedEx_Client_Id__c,FedEx_Client_Secret__c,FedEx_Account_Number__c,FedEx_Environment__c,FedEx_Default_Service_Type__c,FedEx_Default_Packaging_Type__c,FedEx_Default_Pickup_Type__c,FedEx_Active__c,FedEx_Start_Date__c,FedEx_End_Date__c', 60, true, true, false, false, false, false, true),
            descriptor('ups', 'ups', 'UPS', 'ups', 'Carrier', 'UPS', 'UPS_Active__c', 'UPS_End_Date__c', 'UPS_Client_Id__c,UPS_Client_Secret__c,UPS_Account_Number__c,UPS_Environment__c,UPS_Default_Service_Code__c,UPS_Active__c,UPS_Start_Date__c,UPS_End_Date__c', 70, true, true, false, false, false, false, true)
        };
    }

    public static String defaultAdapterClass(String connectorKey, String capabilityKey) {
        String connector = ConnectorRegistryService.normalize(connectorKey);
        String capability = normalizeCapability(capabilityKey);

        if (capability == 'paymentcheckout' || capability == 'paymentprovider') {
            if (connector == 'stripe') return 'StripePaymentAdapter';
            if (connector == 'paypal') return 'PayPalPaymentAdapter';
            if (connector == 'authorizenet') return 'AuthorizeNetPaymentAdapter';
        }
        if (capability == 'scheduleroperation') {
            if (connector == 'qbo' || connector == 'quickbooks') return 'QuickBooksScheduledOperationAdapter';
            if (connector == 'shopify') return 'ShopifyScheduledOperationAdapter';
        }
        if (capability == 'carrieroperation') {
            if (connector == 'fedex') return 'FedExCarrierAdapter';
            if (connector == 'ups') return 'UPSCarrierAdapter';
        }
        if (capability == 'retryhandler') {
            if (connector == 'qbo' || connector == 'quickbooks') return 'QBORetryHandler';
            if (connector == 'shopify') return 'ShopifyRetryHandler';
        }
        if (capability.startsWith('work')) {
            String workHandler = workHandlerClassFor(connectorKey, capabilityKey);
            return String.isBlank(workHandler) ? null : workHandler;
        }
        return null;
    }

    public static String workHandlerClassFor(String connectorKey, String operationOrCapability) {
        String connector = ConnectorRegistryService.normalize(connectorKey);
        String operation = normalizeCapability(operationOrCapability);
        if (operation.startsWith('work')) {
            operation = operation.substring(4);
        }

        if (connector == 'qbo' || connector == 'quickbooks' || connector == 'qbonline') {
            if (operation == 'accountupsert') return 'QBAccountWorker';
            if (operation == 'productupsert') return 'QBProductWorker';
            if (operation == 'invoiceupsert') return 'QBInvoiceWorker';
            if (operation == 'creditmemoupsert') return 'QBCreditMemoWorker';
            if (operation == 'purchaseorderupsert') return 'QBPurchaseOrderWorker';
            if (operation == 'quoteupsert') return 'QBQuoteWorker';
        }
        if (connector == 'shopify') {
            return 'ShopifyIntegrationWorker';
        }
        if (connector == 'carrier') {
            return 'CarrierIntegrationWorker';
        }
        if (connector == 'payment') {
            return 'PaymentIntegrationWorker';
        }
        if (connector == 'qr') {
            return 'QRIntegrationWorker';
        }
        return null;
    }

    public static List<ConnectorRegistryService.ObjectMapDescriptor> objectMapsFor(String connectorKey) {
        String connector = ConnectorRegistryService.normalize(connectorKey);
        List<ConnectorRegistryService.ObjectMapDescriptor> rows = new List<ConnectorRegistryService.ObjectMapDescriptor>();
        if (connector == 'qbo' || connector == 'quickbooks' || connector == 'qbonline') {
            addObjectMap(rows, connectorKey, 'Account', 'Customer');
            addObjectMap(rows, connectorKey, 'Product2', 'Item');
            addObjectMap(rows, connectorKey, 'Order', 'Invoice');
            addObjectMap(rows, connectorKey, 'Invoice__c', 'Invoice');
        } else if (connector == 'shopify') {
            addObjectMap(rows, connectorKey, 'Account', 'Customer');
            addObjectMap(rows, connectorKey, 'Product2', 'Product');
            addObjectMap(rows, connectorKey, 'Order', 'Order');
            addObjectMap(rows, connectorKey, 'OrderItem', 'LineItem');
        }
        return rows;
    }

    private static ConnectorRegistryService.ConnectorDescriptor descriptor(
        String connectorKey,
        String productKey,
        String label,
        String aliases,
        String category,
        String configRecordName,
        String activeField,
        String expiryField,
        String editableFields,
        Integer sortOrder,
        Boolean hasConfig,
        Boolean hasReporting,
        Boolean hasMapping,
        Boolean hasScheduler,
        Boolean hasCheckout,
        Boolean hasPayment,
        Boolean hasCarrier
    ) {
        ConnectorRegistryService.ConnectorDescriptor descriptor = new ConnectorRegistryService.ConnectorDescriptor();
        descriptor.connectorKey = connectorKey;
        descriptor.productKey = productKey;
        descriptor.label = label;
        descriptor.aliases = aliases;
        descriptor.category = category;
        descriptor.iconName = null;
        descriptor.logoUrl = null;
        descriptor.sortOrder = sortOrder;
        descriptor.entitlementKey = productKey;
        descriptor.configSchemaKey = connectorKey;
        descriptor.configRecordName = configRecordName;
        descriptor.integrationType = label;
        descriptor.activeField = activeField;
        descriptor.expiryField = expiryField;
        descriptor.editableFields = splitList(editableFields);
        descriptor.enabled = true;
        descriptor.catalogActive = true;
        descriptor.status = 'Available';
        descriptor.capabilities = new List<String>();
        descriptor.adapterClassByCapability = new Map<String, String>();
        descriptor.configFields = new List<ConnectorRegistryService.ConfigFieldDescriptor>();
        descriptor.objectMappings = new List<ConnectorRegistryService.ObjectMapDescriptor>();
        descriptor.hasConfig = hasConfig;
        descriptor.hasReporting = hasReporting;
        descriptor.hasMapping = hasMapping;
        descriptor.hasScheduler = hasScheduler;
        descriptor.hasCheckout = hasCheckout;
        descriptor.hasPayment = hasPayment;
        descriptor.hasCarrier = hasCarrier;
        return descriptor;
    }

    private static void addObjectMap(List<ConnectorRegistryService.ObjectMapDescriptor> rows, String connectorKey, String salesforceObject, String externalObject) {
        ConnectorRegistryService.ObjectMapDescriptor row = new ConnectorRegistryService.ObjectMapDescriptor();
        row.connectorKey = connectorKey;
        row.salesforceObject = salesforceObject;
        row.externalObject = externalObject;
        row.direction = 'Both';
        rows.add(row);
    }

    private static String normalizeCapability(String capabilityKey) {
        return String.isBlank(capabilityKey) ? '' : capabilityKey.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static List<String> splitList(String rawValue) {
        List<String> values = new List<String>();
        if (String.isBlank(rawValue)) return values;
        for (String value : rawValue.split(',')) {
            if (String.isNotBlank(value)) values.add(value.trim());
        }
        return values;
    }
}
