/**
 * @description LWC controller for the carrier record action panel.
 * Resolves the active carrier for a record, returns available actions,
 * and dispatches carrier operations (address validation, rate quotes, shipments, etc.).
 */
public with sharing class CarrierRecordActionController {

    /** @description Data returned to the LWC containing the resolved carrier type and available actions. */
    public class ActionPanelData {
        @AuraEnabled public String carrierType;
        @AuraEnabled public List<ActionItem> actions;
        public ActionPanelData() {
            actions = new List<ActionItem>();
        }
    }

    /** @description A single dispatchable carrier action with its display label. */
    public class ActionItem {
        @AuraEnabled public String actionName;
        @AuraEnabled public String label;
        public ActionItem(String actionName, String label) {
            this.actionName = actionName;
            this.label = label;
        }
    }

    /** @description Result wrapper returned by getActiveCarriers. */
    public class ActiveCarriersResult {
        @AuraEnabled public Map<String, Boolean> activeByCarrierKey;
        @AuraEnabled public List<CarrierOption> activeCarriers;
        public ActiveCarriersResult() {
            activeByCarrierKey = new Map<String, Boolean>();
            activeCarriers = new List<CarrierOption>();
        }
    }

    /** @description A single carrier option for LWC picklist display. */
    public class CarrierOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String connectorKey;

        public CarrierOption(String label, String value, String connectorKey) {
            this.label = label;
            this.value = value;
            this.connectorKey = connectorKey;
        }
    }

    /**
     * @description Returns all active carrier configurations and their entitlement status.
     * @return ActiveCarriersResult with a map of carrier keys to active flags and a list of active carrier options.
     */
    @AuraEnabled(cacheable=false)
    public static ActiveCarriersResult getActiveCarriers() {
        try {
            ActiveCarriersResult result = new ActiveCarriersResult();
            for (ConnectorRegistryService.ConnectorDescriptor descriptor : ConnectorRegistryService.byCapability('carrier.operation')) {
                ConnectorConfigService.ConnectorConfig config = ConnectorConfigService.getAuthoritativeConfig(descriptor.connectorKey);
                Boolean active = isEntitled(config);
                result.activeByCarrierKey.put(descriptor.connectorKey, active);
                if (active == true) {
                    String label = String.isBlank(descriptor.label) ? descriptor.connectorKey : descriptor.label;
                    result.activeCarriers.add(new CarrierOption(label, label, descriptor.connectorKey));
                }
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Boolean isEntitled(ConnectorConfigService.ConnectorConfig cfg) {
        if (cfg == null || cfg.active != true) return false;
        if (cfg.expiryDate != null && cfg.expiryDate < Date.today()) return false;
        return true;
    }

    private static final Map<String, String> ACTION_LABELS = new Map<String, String>{
        'validateAddress'     => 'Validate Address',
        'getRateQuote'        => 'Get Rate Quote',
        'createShipment'      => 'Create Shipment',
        'generateLabel'       => 'Generate Label',
        'syncTrackingStatus'  => 'Sync Tracking Status',
        'voidShipment'        => 'Void Shipment',
        'createReturnLabel'   => 'Create Return Label'
    };

    /**
     * @description Returns the resolved carrier type and list of available actions for a given record.
     * @param recordId Id of the record to inspect.
     * @param objectApiName API name of the SObject type.
     * @return ActionPanelData with the detected carrier and available carrier actions.
     */
    @AuraEnabled
    public static ActionPanelData getActionsForObject(Id recordId, String objectApiName) {
        try {
            ActionPanelData data = new ActionPanelData();

            String carrierType = null;
            try {
                carrierType = resolveCarrierType(recordId, objectApiName);
            } catch (Exception e) {
                // Carrier type not set yet — still return empty actions and null carrier
            }
            data.carrierType = carrierType;

            if (String.isBlank(carrierType)) {
                return data;
            }

            String integration = CarrierOperationsService.normalizeCarrier(carrierType);

            Set<String> actions = new Set<String>();
            List<Field_Mapping__mdt> mappings = [
                SELECT Action__c
                FROM Field_Mapping__mdt
                WHERE Integration__c = :integration
                AND SF_Object__c = :objectApiName
                AND Is_Active__c = true
                AND Action__c != null
            ];

            String legacyPrefix = integration + '_';
            List<Field_Mapping__mdt> legacyMappings = [
                SELECT Integration__c
                FROM Field_Mapping__mdt
                WHERE Integration__c LIKE :('%' + legacyPrefix + '%')
                AND SF_Object__c = :objectApiName
                AND Is_Active__c = true
            ];

            for (Field_Mapping__mdt m : mappings) {
                actions.add(m.Action__c);
            }
            for (Field_Mapping__mdt m : legacyMappings) {
                String actionPart = m.Integration__c.removeStart(legacyPrefix);
                if (String.isNotBlank(actionPart)) {
                    actions.add(actionPart);
                }
            }

            for (String actionName : ACTION_LABELS.keySet()) {
                if (actions.contains(actionName)) {
                    data.actions.add(new ActionItem(actionName, ACTION_LABELS.get(actionName)));
                }
            }

            return data;
        } catch (AuraHandledException e) {
            logControllerException('getActionsForObject', e, new ControllerLogContext(null, objectApiName, recordId, null));
            throw e;
        } catch (Exception e) {
            logControllerException('getActionsForObject', e, new ControllerLogContext(null, objectApiName, recordId, null));
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Writes the selected carrier type back to a record, enforcing field-level security.
     * @param recordId Id of the record to update.
     * @param objectApiName API name of the SObject type.
     * @param carrierType The carrier type value to write.
     */
    @AuraEnabled
    public static void updateCarrierType(Id recordId, String objectApiName, String carrierType) {
        try {
            String normalized = CarrierAdapterFactory.normalizeCarrierKey(carrierType);
            if (!CarrierAdapterFactory.supportedCarrierKeys().contains(normalized)) {
                throw new AuraHandledException('Unsupported carrier type "' + carrierType + '". Supported values: ' + String.join(CarrierAdapterFactory.supportedCarrierLabels(), ', ') + '.');
            }

            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }
            SObject record = sObjectType.newSObject(recordId);
            record.put('Carrier_Type__c', carrierType);
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, new List<SObject>{ record });
            update decision.getRecords()[0];
        } catch (AuraHandledException e) {
            logControllerException('updateCarrierType', e, new ControllerLogContext(carrierType, objectApiName, recordId, null));
            throw e;
        } catch (Exception e) {
            logControllerException('updateCarrierType', e, new ControllerLogContext(carrierType, objectApiName, recordId, 'update'));
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Dispatches a named carrier action for a record.
     * To add a new action, add a 'when' case to the switch block below.
     * Actions that require an existing shipment must call resolveShipmentId() first.
     * @param recordId Id of the source record.
     * @param objectApiName API name of the SObject type.
     * @param actionName The action key to execute (e.g. 'validateAddress', 'createShipment').
     * @return OperationResult containing success flag, message, and any carrier-specific data.
     */
    @AuraEnabled
    public static CarrierOperationsService.OperationResult runAction(
        Id recordId,
        String objectApiName,
        String actionName
    ) {
        try {
            String carrierType = resolveCarrierType(recordId, objectApiName);
            String integration = CarrierOperationsService.normalizeCarrier(carrierType);

            IntegrationUsageService.assertCanConsumeTask(carrierType, 1);

            switch on actionName {
                when 'validateAddress' {
                    return trackTaskAndReturn(carrierType, CarrierOperationsService.validateAddress(recordId, objectApiName, carrierType, false));
                }
                when 'validateAddressAndUpdate' {
                    return trackTaskAndReturn(carrierType, CarrierOperationsService.validateAddress(recordId, objectApiName, carrierType, true));
                }
                when 'getRateQuote' {
                    return trackTaskAndReturn(carrierType, CarrierOperationsService.getRateQuote(recordId, objectApiName, carrierType));
                }
                when 'createShipment' {
                    return trackTaskAndReturn(carrierType, CarrierOperationsService.createShipment(recordId, objectApiName, carrierType, false));
                }
                when 'createShipmentWithLabel', 'generateLabel' {
                    return trackTaskAndReturn(carrierType, CarrierOperationsService.createShipment(recordId, objectApiName, carrierType, true));
                }
                when 'syncTrackingStatus' {
                    Id shipmentId = resolveShipmentId(recordId, objectApiName, integration);
                    return trackTaskAndReturn(carrierType, CarrierOperationsService.syncTrackingStatus(shipmentId, carrierType));
                }
                when 'voidShipment' {
                    Id shipmentId = resolveShipmentId(recordId, objectApiName, integration);
                    return trackTaskAndReturn(carrierType, CarrierOperationsService.voidShipment(shipmentId, carrierType));
                }
                when 'createReturnLabel' {
                    Id shipmentId = resolveShipmentId(recordId, objectApiName, integration);
                    return trackTaskAndReturn(carrierType, CarrierOperationsService.createReturnLabel(recordId, objectApiName, carrierType, shipmentId));
                }
            }

            CarrierOperationsService.OperationResult result = new CarrierOperationsService.OperationResult();
            result.success = false;
            result.message = 'Unknown action: ' + actionName;
            return result;

        } catch (AuraHandledException e) {
            logControllerException('runAction', e, new ControllerLogContext(null, objectApiName, recordId, null));
            throw e;
        } catch (Exception e) {
            logControllerException('runAction', e, new ControllerLogContext(null, objectApiName, recordId, null));
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Applies a previously validated carrier address back to a Salesforce record.
     * @param recordId Id of the record to update.
     * @param objectApiName API name of the SObject type.
     * @param validatedAddress Address data returned by the carrier's address validation.
     * @return OperationResult indicating success and a summary message.
     */
    @AuraEnabled
    public static CarrierOperationsService.OperationResult applyValidatedAddress(
        Id recordId,
        String objectApiName,
        Map<String, Object> validatedAddress
    ) {
        try {
            String carrierType = resolveCarrierType(recordId, objectApiName);
            return CarrierOperationsService.applyValidatedAddress(recordId, objectApiName, carrierType, validatedAddress);
        } catch (AuraHandledException e) {
            logControllerException('applyValidatedAddress', e, new ControllerLogContext(null, objectApiName, recordId, null));
            throw e;
        } catch (Exception e) {
            logControllerException('applyValidatedAddress', e, new ControllerLogContext(null, objectApiName, recordId, null));
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Applies a selected rate quote to the target record using configured response mappings.
     * @param rateQuoteId Id of the Carrier_Rate_Quote__c record to apply.
     * @param targetRecordId Id of the record that will receive the rate data.
     * @param targetObjectApiName API name of the target SObject type.
     * @return OperationResult indicating success.
     */
    @AuraEnabled
    public static CarrierOperationsService.OperationResult selectRateQuote(
        Id rateQuoteId,
        Id targetRecordId,
        String targetObjectApiName
    ) {
        try {
            return CarrierOperationsService.selectRateQuote(rateQuoteId, targetRecordId, targetObjectApiName);
        } catch (AuraHandledException e) {
            ControllerLogContext ctx = new ControllerLogContext(null, 'Carrier_Rate_Quote__c', rateQuoteId, null);
            ctx.actionSourceObjectApiName = targetObjectApiName;
            ctx.actionSourceRecordId = targetRecordId;
            logControllerException('selectRateQuote', e, ctx);
            throw e;
        } catch (Exception e) {
            ControllerLogContext ctx = new ControllerLogContext(null, 'Carrier_Rate_Quote__c', rateQuoteId, null);
            ctx.actionSourceObjectApiName = targetObjectApiName;
            ctx.actionSourceRecordId = targetRecordId;
            logControllerException('selectRateQuote', e, ctx);
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static String resolveCarrierType(Id recordId, String objectApiName) {
        if (stripNamespace(objectApiName) == 'Carrier_Shipment__c') {
            Carrier_Shipment__c shipment = [
                SELECT Integration_Type__c
                FROM Carrier_Shipment__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (String.isBlank(shipment.Integration_Type__c)) {
                throw new AuraHandledException(
                    'Integration_Type__c is not set on this shipment. Please select a supported carrier before running carrier actions.'
                );
            }
            return shipment.Integration_Type__c;
        }

        String fieldName = 'Carrier_Type__c';
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        Map<String, Schema.SObjectField> fieldMap = sObjectType == null ? new Map<String, Schema.SObjectField>() : sObjectType.getDescribe().fields.getMap();
        String resolvedFieldName = fieldMap.containsKey(fieldName.toLowerCase())
            ? fieldName
            : (fieldMap.containsKey('quickbridgetlg__' + fieldName.toLowerCase()) ? 'QuickBridgeTLG__' + fieldName : null);
        if (sObjectType == null || resolvedFieldName == null) {
            throw new AuraHandledException(
                'Object "' + objectApiName + '" does not have a Carrier_Type__c field. ' +
                'Add Carrier_Type__c (picklist: ' + String.join(CarrierAdapterFactory.supportedCarrierLabels(), ', ') + ') to this object to enable carrier actions.'
            );
        }
        String queryText = 'SELECT ' + resolvedFieldName + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
        SObject record;
        try {
            record = Database.queryWithBinds(queryText, new Map<String, Object>{ 'recordId' => recordId }, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Object "' + objectApiName + '" does not have a Carrier_Type__c field. ' +
                'Add Carrier_Type__c (picklist: ' + String.join(CarrierAdapterFactory.supportedCarrierLabels(), ', ') + ') to this object to enable carrier actions.'
            );
        }

        Object carrierTypeValue = record.get(resolvedFieldName);
        if (carrierTypeValue == null || String.isBlank(String.valueOf(carrierTypeValue))) {
            throw new AuraHandledException(
                'Carrier_Type__c is not set on this record. Please select a supported carrier before running carrier actions.'
            );
        }

        String carrierType = String.valueOf(carrierTypeValue);
        String normalized = CarrierAdapterFactory.normalizeCarrierKey(carrierType);
        if (!CarrierAdapterFactory.supportedCarrierKeys().contains(normalized)) {
            throw new AuraHandledException(
                'Unsupported carrier type "' + carrierType + '". Supported values: ' + String.join(CarrierAdapterFactory.supportedCarrierLabels(), ', ') + '.'
            );
        }

        return carrierType;
    }

    private static String stripNamespace(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return objectApiName;
        }
        if (objectApiName.endsWith('__c') && objectApiName.indexOf('__') != objectApiName.lastIndexOf('__')) {
            return objectApiName.substringAfter('__');
        }
        return objectApiName;
    }

    private static Id resolveShipmentId(Id recordId, String objectApiName, String integration) {
        if (objectApiName == 'QuickBridgeTLG__Carrier_Shipment__c') {
            return recordId;
        }

        List<Carrier_Shipment__c> shipments = [
            SELECT Id
            FROM Carrier_Shipment__c
            WHERE Source_Record_Id__c = :String.valueOf(recordId)
            AND Source_Object__c = :objectApiName
            AND Integration_Type__c = :integration
            AND Is_Return__c = false
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (shipments.isEmpty()) {
            throw new AuraHandledException(
                'No ' + integration.capitalize() + ' shipment found for this record. ' +
                'Create a shipment first before performing this action.'
            );
        }

        return shipments[0].Id;
    }

    private static CarrierOperationsService.OperationResult trackTaskAndReturn(
        String carrierType,
        CarrierOperationsService.OperationResult result
    ) {
        if (result != null && result.success == true) {
            IntegrationUsageService.recordSuccessfulApiTask(carrierType);
        }
        return result;
    }

    private class ControllerLogContext {
        String carrierType;
        String sourceObjectApiName;
        Id sourceRecordId;
        String actionSourceObjectApiName;
        Id actionSourceRecordId;
        String dmlOperation;

        ControllerLogContext(String carrierType, String objectApiName, Id recordId, String dmlOperation) {
            this.carrierType = carrierType;
            this.sourceObjectApiName = objectApiName;
            this.sourceRecordId = recordId;
            this.actionSourceObjectApiName = objectApiName;
            this.actionSourceRecordId = recordId;
            this.dmlOperation = dmlOperation;
        }
    }

    private static void logControllerException(
        String methodName,
        Exception exceptionRecord,
        ControllerLogContext logCtx
    ) {
        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = logCtx == null || String.isBlank(logCtx.carrierType) ? 'Carrier' : logCtx.carrierType;
        context.classMethodName = 'CarrierRecordActionController.' + methodName;
        context.errorMessage = exceptionRecord == null ? null : exceptionRecord.getTypeName() + ': ' + exceptionRecord.getMessage();
        context.stackTrace = exceptionRecord == null ? null : exceptionRecord.getStackTraceString();
        context.sourceObjectApiName = logCtx == null ? null : logCtx.sourceObjectApiName;
        context.sourceRecordId = logCtx == null ? null : logCtx.sourceRecordId;
        context.sourceRecordIdText = logCtx == null || logCtx.sourceRecordId == null ? null : String.valueOf(logCtx.sourceRecordId);
        context.actionSourceObjectApiName = logCtx == null ? null : logCtx.actionSourceObjectApiName;
        context.actionSourceRecordId = logCtx == null ? null : logCtx.actionSourceRecordId;
        context.actionSourceRecordIdText = logCtx == null || logCtx.actionSourceRecordId == null ? null : String.valueOf(logCtx.actionSourceRecordId);
        context.errorCategory = logCtx == null || String.isBlank(logCtx.dmlOperation) ? 'Code Exception' : 'DML Failure';
        context.dmlOperation = logCtx == null ? null : logCtx.dmlOperation;
        ErrorLogUtility.logError(context);
    }
}