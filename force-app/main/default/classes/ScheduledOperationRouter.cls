public with sharing class ScheduledOperationRouter {
    @TestVisible private static ScheduledOperationAdapter testAdapter;

    public static ScheduledOperationAdapter adapterFor(String connectorKey, String operationKey) {
        if (Test.isRunningTest() && testAdapter != null) {
            return testAdapter;
        }
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

    /**
     * Dispatches a scheduled operation while preserving the original adapter
     * contract. Legacy adapters execute synchronously from the scheduler's
     * perspective. Adapters that explicitly implement the deferred contract
     * transfer terminal schedule ownership to the async work they create.
     */
    public static ConnectorScheduleDispatchResult dispatch(
        Scheduled_Integration_Job__c job,
        String leaseToken
    ) {
        ScheduledOperationAdapter adapter = adapterFor(
            job.Integration_Type__c,
            job.Source_Object__c
        );
        if (adapter == null) {
            System.debug(
                LoggingLevel.WARN,
                'No scheduled operation adapter is registered for ' +
                job.Integration_Type__c +
                '.'
            );
            return ConnectorScheduleDispatchResult.failed(
                'No scheduled operation adapter is registered for ' +
                job.Integration_Type__c +
                '.'
            );
        }
        if (adapter instanceof DeferredScheduledOperationAdapter) {
            ConnectorScheduleDispatchResult result =
                ((DeferredScheduledOperationAdapter) adapter).dispatch(
                    job,
                    leaseToken
                );
            return result == null
                ? ConnectorScheduleDispatchResult.failed(
                    'The scheduled operation adapter returned no dispatch result.'
                )
                : result;
        }
        adapter.execute(job);
        return ConnectorScheduleDispatchResult.synchronous();
    }

    public static String integrationTypeToConnectorKey(String integrationType) {
        return ConnectorRegistryService.connectorKeyForIntegrationType(integrationType);
    }
}
