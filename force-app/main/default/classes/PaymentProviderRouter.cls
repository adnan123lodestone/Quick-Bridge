public with sharing class PaymentProviderRouter {
    public static PaymentProviderAdapter route(String connectorKey) {
        PaymentProviderAdapter adapter = adapterFor(connectorKey);
        if (adapter == null) {
            throw new AuraHandledException('Unsupported payment provider: ' + connectorKey);
        }
        return adapter;
    }

    public static PaymentProviderAdapter adapterFor(String connectorKey) {
        ConnectorRegistryService.ConnectorDescriptor connector = ConnectorRegistryService.byKey(connectorKey);
        if (connector == null) {
            return null;
        }
        String adapterClassName = ConnectorRegistryService.adapterClassFor(connector.connectorKey, 'payment.checkout');
        if (String.isBlank(adapterClassName)) {
            adapterClassName = ConnectorRegistryService.adapterClassFor(connector.connectorKey, 'payment.provider');
        }
        if (String.isBlank(adapterClassName)) {
            return null;
        }
        Type adapterType = Type.forName(adapterClassName);
        if (adapterType == null) {
            adapterType = Type.forName('QuickBridgeTLG', adapterClassName);
        }
        return adapterType == null ? null : (PaymentProviderAdapter)adapterType.newInstance();
    }
}
