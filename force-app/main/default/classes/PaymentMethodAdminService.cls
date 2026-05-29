public with sharing class PaymentMethodAdminService {
    public class PaymentMethodAdminException extends Exception {}

    public class PaymentMethodState {
        public String apiName;
        public Boolean active;
    }

    public class DeactivateRequest {
        public String clientOrgName;
        public List<PaymentMethodState> paymentMethodStates;
    }

    public class DeactivateResponse {
        public Boolean success;
        public String message;
        public List<String> acceptedMethods;
        public List<String> unsupportedMethods;
        public String deploymentId;
    }

    public interface MetadataUpdater {
        String upsertProviderStates(Map<String, Boolean> providerStates);
    }

    @TestVisible
    private static MetadataUpdater testUpdater;

    private static final Map<String, String> PROVIDER_TO_METADATA_RECORD = paymentProviderMetadataRecords();
    private static final Map<String, String> PROVIDER_TO_LABEL = paymentProviderLabels();

    public static DeactivateResponse deactivatePaymentMethods(DeactivateRequest request) {
        try {
            QuickBridgeAdminGuard.requireManage();
            if (request == null || request.paymentMethodStates == null || request.paymentMethodStates.isEmpty()) {
                throw new PaymentMethodAdminException('At least one payment method state must be provided.');
            }

            List<String> unsupportedMethods = new List<String>();
            Map<String, Boolean> normalizedStates = normalizeProviderStates(
                request.paymentMethodStates,
                unsupportedMethods
            );

            if (normalizedStates.isEmpty()) {
                throw new PaymentMethodAdminException('No supported payment methods were provided.');
            }

            String deploymentId = getUpdater().upsertProviderStates(normalizedStates);

            List<String> acceptedMethods = new List<String>(normalizedStates.keySet());
            acceptedMethods.sort();
            unsupportedMethods.sort();

            DeactivateResponse response = new DeactivateResponse();
            response.success = true;
            response.message =
                'Accepted payment method sync request for ' +
                buildProviderStateList(acceptedMethods, normalizedStates) +
                (String.isBlank(request.clientOrgName) ? '.' : ' in ' + request.clientOrgName + '.');
            response.acceptedMethods = acceptedMethods;
            response.unsupportedMethods = unsupportedMethods;
            response.deploymentId = deploymentId;
            QuickBridgeAdminGuard.audit('PAYMENT_METHOD_SYNC', null, 'Queued', response.message, null);
            return response;
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBridge',
                'PaymentMethodAdminService.deactivatePaymentMethods',
                e,
                null,
                null
            );
            throw e;
        }
    }

    private static MetadataUpdater getUpdater() {
        return Test.isRunningTest() && testUpdater != null
            ? testUpdater
            : new MetadataApiUpdater();
    }

    private static Map<String, Boolean> normalizeProviderStates(
        List<PaymentMethodState> paymentMethodStates,
        List<String> unsupportedMethods
    ) {
        Map<String, Boolean> normalizedStates = new Map<String, Boolean>();
        for (PaymentMethodState paymentMethodState : paymentMethodStates) {
            String providerKey = paymentMethodState == null ? null : paymentMethodState.apiName;
            String normalizedKey = providerKey == null ? null : providerKey.trim().toLowerCase();
            if (String.isBlank(normalizedKey)) {
                continue;
            }

            if (PROVIDER_TO_METADATA_RECORD.containsKey(normalizedKey)) {
                normalizedStates.put(
                    normalizedKey,
                    paymentMethodState != null && paymentMethodState.active == true
                );
            } else {
                unsupportedMethods.add(providerKey.trim());
            }
        }
        return normalizedStates;
    }

    private static String buildProviderStateList(
        List<String> providerKeys,
        Map<String, Boolean> providerStates
    ) {
        List<String> providerLabels = new List<String>();
        for (String providerKey : providerKeys) {
            providerLabels.add(
                PROVIDER_TO_LABEL.get(providerKey) +
                ' (' + (providerStates.get(providerKey) ? 'active' : 'inactive') + ')'
            );
        }
        return String.join(providerLabels, ', ');
    }

    private class MetadataApiUpdater implements MetadataUpdater {
        public String upsertProviderStates(Map<String, Boolean> providerStates) {
            try {
                Metadata.DeployContainer container = new Metadata.DeployContainer();

                for (String providerKey : providerStates.keySet()) {
                    Metadata.CustomMetadata record = new Metadata.CustomMetadata();
                    record.fullName = PROVIDER_TO_METADATA_RECORD.get(providerKey);
                    record.label = 'Default';

                    Metadata.CustomMetadataValue activeValue = new Metadata.CustomMetadataValue();
                    activeValue.field = 'Active__c';
                    activeValue.value = providerStates.get(providerKey);
                    record.values.add(activeValue);

                    container.addMetadata(record);
                }

                Id deploymentId = Metadata.Operations.enqueueDeployment(
                    container,
                    new PaymentMethodAdminDeployCallback()
                );
                return deploymentId == null ? null : String.valueOf(deploymentId);
            } catch (Exception e) {
                ErrorLogUtility.logException(
                    'QuickBridge',
                    'PaymentMethodAdminService.MetadataApiUpdater.upsertProviderStates',
                    e,
                    null,
                    null
                );
                throw e;
            }
        }
    }

    private static Map<String, String> paymentProviderLabels() {
        Map<String, String> labels = new Map<String, String>();
        for (IntegrationConnectorRegistry.ConnectorDescriptor connector : IntegrationConnectorRegistry.paymentConnectors()) {
            if (PROVIDER_TO_METADATA_RECORD.containsKey(connector.connectorKey)) {
                labels.put(connector.connectorKey, connector.label);
            }
        }
        if (labels.isEmpty()) {
            labels.put('authorizenet', 'Authorize.Net');
            labels.put('stripe', 'Stripe');
            labels.put('paypal', 'PayPal');
        }
        return labels;
    }

    private static Map<String, String> paymentProviderMetadataRecords() {
        Map<String, String> records = new Map<String, String>();
        for (IntegrationConnectorRegistry.ConnectorDescriptor connector : IntegrationConnectorRegistry.paymentConnectors()) {
            if (String.isBlank(connector.connectorKey)) {
                continue;
            }
            String recordFullName = paymentAdminMetadataFullName(connector);
            if (String.isNotBlank(recordFullName)) {
                records.put(connector.connectorKey, recordFullName);
            }
        }
        if (records.isEmpty()) {
            records.put('authorizenet', 'AuthorizeNet_Config__mdt.Default');
            records.put('stripe', 'Stripe_Config__mdt.Default');
            records.put('paypal', 'PayPal_Config__mdt.Default');
        }
        return records;
    }

    private static String paymentAdminMetadataFullName(IntegrationConnectorRegistry.ConnectorDescriptor connector) {
        if (connector == null || String.isBlank(connector.configRecordName)) {
            return null;
        }
        if (connector.configRecordName.contains('__mdt.')) {
            return connector.configRecordName;
        }
        return connector.configRecordName + '_Config__mdt.Default';
    }
}