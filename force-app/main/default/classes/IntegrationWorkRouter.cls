public with sharing class IntegrationWorkRouter {
    public static void process(Integration_Work_Item__c item) {
        if (item == null) {
            throw new IntegrationWorkRouteException('Work item is required.');
        }
        IntegrationWorkHandler handler = handlerFor(item.Integration__c, item.Operation__c);
        if (handler == null) {
            throw new IntegrationWorkRouteException('Unsupported integration operation: ' + item.Integration__c + '.' + item.Operation__c);
        }
        handler.handle(item);
    }

    public static String handlerClassFor(String integrationKey, String operationKey) {
        ConnectorRegistryService.ConnectorDescriptor connector = ConnectorRegistryService.byKey(integrationKey);
        String connectorKey = connector == null ? integrationKey : connector.connectorKey;
        String className = connector == null ? null : ConnectorRegistryService.adapterClassFor(connector.connectorKey, 'work.' + operationKey);
        if (String.isBlank(className)) {
            className = LegacyConnectorRegistryFallback.workHandlerClassFor(connectorKey, operationKey);
        }
        if (String.isBlank(className)) {
            ErrorLogUtility.logException(
                'QuickBridge',
                'IntegrationWorkRouter.handlerClassFor',
                new IntegrationWorkRouteException('No handler registered for: ' + integrationKey + '.' + operationKey),
                null,
                null
            );
        }
        return className;
    }

    private static IntegrationWorkHandler handlerFor(String integrationKey, String operationKey) {
        String className = handlerClassFor(integrationKey, operationKey);
        if (String.isBlank(className)) {
            return null;
        }
        ConnectorAdapterAllowlist.assertAllowed(className);
        Type handlerType = Type.forName(className);
        if (handlerType == null) {
            handlerType = Type.forName('QuickBridgeTLG', className);
        }
        return handlerType == null ? null : (IntegrationWorkHandler)handlerType.newInstance();
    }

    public class IntegrationWorkRouteException extends Exception {}
}