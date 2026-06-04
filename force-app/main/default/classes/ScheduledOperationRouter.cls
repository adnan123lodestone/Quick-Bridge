/**
 * @description Routes scheduled integration jobs to the appropriate ScheduledOperationAdapter.
 *
 * REGISTRATION CONTRACT — how to add a new scheduled integration:
 *   1. Deploy one Integration_Connector_Capability__mdt record with:
 *        - Connector_Key__c  = the connector's unique key (e.g. 'klaviyo')
 *        - Capability_Key__c = 'scheduler.operation'
 *        - Adapter_Class__c  = the unqualified class name of your ScheduledOperationAdapter implementation
 *        - Enabled__c        = true
 *   2. Ensure the adapter class is listed in ConnectorAdapterAllowlist.ALLOWED OR is covered by
 *      the metadata-driven secondary check in ConnectorAdapterAllowlist.assertAllowed().
 *   3. No changes to this router or GenericScheduleDispatcher are required.
 */
public with sharing class ScheduledOperationRouter {
    public static ScheduledOperationAdapter adapterFor(String connectorKey, String operationKey) {
        ConnectorRegistryService.ConnectorDescriptor connector = ConnectorRegistryService.byKey(connectorKey);
        if (connector == null) {
            connector = ConnectorRegistryService.byKey(integrationTypeToConnectorKey(connectorKey));
        }
        if (connector == null) {
            return null;
        }
        String adapterClassName = ConnectorRegistryService.adapterClassFor(connector.connectorKey, 'scheduler.operation');
        if (String.isBlank(adapterClassName)) {
            return null;
        }
        ConnectorAdapterAllowlist.assertAllowed(adapterClassName);
        Type adapterType = Type.forName(adapterClassName);
        if (adapterType == null) {
            adapterType = Type.forName('QuickBridgeTLG', adapterClassName);
        }
        return adapterType == null ? null : (ScheduledOperationAdapter)adapterType.newInstance();
    }

    public static void execute(Scheduled_Integration_Job__c job) {
        ScheduledOperationAdapter adapter = adapterFor(job.Integration_Type__c, job.Source_Object__c);
        if (adapter == null) {
            System.debug(LoggingLevel.WARN, 'No scheduled operation adapter is registered for ' + job.Integration_Type__c + '.');
            return;
        }
        adapter.execute(job);
    }

    public static String integrationTypeToConnectorKey(String integrationType) {
        return ConnectorRegistryService.connectorKeyForIntegrationType(integrationType);
    }
}