public with sharing class CarrierAdapterFactory {
    @TestVisible private static Map<String, ICarrierAdapter> testAdapters;

    public static ICarrierAdapter getAdapter(String carrierType) {
        if (String.isBlank(carrierType)) {
            logAdapterFailure('Carrier type is required.');
            throw new AuraHandledException('Carrier type is required.');
        }
        String normalized = normalizeCarrierKey(carrierType);
        if (Test.isRunningTest() && testAdapters != null && testAdapters.containsKey(normalized)) {
            return testAdapters.get(normalized);
        }

        String adapterClassName = ConnectorRegistryService.adapterClassFor(normalized, 'carrier.operation');
        if (String.isBlank(adapterClassName)) {
            logAdapterFailure('Unsupported carrier type: ' + carrierType + '. Supported values: ' + String.join(supportedCarrierLabels(), ', ') + '.');
            throw new AuraHandledException('Unsupported carrier type: ' + carrierType + '. Supported values: ' + String.join(supportedCarrierLabels(), ', ') + '.');
        }

        ConnectorAdapterAllowlist.assertAllowed(adapterClassName);
        Type adapterType = Type.forName(adapterClassName);
        if (adapterType == null) {
            adapterType = Type.forName('QuickBridgeTLG', adapterClassName);
        }
        if (adapterType == null) {
            logAdapterFailure('Carrier adapter class was not found: ' + adapterClassName);
            throw new AuraHandledException('Carrier adapter class was not found: ' + adapterClassName);
        }
        return (ICarrierAdapter) adapterType.newInstance();
    }

    public static String normalizeCarrierKey(String carrierType) {
        if (String.isBlank(carrierType)) return '';
        return carrierType.toLowerCase().trim();
    }

    public static Set<String> supportedCarrierKeys() {
        Set<String> keys = new Set<String>();
        for (ConnectorRegistryService.ConnectorDescriptor descriptor : ConnectorRegistryService.byCapability('carrier.operation')) {
            keys.add(descriptor.connectorKey);
        }
        return keys;
    }

    public static List<String> supportedCarrierLabels() {
        List<String> labels = new List<String>();
        for (ConnectorRegistryService.ConnectorDescriptor descriptor : ConnectorRegistryService.byCapability('carrier.operation')) {
            labels.add(String.isBlank(descriptor.label) ? descriptor.connectorKey : descriptor.label);
        }
        labels.sort();
        return labels;
    }

    private static void logAdapterFailure(String message) {
        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = 'Carrier';
        context.classMethodName = 'CarrierAdapterFactory.getAdapter';
        context.errorMessage = message;
        context.errorCategory = 'Configuration Error';
        ErrorLogUtility.logError(context);
    }
}
