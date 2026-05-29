public with sharing class CarrierAdapterFactory {
  @TestVisible
  private static Map<String, ICarrierAdapter> testAdapters;

  public static ICarrierAdapter getAdapter(String carrierType) {
    if (String.isBlank(carrierType)) {
      logAdapterFailure('Carrier type is required.');
      throw new AuraHandledException('Carrier type is required.');
    }
    String normalized = normalizeCarrierKey(carrierType);
    if (
      Test.isRunningTest() &&
      testAdapters != null &&
      testAdapters.containsKey(normalized)
    ) {
      return testAdapters.get(normalized);
    }

    ICarrierAdapter registeredAdapter = registeredAdapterFor(normalized);
    if (registeredAdapter != null) {
      return registeredAdapter;
    }

    if (supportedCarrierKeys().contains(normalized)) {
      logAdapterFailure(
        'No runtime adapter is registered for carrier type: ' +
          carrierType +
          '.'
      );
      throw new AuraHandledException(
        'No runtime adapter is registered for carrier type: ' +
          carrierType +
          '.'
      );
    }
    logAdapterFailure(
      'Unsupported carrier type: ' +
        carrierType +
        '. Supported values: ' +
        String.join(supportedCarrierLabels(), ', ') +
        '.'
    );
    throw new AuraHandledException(
      'Unsupported carrier type: ' +
        carrierType +
        '. Supported values: ' +
        String.join(supportedCarrierLabels(), ', ') +
        '.'
    );
  }

  public static String normalizeCarrierKey(String carrierType) {
    IntegrationConnectorRegistry.ConnectorDescriptor connector = IntegrationConnectorRegistry.byKey(
      carrierType
    );
    if (connector != null && connector.hasCarrier == true) {
      return connector.productKey;
    }
    return String.isBlank(carrierType) ? '' : carrierType.toLowerCase().trim();
  }

  public static Set<String> supportedCarrierKeys() {
    Set<String> keys = new Set<String>();
    for (
      IntegrationConnectorRegistry.ConnectorDescriptor connector : IntegrationConnectorRegistry.connectors()
    ) {
      if (
        connector.hasCarrier == true && String.isNotBlank(connector.productKey)
      ) {
        keys.add(connector.productKey);
      }
    }
    if (keys.isEmpty()) {
      keys.add('fedex');
      keys.add('ups');
    }
    return keys;
  }

  public static List<String> supportedCarrierLabels() {
    List<String> labels = new List<String>();
    for (
      IntegrationConnectorRegistry.ConnectorDescriptor connector : IntegrationConnectorRegistry.connectors()
    ) {
      if (connector.hasCarrier == true && String.isNotBlank(connector.label)) {
        labels.add(connector.label);
      }
    }
    if (labels.isEmpty()) {
      labels.add('FedEx');
      labels.add('UPS');
    }
    labels.sort();
    return labels;
  }

  private static ICarrierAdapter registeredAdapterFor(String carrierType) {
    IntegrationConnectorRegistry.ConnectorDescriptor connector = IntegrationConnectorRegistry.byKey(
      carrierType
    );
    String connectorKey = connector == null
      ? carrierType
      : connector.connectorKey;
    String adapterClassName = ConnectorRegistryService.adapterClassFor(
      connectorKey,
      'carrier.operation'
    );
    if (String.isBlank(adapterClassName)) {
      return null;
    }
    Type adapterType = Type.forName(adapterClassName);
    if (adapterType == null) {
      adapterType = Type.forName('QuickBridgeTLG', adapterClassName);
    }
    return adapterType == null
      ? null
      : (ICarrierAdapter) adapterType.newInstance();
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
