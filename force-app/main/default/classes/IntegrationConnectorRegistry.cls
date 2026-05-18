public with sharing class IntegrationConnectorRegistry {
    public class ConnectorDescriptor {
        @AuraEnabled public String connectorKey { get; set; }
        @AuraEnabled public String productKey { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String aliases { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String configRecordName { get; set; }
        @AuraEnabled public String activeField { get; set; }
        @AuraEnabled public String expiryField { get; set; }
        @AuraEnabled public List<String> editableFields { get; set; }
        @AuraEnabled public Integer displayOrder { get; set; }
        @AuraEnabled public Boolean enabled { get; set; }
        @AuraEnabled public Boolean hasConfig { get; set; }
        @AuraEnabled public Boolean hasReporting { get; set; }
        @AuraEnabled public Boolean hasMapping { get; set; }
        @AuraEnabled public Boolean hasScheduler { get; set; }
        @AuraEnabled public Boolean hasCheckout { get; set; }
        @AuraEnabled public Boolean hasPayment { get; set; }
        @AuraEnabled public Boolean hasCarrier { get; set; }
    }

    private static List<ConnectorDescriptor> cachedConnectors;

    @AuraEnabled(cacheable=true)
    public static List<ConnectorDescriptor> getConnectorDescriptors() {
        return connectors();
    }

    public static List<ConnectorDescriptor> connectors() {
        if (cachedConnectors != null) {
            return cloneList(cachedConnectors);
        }

        List<ConnectorDescriptor> rows = new List<ConnectorDescriptor>();
        try {
            for (Integration_Connector__mdt row : [
                SELECT Connector_Key__c, Product_Key__c, Provider_Label__c, Aliases__c, Category__c,
                    Config_Record_Name__c, Active_Field__c, Expiry_Field__c, Editable_Fields__c,
                    Display_Order__c, Enabled__c, Has_Config__c, Has_Reporting__c, Has_Mapping__c,
                    Has_Scheduler__c, Has_Checkout__c, Has_Payment__c, Has_Carrier__c
                FROM Integration_Connector__mdt
                WHERE Enabled__c = true
                ORDER BY Display_Order__c ASC, Provider_Label__c ASC
            ]) {
                rows.add(fromMetadata(row));
            }
        } catch (Exception ignored) {
        }

        cachedConnectors = rows.isEmpty() ? fallbackConnectors() : rows;
        return cloneList(cachedConnectors);
    }

    public static ConnectorDescriptor byKey(String keyOrAlias) {
        String normalized = normalize(keyOrAlias);
        if (String.isBlank(normalized)) {
            return null;
        }
        for (ConnectorDescriptor connector : connectors()) {
            if (normalize(connector.connectorKey) == normalized || normalize(connector.productKey) == normalized || aliasSet(connector).contains(normalized)) {
                return cloneConnector(connector);
            }
        }
        return null;
    }

    public static List<ConnectorDescriptor> paymentConnectors() {
        List<ConnectorDescriptor> result = new List<ConnectorDescriptor>();
        for (ConnectorDescriptor connector : connectors()) {
            if (connector.hasPayment == true || connector.hasCheckout == true) {
                result.add(connector);
            }
        }
        return result;
    }

    public static List<String> productKeys() {
        List<String> keys = new List<String>();
        for (ConnectorDescriptor connector : connectors()) {
            if (String.isNotBlank(connector.productKey)) {
                keys.add(connector.productKey);
            }
        }
        return keys;
    }

    public static Map<String, ConnectorDescriptor> byProductKey() {
        Map<String, ConnectorDescriptor> result = new Map<String, ConnectorDescriptor>();
        for (ConnectorDescriptor connector : connectors()) {
            result.put(connector.productKey, connector);
        }
        return result;
    }

    public static String normalizeProductKey(String product) {
        ConnectorDescriptor connector = byKey(product);
        return connector == null ? null : connector.productKey;
    }

    public static String normalize(String value) {
        return String.isBlank(value) ? '' : value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static ConnectorDescriptor fromMetadata(Integration_Connector__mdt row) {
        ConnectorDescriptor connector = new ConnectorDescriptor();
        connector.connectorKey = row.Connector_Key__c;
        connector.productKey = row.Product_Key__c;
        connector.label = row.Provider_Label__c;
        connector.aliases = row.Aliases__c;
        connector.category = row.Category__c;
        connector.configRecordName = row.Config_Record_Name__c;
        connector.activeField = row.Active_Field__c;
        connector.expiryField = row.Expiry_Field__c;
        connector.editableFields = splitList(row.Editable_Fields__c);
        connector.displayOrder = row.Display_Order__c == null ? 999 : row.Display_Order__c.intValue();
        connector.enabled = row.Enabled__c == true;
        connector.hasConfig = row.Has_Config__c == true;
        connector.hasReporting = row.Has_Reporting__c == true;
        connector.hasMapping = row.Has_Mapping__c == true;
        connector.hasScheduler = row.Has_Scheduler__c == true;
        connector.hasCheckout = row.Has_Checkout__c == true;
        connector.hasPayment = row.Has_Payment__c == true;
        connector.hasCarrier = row.Has_Carrier__c == true;
        return connector;
    }

    private static List<ConnectorDescriptor> fallbackConnectors() {
        return new List<ConnectorDescriptor>{
            fallback('qbo', 'quickbooks', 'QuickBooks', 'qbo,quickbooks,quickbooksonline,quickbooks online', 'Accounting', 'QuickBooks', 'QuickBooks_Is_Active__c', 'QuickBooks_End_Date__c', 'Company_Name__c,QuickBooks_Realm_ID__c,QuickBooks_Is_Active__c,QuickBooks_Start_Date__c,QuickBooks_End_Date__c', 10, true, true, true, false, false, false),
            fallback('shopify', 'shopify', 'Shopify', 'shopify', 'Commerce', 'Shopify', 'Shopify_Is_Active__c', 'Shopify_End_Date__c', 'Company_Name__c,Shopify_Store_URL__c,Shopify_Access_Token__c,Shopify_API_Key__c,Shopify_API_Secret__c,Shopify_Is_Active__c,Shopify_Start_Date__c,Shopify_End_Date__c', 20, true, true, true, false, false, false),
            fallback('stripe', 'stripe', 'Stripe', 'stripe', 'Payment', 'Stripe', 'Stripe_Active__c', 'Stripe_End_Date__c', 'Company_Name__c,Stripe_Publishable_Key__c,Stripe_Webhook_Signing_Secret__c,Stripe_Active__c,Stripe_Use_Sandbox__c,Stripe_Start_Date__c,Stripe_End_Date__c', 30, true, true, false, true, true, false),
            fallback('authorizenet', 'authorizenet', 'Authorize.Net', 'authorizenet,authorize.net,authorize net,authnet', 'Payment', 'AuthorizeNet', 'AuthorizeNet_Active__c', 'AuthorizeNet_End_Date__c', 'Company_Name__c,AuthorizeNet_API_Login_ID__c,AuthorizeNet_Public_Client_Key__c,AuthorizeNet_Webhook_Signing_Key__c,AuthorizeNet_Active__c,AuthorizeNet_Use_Sandbox__c,AuthorizeNet_Start_Date__c,AuthorizeNet_End_Date__c', 40, true, false, false, true, true, false),
            fallback('paypal', 'paypal', 'PayPal', 'paypal,pay pal', 'Payment', 'PayPal', 'PayPal_Active__c', 'PayPal_EndDate__c', 'Company_Name__c,PayPal_ClientId__c,PayPal_Active__c,PayPal_UseSandbox__c,PayPal_StartDate__c,PayPal_EndDate__c', 50, true, false, false, true, true, false),
            fallback('fedex', 'fedex', 'FedEx', 'fedex', 'Carrier', 'FedEx', 'FedEx_Active__c', 'FedEx_End_Date__c', 'FedEx_Client_Id__c,FedEx_Client_Secret__c,FedEx_Account_Number__c,FedEx_Environment__c,FedEx_Default_Service_Type__c,FedEx_Default_Packaging_Type__c,FedEx_Default_Pickup_Type__c,FedEx_Active__c,FedEx_Start_Date__c,FedEx_End_Date__c', 60, true, true, false, false, false, true),
            fallback('ups', 'ups', 'UPS', 'ups', 'Carrier', 'UPS', 'UPS_Active__c', 'UPS_End_Date__c', 'UPS_Client_Id__c,UPS_Client_Secret__c,UPS_Account_Number__c,UPS_Environment__c,UPS_Default_Service_Code__c,UPS_Active__c,UPS_Start_Date__c,UPS_End_Date__c', 70, true, true, false, false, false, true)
        };
    }

    private static ConnectorDescriptor fallback(String connectorKey, String productKey, String label, String aliases, String category, String recordName, String activeField, String expiryField, String editableFields, Integer orderValue, Boolean hasConfig, Boolean hasMapping, Boolean hasScheduler, Boolean hasCheckout, Boolean hasPayment, Boolean hasCarrier) {
        ConnectorDescriptor connector = new ConnectorDescriptor();
        connector.connectorKey = connectorKey;
        connector.productKey = productKey;
        connector.label = label;
        connector.aliases = aliases;
        connector.category = category;
        connector.configRecordName = recordName;
        connector.activeField = activeField;
        connector.expiryField = expiryField;
        connector.editableFields = splitList(editableFields);
        connector.displayOrder = orderValue;
        connector.enabled = true;
        connector.hasConfig = hasConfig;
        connector.hasReporting = true;
        connector.hasMapping = hasMapping;
        connector.hasScheduler = hasScheduler;
        connector.hasCheckout = hasCheckout;
        connector.hasPayment = hasPayment;
        connector.hasCarrier = hasCarrier;
        return connector;
    }

    private static Set<String> aliasSet(ConnectorDescriptor connector) {
        Set<String> result = new Set<String>();
        for (String aliasValue : splitList(connector.aliases)) {
            result.add(normalize(aliasValue));
        }
        return result;
    }

    private static List<String> splitList(String rawValue) {
        List<String> values = new List<String>();
        if (String.isBlank(rawValue)) {
            return values;
        }
        for (String value : rawValue.split(',')) {
            if (String.isNotBlank(value)) {
                values.add(value.trim());
            }
        }
        return values;
    }

    private static List<ConnectorDescriptor> cloneList(List<ConnectorDescriptor> source) {
        List<ConnectorDescriptor> result = new List<ConnectorDescriptor>();
        for (ConnectorDescriptor connector : source) {
            result.add(cloneConnector(connector));
        }
        return result;
    }

    private static ConnectorDescriptor cloneConnector(ConnectorDescriptor source) {
        ConnectorDescriptor cloneValue = new ConnectorDescriptor();
        cloneValue.connectorKey = source.connectorKey;
        cloneValue.productKey = source.productKey;
        cloneValue.label = source.label;
        cloneValue.aliases = source.aliases;
        cloneValue.category = source.category;
        cloneValue.configRecordName = source.configRecordName;
        cloneValue.activeField = source.activeField;
        cloneValue.expiryField = source.expiryField;
        cloneValue.editableFields = source.editableFields == null ? new List<String>() : new List<String>(source.editableFields);
        cloneValue.displayOrder = source.displayOrder;
        cloneValue.enabled = source.enabled;
        cloneValue.hasConfig = source.hasConfig;
        cloneValue.hasReporting = source.hasReporting;
        cloneValue.hasMapping = source.hasMapping;
        cloneValue.hasScheduler = source.hasScheduler;
        cloneValue.hasCheckout = source.hasCheckout;
        cloneValue.hasPayment = source.hasPayment;
        cloneValue.hasCarrier = source.hasCarrier;
        return cloneValue;
    }
}