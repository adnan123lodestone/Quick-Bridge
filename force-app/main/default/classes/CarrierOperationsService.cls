public with sharing class CarrierOperationsService {

    public class OperationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id shipmentId;
        @AuraEnabled public Id fileId;
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public List<RateQuoteOption> rateQuotes;
        @AuraEnabled public Map<String, Object> correctedAddress;
        @AuraEnabled public String rawResponse;
        @AuraEnabled public String carrierType;
        public String actionName;
        public String sourceObjectApiName;
        public Id sourceRecordId;
        public String actionSourceObjectApiName;
        public Id actionSourceRecordId;
    }

    public class RateQuoteOption {
        @AuraEnabled public Id rateQuoteId;
        @AuraEnabled public String serviceType;
        @AuraEnabled public String serviceName;
        @AuraEnabled public Decimal totalNetCharge;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String transitTime;
        @AuraEnabled public String deliveryTimestamp;
        @AuraEnabled public String rawResponse;
    }

    public static OperationResult validateAddress(Id sourceRecordId, String sourceObjectApiName, String carrierType, Boolean updateSalesforce) {
        OperationResult result = newResult(carrierType);
        setLogContext(result, 'validateAddress', sourceObjectApiName, sourceRecordId, sourceObjectApiName, sourceRecordId);
        try {
            String integration = normalizeCarrier(carrierType);
            ICarrierAdapter adapter = CarrierAdapterFactory.getAdapter(integration);
            CarrierMappingService.MappingSet mappings = CarrierMappingService.load(integration, 'validateAddress', sourceObjectApiName);
            ensureRequestMappingsConfigured(mappings, 'validateAddress');
            if (updateSalesforce == true) {
                ensureResponseMappingsConfigured(mappings, 'validateAddress');
            }
            SObject sourceRecord = CarrierMappingService.queryMappedRecord(sourceRecordId, mappings, CarrierMappingService.DIRECTION_TO_CARRIER);
            Map<String, Object> mappedPayload = CarrierMappingService.buildRequestPayload(sourceRecord, mappings);

            Map<String, Object> responseValues = adapter.validateAddress(mappedPayload);
            result.correctedAddress = (Map<String, Object>) responseValues.get('validatedAddress');
            result.rawResponse = String.valueOf(responseValues.get('rawResponse'));
            result.success = true;
            result.message = 'Address validation completed.';

            if (updateSalesforce == true) {
                CarrierMappingService.applyResponseMappings(sourceRecordId, mappings, responseValues);
                result.message = 'Address validation completed and Salesforce was updated.';
            }
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    public static OperationResult applyValidatedAddress(Id sourceRecordId, String sourceObjectApiName, String carrierType, Map<String, Object> validatedAddress) {
        OperationResult result = newResult(carrierType);
        setLogContext(result, 'applyValidatedAddress', sourceObjectApiName, sourceRecordId, sourceObjectApiName, sourceRecordId);
        try {
            String integration = normalizeCarrier(carrierType);
            CarrierMappingService.MappingSet mappings = CarrierMappingService.load(integration, 'validateAddress', sourceObjectApiName);
            if (mappings.responseMappings.isEmpty()) {
                result.success = true;
                result.message = 'Address validated but no Carrier→SF field mappings are configured for validateAddress. Configure response mappings in Quickbridge settings to write fields back automatically.';
                return result;
            }
            Map<String, Object> responseValues = new Map<String, Object>{ 'validatedAddress' => validatedAddress };
            CarrierMappingService.applyResponseMappings(sourceRecordId, mappings, responseValues);
            result.success = true;
            result.message = 'Validated address applied to record.';
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    public static OperationResult getRateQuote(Id sourceRecordId, String sourceObjectApiName, String carrierType) {
        OperationResult result = newResult(carrierType);
        setLogContext(result, 'getRateQuote', sourceObjectApiName, sourceRecordId, sourceObjectApiName, sourceRecordId);
        try {
            String integration = normalizeCarrier(carrierType);
            ICarrierAdapter adapter = CarrierAdapterFactory.getAdapter(integration);
            CarrierMappingService.MappingSet mappings = CarrierMappingService.load(integration, 'getRateQuote', sourceObjectApiName);
            ensureRequestMappingsConfigured(mappings, 'getRateQuote');
            SObject sourceRecord = CarrierMappingService.queryMappedRecord(sourceRecordId, mappings, CarrierMappingService.DIRECTION_TO_CARRIER);
            Map<String, Object> mappedPayload = CarrierMappingService.buildRequestPayload(sourceRecord, mappings);

            Map<String, Object> adapterResult = adapter.getRateQuote(mappedPayload);
            List<RateQuoteOption> options = extractRateOptions(adapterResult, integration);
            persistRateOptions(sourceRecordId, null, options, integration);

            result.success = true;
            result.message = options.isEmpty() ? 'No rate options returned.' : 'Rate options returned.';
            result.rateQuotes = options;
            result.rawResponse = String.valueOf(adapterResult.get('rawResponse'));
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    public static OperationResult selectRateQuote(Id rateQuoteId, Id targetRecordId, String targetObjectApiName) {
        OperationResult result = newResult(null);
        setLogContext(result, 'selectRateQuote', 'Carrier_Rate_Quote__c', rateQuoteId, targetObjectApiName, targetRecordId);
        try {
            Carrier_Rate_Quote__c selectedQuote = [
                SELECT Id, Service_Type__c, Service_Name__c, Total_Net_Charge__c, Currency__c,
                       Transit_Time__c, Delivery_Timestamp__c, Rate_Response__c, Shipment__c,
                       Integration_Type__c, Source_Record_Id__c
                FROM Carrier_Rate_Quote__c
                WHERE Id = :rateQuoteId
                LIMIT 1
            ];

            result.carrierType = selectedQuote.Integration_Type__c;

            update new Carrier_Rate_Quote__c(Id = selectedQuote.Id, Is_Selected__c = true);
            if (selectedQuote.Shipment__c != null) {
                for (Carrier_Rate_Quote__c quote : [
                    SELECT Id
                    FROM Carrier_Rate_Quote__c
                    WHERE Shipment__c = :selectedQuote.Shipment__c AND Id != :selectedQuote.Id AND Is_Selected__c = true
                ]) {
                    update new Carrier_Rate_Quote__c(Id = quote.Id, Is_Selected__c = false);
                }
            } else if (String.isNotBlank(selectedQuote.Source_Record_Id__c)) {
                for (Carrier_Rate_Quote__c quote : [
                    SELECT Id
                    FROM Carrier_Rate_Quote__c
                    WHERE Source_Record_Id__c = :selectedQuote.Source_Record_Id__c
                    AND Shipment__c = null
                    AND Id != :selectedQuote.Id
                    AND Is_Selected__c = true
                ]) {
                    update new Carrier_Rate_Quote__c(Id = quote.Id, Is_Selected__c = false);
                }
            }

            if (targetRecordId != null && String.isNotBlank(targetObjectApiName)) {
                String integration = normalizeCarrier(selectedQuote.Integration_Type__c);
                Map<String, Object> responseValues = new Map<String, Object>{
                    'selectedRate' => new Map<String, Object>{
                        'serviceType' => selectedQuote.Service_Type__c,
                        'serviceName' => selectedQuote.Service_Name__c,
                        'totalNetCharge' => selectedQuote.Total_Net_Charge__c,
                        'currency' => selectedQuote.Currency__c,
                        'transitTime' => selectedQuote.Transit_Time__c,
                        'deliveryTimestamp' => selectedQuote.Delivery_Timestamp__c
                    }
                };
                CarrierMappingService.applyResponseMappings(
                    targetRecordId,
                    CarrierMappingService.load(integration, 'getRateQuote', targetObjectApiName),
                    responseValues
                );
            }

            result.success = true;
            result.message = 'Selected rate saved.';
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    public static OperationResult createShipment(Id sourceRecordId, String sourceObjectApiName, String carrierType, Boolean generateLabel) {
        OperationResult result = newResult(carrierType);
        setLogContext(result, 'createShipment', sourceObjectApiName, sourceRecordId, sourceObjectApiName, sourceRecordId);
        try {
            String integration = normalizeCarrier(carrierType);
            ICarrierAdapter adapter = CarrierAdapterFactory.getAdapter(integration);

            // Load mappings and build payload before any DML so the callout is first
            CarrierMappingService.MappingSet mappings = CarrierMappingService.load(integration, 'createShipment', sourceObjectApiName);
            ensureRequestMappingsConfigured(mappings, 'createShipment');
            SObject sourceRecord = CarrierMappingService.queryMappedRecord(sourceRecordId, mappings, CarrierMappingService.DIRECTION_TO_CARRIER);
            Map<String, Object> mappedPayload = CarrierMappingService.buildRequestPayload(sourceRecord, mappings);

            // Callout first — no DML before this point
            Map<String, Object> adapterResult = adapter.createShipment(mappedPayload, generateLabel == true);

            // All DML after the callout
            Id shipmentId = ensureShipment(sourceRecordId, sourceObjectApiName, integration, false, null);
            Id fileId = saveLabelIfPresent(shipmentId, adapterResult, integration.capitalize() + ' Label');
            if (fileId != null) {
                CarrierMappingService.putPath(adapterResult, 'label.contentDocumentId', fileId);
            }

            applyShipmentCoreUpdate(shipmentId, adapterResult, false, integration);
            persistPackageTracking(shipmentId, adapterResult, integration);
            CarrierMappingService.applyResponseMappings(sourceRecordId, mappings, adapterResult);

            result.success = true;
            result.message = integration.capitalize() + ' shipment created.';
            result.shipmentId = shipmentId;
            result.fileId = fileId;
            result.trackingNumber = stringValue(CarrierMappingService.getPath(adapterResult, 'shipment.masterTrackingNumber'));
            result.rawResponse = stringValue(adapterResult.get('rawResponse'));
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    public static OperationResult generateLabel(Id shipmentId, String carrierType) {
        OperationResult result = newResult(carrierType);
        setLogContext(result, 'generateLabel', 'Carrier_Shipment__c', shipmentId, 'Carrier_Shipment__c', shipmentId);
        try {
            String integration = normalizeCarrier(carrierType);
            ICarrierAdapter adapter = CarrierAdapterFactory.getAdapter(integration);
            Carrier_Shipment__c shipment = [
                SELECT Id, Master_Tracking_Number__c, External_Shipment_Id__c, Label_Content_Document_Id__c
                FROM Carrier_Shipment__c
                WHERE Id = :shipmentId
                LIMIT 1
            ];

            if (String.isNotBlank(shipment.Label_Content_Document_Id__c)) {
                result.success = true;
                result.message = integration.capitalize() + ' label already exists.';
                result.shipmentId = shipmentId;
                result.fileId = (Id) shipment.Label_Content_Document_Id__c;
                result.trackingNumber = shipment.Master_Tracking_Number__c;
                return result;
            }

            CarrierMappingService.MappingSet mappings = CarrierMappingService.load(integration, 'generateLabel', 'Carrier_Shipment__c');
            ensureRequestMappingsConfigured(mappings, 'generateLabel');
            SObject shipmentRecord = CarrierMappingService.queryMappedRecord(shipmentId, mappings, CarrierMappingService.DIRECTION_TO_CARRIER);
            Map<String, Object> mappedPayload = CarrierMappingService.buildRequestPayload(shipmentRecord, mappings);

            Map<String, Object> adapterResult = adapter.generateLabel(
                shipment.Master_Tracking_Number__c,
                shipment.External_Shipment_Id__c,
                mappedPayload
            );
            Id fileId = saveLabelIfPresent(shipmentId, adapterResult, integration.capitalize() + ' Label');
            if (fileId != null) {
                CarrierMappingService.putPath(adapterResult, 'label.contentDocumentId', fileId);
                update new Carrier_Shipment__c(
                    Id = shipmentId,
                    Label_Content_Document_Id__c = String.valueOf(fileId),
                    Raw_Response__c = abbreviate(stringValue(adapterResult.get('rawResponse')), 32768)
                );
            }

            CarrierMappingService.applyResponseMappings(shipmentId, mappings, adapterResult);

            result.success = true;
            result.message = integration.capitalize() + ' label generated.';
            result.shipmentId = shipmentId;
            result.fileId = fileId;
            result.trackingNumber = stringValue(CarrierMappingService.getPath(adapterResult, 'shipment.masterTrackingNumber'));
            result.rawResponse = stringValue(adapterResult.get('rawResponse'));
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    public static OperationResult createReturnLabel(Id sourceRecordId, String sourceObjectApiName, String carrierType, Id originalShipmentId) {
        OperationResult result = newResult(carrierType);
        setLogContext(result, 'createReturnLabel', sourceObjectApiName, sourceRecordId, 'Carrier_Shipment__c', originalShipmentId);
        try {
            String integration = normalizeCarrier(carrierType);
            ICarrierAdapter adapter = CarrierAdapterFactory.getAdapter(integration);

            // Load mappings and build payload before any DML so the callout is first
            CarrierMappingService.MappingSet mappings = CarrierMappingService.load(integration, 'createReturnLabel', sourceObjectApiName);
            ensureRequestMappingsConfigured(mappings, 'createReturnLabel');
            SObject sourceRecord = CarrierMappingService.queryMappedRecord(sourceRecordId, mappings, CarrierMappingService.DIRECTION_TO_CARRIER);
            Map<String, Object> mappedPayload = CarrierMappingService.buildRequestPayload(sourceRecord, mappings);

            // Callout first — no DML before this point
            Map<String, Object> adapterResult = adapter.createReturnLabel(mappedPayload);

            // All DML after the callout
            Id returnShipmentId = ensureShipment(sourceRecordId, sourceObjectApiName, integration, true, originalShipmentId);
            Id fileId = saveLabelIfPresent(returnShipmentId, adapterResult, integration.capitalize() + ' Return Label');
            if (fileId != null) {
                CarrierMappingService.putPath(adapterResult, 'returnShipment.labelContentDocumentId', fileId);
            }

            applyShipmentCoreUpdate(returnShipmentId, adapterResult, true, integration);
            CarrierMappingService.applyResponseMappings(sourceRecordId, mappings, adapterResult);

            result.success = true;
            result.message = integration.capitalize() + ' return label created.';
            result.shipmentId = returnShipmentId;
            result.fileId = fileId;
            result.trackingNumber = stringValue(CarrierMappingService.getPath(adapterResult, 'returnShipment.trackingNumber'));
            result.rawResponse = stringValue(adapterResult.get('rawResponse'));
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    public static OperationResult syncTrackingStatus(Id shipmentId, String carrierType) {
        OperationResult result = newResult(carrierType);
        setLogContext(result, 'syncTrackingStatus', 'Carrier_Shipment__c', shipmentId, 'Carrier_Shipment__c', shipmentId);
        try {
            String integration = normalizeCarrier(carrierType);
            ICarrierAdapter adapter = CarrierAdapterFactory.getAdapter(integration);

            Carrier_Shipment__c shipment = [
                SELECT Id, Master_Tracking_Number__c, Is_Terminal__c
                FROM Carrier_Shipment__c
                WHERE Id = :shipmentId
                LIMIT 1
            ];

            if (shipment.Is_Terminal__c) {
                result.success = true;
                result.message = 'Shipment is terminal. Tracking sync skipped.';
                result.shipmentId = shipmentId;
                return result;
            }
            if (String.isBlank(shipment.Master_Tracking_Number__c)) {
                throw new AuraHandledException('A tracking number is required before syncing status.');
            }

            Map<String, Object> adapterResult = adapter.syncTrackingStatus(shipment.Master_Tracking_Number__c);
            upsertTrackingEvents(shipmentId, adapterResult, integration);
            updateShipmentTrackingStatus(shipmentId, adapterResult, integration);
            handleDeliveryException(shipmentId, adapterResult, integration);

            CarrierMappingService.applyResponseMappings(
                shipmentId,
                CarrierMappingService.load(integration, 'syncTrackingStatus', 'Carrier_Shipment__c'),
                adapterResult
            );

            result.success = true;
            result.message = integration.capitalize() + ' tracking status synced.';
            result.shipmentId = shipmentId;
            result.trackingNumber = shipment.Master_Tracking_Number__c;
            result.rawResponse = stringValue(adapterResult.get('rawResponse'));
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    public static OperationResult voidShipment(Id shipmentId, String carrierType) {
        OperationResult result = newResult(carrierType);
        setLogContext(result, 'voidShipment', 'Carrier_Shipment__c', shipmentId, 'Carrier_Shipment__c', shipmentId);
        try {
            String integration = normalizeCarrier(carrierType);
            ICarrierAdapter adapter = CarrierAdapterFactory.getAdapter(integration);

            Carrier_Shipment__c shipment = [
                SELECT Id, Master_Tracking_Number__c, External_Shipment_Id__c, Is_Terminal__c, Shipment_Status__c
                FROM Carrier_Shipment__c
                WHERE Id = :shipmentId
                LIMIT 1
            ];

            if (shipment.Is_Terminal__c || shipment.Shipment_Status__c == 'Delivered') {
                throw new AuraHandledException('Delivered or terminal shipments cannot be voided.');
            }
            if (String.isBlank(shipment.Master_Tracking_Number__c) && String.isBlank(shipment.External_Shipment_Id__c)) {
                throw new AuraHandledException('A tracking number or shipment identifier is required to void a shipment.');
            }

            Map<String, Object> adapterResult = adapter.voidShipment(shipment.Master_Tracking_Number__c, shipment.External_Shipment_Id__c);

            update new Carrier_Shipment__c(
                Id = shipmentId,
                Shipment_Status__c = 'Voided',
                Is_Terminal__c = true
            );
            CarrierMappingService.applyResponseMappings(
                shipmentId,
                CarrierMappingService.load(integration, 'voidShipment', 'Carrier_Shipment__c'),
                adapterResult
            );

            result.success = true;
            result.message = integration.capitalize() + ' shipment voided.';
            result.shipmentId = shipmentId;
            result.trackingNumber = shipment.Master_Tracking_Number__c;
            result.rawResponse = stringValue(adapterResult.get('rawResponse'));
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    private static Id ensureShipment(Id sourceRecordId, String sourceObjectApiName, String integration, Boolean isReturn, Id originalShipmentId) {
        if (sourceObjectApiName == 'Carrier_Shipment__c' && isReturn != true) {
            return sourceRecordId;
        }

        String sourceIdStr = sourceRecordId == null ? null : String.valueOf(sourceRecordId);
        Id linkedOriginalShipmentId = originalShipmentId;
        if (sourceObjectApiName == 'Carrier_Shipment__c' && isReturn == true && linkedOriginalShipmentId == null) {
            linkedOriginalShipmentId = sourceRecordId;
        }

        List<Carrier_Shipment__c> existing = [
            SELECT Id, Master_Tracking_Number__c, Shipment_Status__c
            FROM Carrier_Shipment__c
            WHERE Source_Record_Id__c = :sourceIdStr
            AND Integration_Type__c = :integration
            AND Is_Return__c = :isReturn
            AND Original_Shipment__c = :linkedOriginalShipmentId
            LIMIT 1
        ];
        if (!existing.isEmpty() && String.isBlank(existing[0].Master_Tracking_Number__c)) {
            return existing[0].Id;
        }

        Carrier_Shipment__c shipment = new Carrier_Shipment__c(
            Name = (isReturn ? 'Return ' : '') + integration.capitalize() + ' Shipment',
            Source_Record_Id__c = sourceIdStr,
            Source_Object__c = sourceObjectApiName,
            Integration_Type__c = integration,
            Is_Return__c = isReturn,
            Original_Shipment__c = linkedOriginalShipmentId,
            Shipment_Status__c = 'Draft'
        );
        insert shipment;
        return shipment.Id;
    }

    private static void applyShipmentCoreUpdate(Id shipmentId, Map<String, Object> adapterResult, Boolean isReturn, String integration) {
        Object shipmentValuesObject = isReturn
            ? adapterResult.get('returnShipment')
            : adapterResult.get('shipment');
        if (!(shipmentValuesObject instanceof Map<String, Object>)) {
            return;
        }
        Map<String, Object> shipmentValues = (Map<String, Object>) shipmentValuesObject;

        Carrier_Shipment__c toUpdate = new Carrier_Shipment__c(
            Id = shipmentId,
            External_Shipment_Id__c = stringValue(shipmentValues.get('externalShipmentId')),
            Master_Tracking_Number__c = isReturn
                ? stringValue(shipmentValues.get('trackingNumber'))
                : stringValue(shipmentValues.get('masterTrackingNumber')),
            Shipment_Status__c = stringValue(shipmentValues.get('status')),
            Total_Net_Charge__c = decimalValue(shipmentValues.get('totalNetCharge')),
            Service_Type__c = stringValue(shipmentValues.get('serviceType')),
            Raw_Response__c = abbreviate(stringValue(adapterResult.get('rawResponse')), 32768)
        );
        String labelDocId = stringValue(
            CarrierMappingService.getPath(adapterResult, isReturn ? 'returnShipment.labelContentDocumentId' : 'label.contentDocumentId')
        );
        if (String.isNotBlank(labelDocId)) {
            toUpdate.Label_Content_Document_Id__c = labelDocId;
        }
        update toUpdate;
    }

    private static void persistPackageTracking(Id shipmentId, Map<String, Object> adapterResult, String integration) {
        String trackingNumber = stringValue(CarrierMappingService.getPath(adapterResult, 'package.trackingNumber'));
        if (String.isBlank(trackingNumber)) {
            return;
        }
        insert new Carrier_Package__c(
            Name = 'Package ' + trackingNumber,
            Shipment__c = shipmentId,
            Integration_Type__c = integration,
            Tracking_Number__c = trackingNumber,
            Package_Status__c = 'Created'
        );
    }

    private static List<RateQuoteOption> extractRateOptions(Map<String, Object> adapterResult, String integration) {
        List<RateQuoteOption> options = new List<RateQuoteOption>();
        Object rateDetailsObject = adapterResult.get('rateDetails');
        if (!(rateDetailsObject instanceof List<Object>)) {
            return options;
        }

        for (Object detailObject : (List<Object>) rateDetailsObject) {
            if (!(detailObject instanceof Map<String, Object>)) continue;
            Map<String, Object> detail = (Map<String, Object>) detailObject;
            RateQuoteOption option = new RateQuoteOption();

            if (integration == 'fedex') {
                option.serviceType = stringValue(detail.get('serviceType'));
                option.serviceName = stringValue(detail.get('serviceName'));
                option.transitTime = stringValue(CarrierMappingService.getPath(detail, 'commit.transitTime'));

                Object ratedShipmentDetails = detail.get('ratedShipmentDetails');
                if (ratedShipmentDetails instanceof List<Object> && !((List<Object>) ratedShipmentDetails).isEmpty()) {
                    Map<String, Object> firstRated = (Map<String, Object>) ((List<Object>) ratedShipmentDetails)[0];
                    Object shipmentRateDetail = firstRated.get('shipmentRateDetail');
                    if (shipmentRateDetail instanceof Map<String, Object>) {
                        option.totalNetCharge = decimalValue(CarrierMappingService.getPath((Map<String, Object>) shipmentRateDetail, 'totalNetCharge.amount'));
                        option.currencyCode = stringValue(CarrierMappingService.getPath((Map<String, Object>) shipmentRateDetail, 'totalNetCharge.currency'));
                    }
                    if (option.totalNetCharge == null) {
                        option.totalNetCharge = decimalValue(firstRated.get('totalNetCharge'));
                        option.currencyCode = stringValue(firstRated.get('currency'));
                    }
                }
            } else if (integration == 'ups') {
                option.serviceType = stringValue(CarrierMappingService.getPath(detail, 'Service.Code'));
                option.serviceName = 'UPS Service ' + option.serviceType;
                option.totalNetCharge = decimalValue(CarrierMappingService.getPath(detail, 'TotalCharges.MonetaryValue'));
                option.currencyCode = stringValue(CarrierMappingService.getPath(detail, 'TotalCharges.CurrencyCode'));
                option.transitTime = stringValue(CarrierMappingService.getPath(detail, 'TimeInTransit.ServiceSummary.EstimatedArrival.BusinessDaysInTransit'));
            }

            option.rawResponse = JSON.serialize(detail);
            if (option.serviceType != null) {
                options.add(option);
            }
        }
        return options;
    }

    private static void persistRateOptions(Id sourceRecordId, Id shipmentId, List<RateQuoteOption> options, String integration) {
        List<Carrier_Rate_Quote__c> records = new List<Carrier_Rate_Quote__c>();
        for (RateQuoteOption option : options) {
            records.add(new Carrier_Rate_Quote__c(
                Name = String.isBlank(option.serviceName) ? option.serviceType : option.serviceName,
                Integration_Type__c = integration,
                Source_Record_Id__c = sourceRecordId == null ? null : String.valueOf(sourceRecordId),
                Shipment__c = shipmentId,
                Service_Type__c = option.serviceType,
                Service_Name__c = option.serviceName,
                Total_Net_Charge__c = option.totalNetCharge,
                Currency__c = option.currencyCode,
                Transit_Time__c = option.transitTime,
                Delivery_Timestamp__c = parseDatetime(option.deliveryTimestamp),
                Rate_Response__c = abbreviate(option.rawResponse, 32768)
            ));
        }
        if (!records.isEmpty()) {
            insert records;
            for (Integer i = 0; i < records.size(); i++) {
                options[i].rateQuoteId = records[i].Id;
            }
        }
    }

    private static void upsertTrackingEvents(Id shipmentId, Map<String, Object> adapterResult, String integration) {
        Map<String, Object> tracking = (Map<String, Object>) adapterResult.get('tracking');
        String trackingNumber = tracking == null ? null : stringValue(tracking.get('trackingNumber'));
        Object eventsObject = adapterResult.get('events');
        if (!(eventsObject instanceof List<Object>)) {
            return;
        }

        List<Carrier_Tracking_Event__c> events = new List<Carrier_Tracking_Event__c>();
        for (Object eventObject : (List<Object>) eventsObject) {
            if (!(eventObject instanceof Map<String, Object>)) continue;
            Map<String, Object> eventMap = (Map<String, Object>) eventObject;
            String eventCode = stringValue(eventMap.get('eventCode'));
            String timestampValue = stringValue(eventMap.get('timestamp'));
            String dedupeKey = integration + '|' + trackingNumber + '|' + eventCode + '|' + timestampValue;
            events.add(new Carrier_Tracking_Event__c(
                Shipment__c = shipmentId,
                Integration_Type__c = integration,
                Tracking_Number__c = trackingNumber,
                Event_Type__c = stringValue(eventMap.get('eventType')),
                Event_Code__c = eventCode,
                Event_Description__c = stringValue(eventMap.get('description')),
                Event_Timestamp__c = parseDatetime(timestampValue),
                Deduplication_Key__c = dedupeKey
            ));
        }
        if (!events.isEmpty()) {
            upsert events Deduplication_Key__c;
        }
    }

    private static void updateShipmentTrackingStatus(Id shipmentId, Map<String, Object> adapterResult, String integration) {
        Map<String, Object> tracking = (Map<String, Object>) adapterResult.get('tracking');
        String statusCode = tracking == null ? null : stringValue(tracking.get('statusCode'));
        String statusLabel = tracking == null ? null : stringValue(tracking.get('latestStatus'));
        Boolean isTerminal = false;

        if (String.isNotBlank(statusCode)) {
            List<Carrier_Status_Mapping__c> mappings = [
                SELECT Status_Label__c, Is_Terminal__c
                FROM Carrier_Status_Mapping__c
                WHERE Status_Code__c = :statusCode
                AND Integration_Type__c = :integration
                LIMIT 1
            ];
            if (!mappings.isEmpty()) {
                statusLabel = String.isBlank(mappings[0].Status_Label__c) ? statusLabel : mappings[0].Status_Label__c;
                isTerminal = mappings[0].Is_Terminal__c;
            }
        }

        update new Carrier_Shipment__c(
            Id = shipmentId,
            Latest_Status__c = statusLabel,
            Shipment_Status__c = statusLabel,
            Is_Terminal__c = isTerminal
        );
        if (tracking != null) {
            tracking.put('isTerminal', isTerminal);
        }
    }

    private static void handleDeliveryException(Id shipmentId, Map<String, Object> adapterResult, String integration) {
        Map<String, Object> tracking = (Map<String, Object>) adapterResult.get('tracking');
        String statusCode = tracking == null ? null : stringValue(tracking.get('statusCode'));
        String statusDescription = tracking == null ? null : stringValue(tracking.get('statusDescription'));
        if (String.isBlank(statusCode)) {
            return;
        }

        List<Carrier_Status_Mapping__c> statusMappings = [
            SELECT Is_Exception__c
            FROM Carrier_Status_Mapping__c
            WHERE Status_Code__c = :statusCode
            AND Integration_Type__c = :integration
            LIMIT 1
        ];
        if (statusMappings.isEmpty() || !statusMappings[0].Is_Exception__c) {
            return;
        }

        update new Carrier_Shipment__c(
            Id = shipmentId,
            Exception_Reason__c = statusDescription,
            Exception_Timestamp__c = Datetime.now()
        );

        List<Carrier_Exception_Rule__c> rules = [
            SELECT Action__c, Priority__c, Notification_Target__c
            FROM Carrier_Exception_Rule__c
            WHERE Active__c = true
            AND Status_Code__c = :statusCode
            AND Integration_Type__c = :integration
            LIMIT 1
        ];
        if (rules.isEmpty()) {
            return;
        }

        Carrier_Exception_Rule__c rule = rules[0];
        String carrier = integration.capitalize();
        if (rule.Action__c == 'Task') {
            insert new Task(
                WhatId = shipmentId,
                Subject = carrier + ' delivery exception',
                Priority = String.isBlank(rule.Priority__c) ? 'Normal' : rule.Priority__c,
                Status = 'Not Started',
                Description = statusDescription
            );
        } else if (rule.Action__c == 'Case') {
            insert new Case(
                Subject = carrier + ' delivery exception',
                Origin = carrier,
                Status = 'New',
                Priority = String.isBlank(rule.Priority__c) ? 'Medium' : rule.Priority__c,
                Description = statusDescription
            );
        }
    }

    private static Id saveLabelIfPresent(Id parentId, Map<String, Object> adapterResult, String titlePrefix) {
        String encodedLabel = stringValue(CarrierMappingService.getPath(adapterResult, 'label.encodedLabel'));
        if (String.isBlank(encodedLabel)) {
            encodedLabel = stringValue(CarrierMappingService.getPath(adapterResult, 'returnShipment.encodedLabel'));
        }
        if (String.isBlank(encodedLabel)) {
            return null;
        }

        ContentVersion contentVersion = new ContentVersion(
            Title = titlePrefix + ' - ' + Datetime.now().format('yyyyMMddHHmmss'),
            PathOnClient = titlePrefix.replace(' ', '') + getLabelExtension(adapterResult),
            VersionData = EncodingUtil.base64Decode(encodedLabel),
            Origin = 'H'
        );
        insert contentVersion;

        contentVersion = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id LIMIT 1];
        insert new ContentDocumentLink(
            ContentDocumentId = contentVersion.ContentDocumentId,
            LinkedEntityId = parentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        return contentVersion.ContentDocumentId;
    }

    private static String getLabelExtension(Map<String, Object> adapterResult) {
        String imageType = stringValue(CarrierMappingService.getPath(adapterResult, 'label.imageType'));
        if (String.isBlank(imageType)) {
            imageType = stringValue(CarrierMappingService.getPath(adapterResult, 'returnShipment.imageType'));
        }
        if (String.isNotBlank(imageType)) {
            String normalized = imageType.toLowerCase();
            if (normalized.contains('pdf')) return '.pdf';
            if (normalized.contains('gif')) return '.gif';
            if (normalized.contains('png')) return '.png';
            if (normalized.contains('zpl')) return '.zpl';
            if (normalized.contains('epl')) return '.epl';
        }
        // imageType from carrier response (e.g. FedEx 'LABEL', 'LABEL_STOCK') is not a
        // file format — fall back to PDF since that is what labelSpecification always requests
        return '.pdf';
    }

    public static String normalizeCarrier(String carrierType) {
        if (String.isBlank(carrierType)) {
            throw new AuraHandledException('Carrier type is required.');
        }
        String normalized = carrierType.toLowerCase().trim();
        if (normalized == 'fedex' || normalized == 'ups') {
            return normalized;
        }
        throw new AuraHandledException('Unsupported carrier type: ' + carrierType);
    }

    private static OperationResult newResult(String carrierType) {
        OperationResult result = new OperationResult();
        result.success = false;
        result.rateQuotes = new List<RateQuoteOption>();
        result.carrierType = carrierType;
        return result;
    }

    private static void setLogContext(
        OperationResult result,
        String actionName,
        String sourceObjectApiName,
        Id sourceRecordId,
        String actionSourceObjectApiName,
        Id actionSourceRecordId
    ) {
        if (result == null) {
            return;
        }
        result.actionName = actionName;
        result.sourceObjectApiName = sourceObjectApiName;
        result.sourceRecordId = sourceRecordId;
        result.actionSourceObjectApiName = actionSourceObjectApiName;
        result.actionSourceRecordId = actionSourceRecordId;
    }

    private static void ensureRequestMappingsConfigured(CarrierMappingService.MappingSet mappings, String actionName) {
        if (mappings == null || mappings.requestMappings.isEmpty()) {
            throw new AuraHandledException(
                'No active field mappings were found for carrier action "' + actionName + '". ' +
                'Save the "' + actionName + '" mappings for this Salesforce object in the carrier mapping screen, then try again.'
            );
        }
    }

    private static void ensureResponseMappingsConfigured(CarrierMappingService.MappingSet mappings, String actionName) {
        if (mappings == null || mappings.responseMappings.isEmpty()) {
            throw new AuraHandledException(
                'No active Carrier to SF mappings were found for carrier action "' + actionName + '". ' +
                'Add the reverse mappings before using the update/apply flow.'
            );
        }
    }

    private static void applyError(OperationResult result, Exception e) {
        result.success = false;
        result.message = e.getMessage();
        ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
        context.gatewayName = String.isBlank(result.carrierType) ? 'Carrier' : result.carrierType;
        context.classMethodName = 'CarrierOperationsService.' + (String.isBlank(result.actionName) ? 'unknown' : result.actionName);
        context.errorMessage = e == null ? null : e.getTypeName() + ': ' + e.getMessage();
        context.stackTrace = e == null ? null : e.getStackTraceString();
        context.sourceObjectApiName = result.sourceObjectApiName;
        context.sourceRecordId = result.sourceRecordId;
        context.sourceRecordIdText = result.sourceRecordId == null ? null : String.valueOf(result.sourceRecordId);
        context.actionSourceObjectApiName = result.actionSourceObjectApiName;
        context.actionSourceRecordId = result.actionSourceRecordId;
        context.actionSourceRecordIdText = result.actionSourceRecordId == null ? null : String.valueOf(result.actionSourceRecordId);
        context.errorCategory = getErrorCategory(e);
        context.dmlOperation = context.errorCategory == 'DML Failure' ? 'unknown' : null;
        ErrorLogUtility.logError(context);
    }

    private static String getErrorCategory(Exception e) {
        if (e == null) {
            return 'Carrier Error';
        }
        String typeName = e.getTypeName();
        if (typeName != null && typeName.contains('DmlException')) {
            return 'DML Failure';
        }
        if (typeName != null && (typeName.contains('CalloutException') || typeName.contains('Callout'))) {
            return 'Callout Failure';
        }
        return 'Code Exception';
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal decimalValue(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) return null;
        if (value instanceof Decimal) return (Decimal) value;
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static Datetime parseDatetime(String value) {
        if (String.isBlank(value)) return null;
        try {
            if (value.contains('T')) {
                return Datetime.valueOfGmt(value.replace('T', ' ').replace('Z', ''));
            }
            return Datetime.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    private static String abbreviate(String value, Integer maxLength) {
        if (String.isBlank(value) || value.length() <= maxLength) return value;
        return value.substring(0, maxLength);
    }
}