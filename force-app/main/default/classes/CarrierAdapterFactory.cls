public with sharing class CarrierAdapterFactory {
    @TestVisible private static Map<String, ICarrierAdapter> testAdapters;

    public static ICarrierAdapter getAdapter(String carrierType) {
        if (String.isBlank(carrierType)) {
            logAdapterFailure('Carrier type is required.');
            throw new AuraHandledException('Carrier type is required.');
        }
        String normalized = carrierType.toLowerCase().trim();
        if (Test.isRunningTest() && testAdapters != null && testAdapters.containsKey(normalized)) {
            return testAdapters.get(normalized);
        }
        if (normalized == 'fedex') {
            return new FedExCarrierAdapter();
        }
        if (normalized == 'ups') {
            return new UPSCarrierAdapter();
        }
        logAdapterFailure('Unsupported carrier type: ' + carrierType + '. Supported values: FedEx, UPS.');
        throw new AuraHandledException('Unsupported carrier type: ' + carrierType + '. Supported values: FedEx, UPS.');
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