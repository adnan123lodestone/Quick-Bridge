public with sharing class IntegrationConnectorRegistry {
    public class ConnectorDescriptor {
        @AuraEnabled public String connectorKey { get; set; }
        @AuraEnabled public String productKey { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String aliases { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String configRecordName { get; set; }
        @AuraEnabled public String integrationType { get; set; }
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
        @AuraEnabled public String logoUrl { get; set; }
        @AuraEnabled public Boolean catalogActive { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public String status { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<ConnectorDescriptor> getConnectorDescriptors() {
        return connectors();
    }

    public static List<ConnectorDescriptor> connectors() {
        List<ConnectorDescriptor> result = new List<ConnectorDescriptor>();
        for (ConnectorRegistryService.ConnectorDescriptor descriptor : ConnectorRegistryService.connectors()) {
            result.add(fromCanonical(descriptor));
        }
        return result;
    }

    public static ConnectorDescriptor byKey(String keyOrAlias) {
        ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(keyOrAlias);
        return descriptor == null ? null : fromCanonical(descriptor);
    }

    public static List<ConnectorDescriptor> paymentConnectors() {
        List<ConnectorDescriptor> result = new List<ConnectorDescriptor>();
        for (ConnectorRegistryService.ConnectorDescriptor descriptor : ConnectorRegistryService.byCapability('payment.checkout')) {
            result.add(fromCanonical(descriptor));
        }
        return result;
    }

    public static List<String> productKeys() {
        List<String> keys = new List<String>();
        for (ConnectorDescriptor connector : connectors()) {
            if (String.isNotBlank(connector.productKey)) keys.add(connector.productKey);
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
        return ConnectorRegistryService.normalize(value);
    }

    public static void clearCache() {
        ConnectorRegistryService.clearCache();
    }

    private static ConnectorDescriptor fromCanonical(ConnectorRegistryService.ConnectorDescriptor source) {
        ConnectorDescriptor connector = new ConnectorDescriptor();
        connector.connectorKey = source.connectorKey;
        connector.productKey = source.productKey;
        connector.label = source.label;
        connector.aliases = source.aliases;
        connector.category = source.category;
        connector.configRecordName = source.configRecordName;
        connector.integrationType = source.integrationType;
        connector.activeField = source.activeField;
        connector.expiryField = source.expiryField;
        connector.editableFields = source.editableFields == null ? new List<String>() : new List<String>(source.editableFields);
        connector.displayOrder = source.sortOrder;
        connector.enabled = source.enabled;
        connector.hasConfig = source.hasConfig;
        connector.hasReporting = source.hasReporting;
        connector.hasMapping = source.hasMapping;
        connector.hasScheduler = source.hasScheduler;
        connector.hasCheckout = source.hasCheckout;
        connector.hasPayment = source.hasPayment;
        connector.hasCarrier = source.hasCarrier;
        connector.logoUrl = source.logoUrl;
        connector.catalogActive = source.catalogActive;
        connector.startDate = source.startDate;
        connector.endDate = source.endDate;
        connector.status = source.status;
        return connector;
    }
}