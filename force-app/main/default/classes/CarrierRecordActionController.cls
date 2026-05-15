public with sharing class CarrierRecordActionController {

    public class ActionPanelData {
        @AuraEnabled public String carrierType;
        @AuraEnabled public List<ActionItem> actions;
        public ActionPanelData() {
            actions = new List<ActionItem>();
        }
    }

    public class ActionItem {
        @AuraEnabled public String actionName;
        @AuraEnabled public String label;
        public ActionItem(String actionName, String label) {
            this.actionName = actionName;
            this.label = label;
        }
    }

    public class ActiveCarriersResult {
        @AuraEnabled public Boolean fedexActive;
        @AuraEnabled public Boolean upsActive;
        public ActiveCarriersResult() {
            fedexActive = false;
            upsActive = false;
        }
    }

    @AuraEnabled(cacheable=false)
    public static ActiveCarriersResult getActiveCarriers() {
        try {
            ActiveCarriersResult result = new ActiveCarriersResult();
            Quickbridge_Config__mdt fedexConfig = Quickbridge_Config__mdt.getInstance('FedEx');
            if (fedexConfig != null) {
                result.fedexActive = fedexConfig.FedEx_Active__c == true;
            }
            Quickbridge_Config__mdt upsConfig = Quickbridge_Config__mdt.getInstance('UPS');
            if (upsConfig != null) {
                result.upsActive = upsConfig.UPS_Active__c == true;
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static final Map<String, String> ACTION_LABELS = new Map<String, String>{
        'validateAddress'     => 'Validate Address',
        'getRateQuote'        => 'Get Rate Quote',
        'createShipment'      => 'Create Shipment',
        'syncTrackingStatus'  => 'Sync Tracking Status',
        'voidShipment'        => 'Void Shipment',
        'createReturnLabel'   => 'Create Return Label'
    };

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
            logControllerException('getActionsForObject', e, null, objectApiName, recordId, objectApiName, recordId, null);
            throw e;
        } catch (Exception e) {
            logControllerException('getActionsForObject', e, null, objectApiName, recordId, objectApiName, recordId, null);
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateCarrierType(Id recordId, String objectApiName, String carrierType) {
        try {
            String lower = String.isBlank(carrierType) ? '' : carrierType.toLowerCase().trim();
            if (lower != 'fedex' && lower != 'ups') {
                throw new AuraHandledException('Unsupported carrier type "' + carrierType + '". Supported values: FedEx, UPS.');
            }

            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }
            SObject record = sObjectType.newSObject(recordId);
            record.put('Carrier_Type__c', carrierType);
            update record;
        } catch (AuraHandledException e) {
            logControllerException('updateCarrierType', e, carrierType, objectApiName, recordId, objectApiName, recordId, null);
            throw e;
        } catch (Exception e) {
            logControllerException('updateCarrierType', e, carrierType, objectApiName, recordId, objectApiName, recordId, 'update');
            throw new AuraHandledException(e.getMessage());
        }
    }

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

            if (actionName == 'validateAddress') {
                return trackTaskAndReturn(carrierType, CarrierOperationsService.validateAddress(recordId, objectApiName, carrierType, false));
            }
            if (actionName == 'validateAddressAndUpdate') {
                return trackTaskAndReturn(carrierType, CarrierOperationsService.validateAddress(recordId, objectApiName, carrierType, true));
            }
            if (actionName == 'getRateQuote') {
                return trackTaskAndReturn(carrierType, CarrierOperationsService.getRateQuote(recordId, objectApiName, carrierType));
            }
            if (actionName == 'createShipment') {
                return trackTaskAndReturn(carrierType, CarrierOperationsService.createShipment(recordId, objectApiName, carrierType, false));
            }
            if (actionName == 'createShipmentWithLabel') {
                return trackTaskAndReturn(carrierType, CarrierOperationsService.createShipment(recordId, objectApiName, carrierType, true));
            }
            if (actionName == 'syncTrackingStatus') {
                Id shipmentId = resolveShipmentId(recordId, objectApiName, integration);
                return trackTaskAndReturn(carrierType, CarrierOperationsService.syncTrackingStatus(shipmentId, carrierType));
            }
            if (actionName == 'voidShipment') {
                Id shipmentId = resolveShipmentId(recordId, objectApiName, integration);
                return trackTaskAndReturn(carrierType, CarrierOperationsService.voidShipment(shipmentId, carrierType));
            }
            if (actionName == 'createReturnLabel') {
                Id shipmentId = resolveShipmentId(recordId, objectApiName, integration);
                return trackTaskAndReturn(carrierType, CarrierOperationsService.createReturnLabel(recordId, objectApiName, carrierType, shipmentId));
            }

            CarrierOperationsService.OperationResult result = new CarrierOperationsService.OperationResult();
            result.success = false;
            result.message = 'Unknown action: ' + actionName;
            return result;

        } catch (AuraHandledException e) {
            logControllerException('runAction', e, null, objectApiName, recordId, objectApiName, recordId, null);
            throw e;
        } catch (Exception e) {
            logControllerException('runAction', e, null, objectApiName, recordId, objectApiName, recordId, null);
            throw new AuraHandledException(e.getMessage());
        }
    }

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
            logControllerException('applyValidatedAddress', e, null, objectApiName, recordId, objectApiName, recordId, null);
            throw e;
        } catch (Exception e) {
            logControllerException('applyValidatedAddress', e, null, objectApiName, recordId, objectApiName, recordId, null);
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static CarrierOperationsService.OperationResult selectRateQuote(
        Id rateQuoteId,
        Id targetRecordId,
        String targetObjectApiName
    ) {
        try {
            return CarrierOperationsService.selectRateQuote(rateQuoteId, targetRecordId, targetObjectApiName);
        } catch (AuraHandledException e) {
            logControllerException('selectRateQuote', e, null, 'Carrier_Rate_Quote__c', rateQuoteId, targetObjectApiName, targetRecordId, null);
            throw e;
        } catch (Exception e) {
            logControllerException('selectRateQuote', e, null, 'Carrier_Rate_Quote__c', rateQuoteId, targetObjectApiName, targetRecordId, null);
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static String resolveCarrierType(Id recordId, String objectApiName) {
        String fieldName = 'Carrier_Type__c';
        String queryText = 'SELECT ' + fieldName + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
        SObject record;
        try {
            record = Database.query(queryText);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Object "' + objectApiName + '" does not have a Carrier_Type__c field. ' +
                'Add Carrier_Type__c (picklist: FedEx, UPS) to this object to enable carrier actions.'
            );
        }

        Object carrierTypeValue = record.get(fieldName);
        if (carrierTypeValue == null || String.isBlank(String.valueOf(carrierTypeValue))) {
            throw new AuraHandledException(
                'Carrier_Type__c is not set on this record. Please select FedEx or UPS before running carrier actions.'
            );
        }

        String carrierType = String.valueOf(carrierTypeValue);
        String lower = carrierType.toLowerCase().trim();
        if (lower != 'fedex' && lower != 'ups') {
            throw new AuraHandledException(
                'Unsupported carrier type "' + carrierType + '". Supported values: FedEx, UPS.'
            );
        }

        return carrierType;
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

    private static void logControllerException(
        String methodName,
        Exception exceptionRecord,
        String carrierType,
        String sourceObjectApiName,
        Id sourceRecordId,
        String actionSourceObjectApiName,
        Id actionSourceRecordId,
        String dmlOperation
    ) {
        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = String.isBlank(carrierType) ? 'Carrier' : carrierType;
        context.classMethodName = 'CarrierRecordActionController.' + methodName;
        context.errorMessage = exceptionRecord == null ? null : exceptionRecord.getTypeName() + ': ' + exceptionRecord.getMessage();
        context.stackTrace = exceptionRecord == null ? null : exceptionRecord.getStackTraceString();
        context.sourceObjectApiName = sourceObjectApiName;
        context.sourceRecordId = sourceRecordId;
        context.sourceRecordIdText = sourceRecordId == null ? null : String.valueOf(sourceRecordId);
        context.actionSourceObjectApiName = actionSourceObjectApiName;
        context.actionSourceRecordId = actionSourceRecordId;
        context.actionSourceRecordIdText = actionSourceRecordId == null ? null : String.valueOf(actionSourceRecordId);
        context.errorCategory = String.isBlank(dmlOperation) ? 'Code Exception' : 'DML Failure';
        context.dmlOperation = dmlOperation;
        ErrorLogUtility.logError(context);
    }
}