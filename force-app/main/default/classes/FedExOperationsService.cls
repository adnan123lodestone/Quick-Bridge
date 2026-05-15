public with sharing class FedExOperationsService {
    private static final String ACTION_VALIDATE_ADDRESS = 'validateAddress';
    private static final String ACTION_GET_RATE_QUOTE = 'getRateQuote';
    private static final String ACTION_CREATE_SHIPMENT = 'createShipment';
    private static final String ACTION_GENERATE_LABEL = 'generateLabel';
    private static final String ACTION_SYNC_TRACKING_STATUS = 'syncTrackingStatus';
    private static final String ACTION_CREATE_RETURN_LABEL = 'createReturnLabel';
    private static final String ACTION_VOID_SHIPMENT = 'voidShipment';

    public class OperationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id shipmentId;
        @AuraEnabled public Id fileId;
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public List<RateQuoteOption> rateQuotes;
        @AuraEnabled public Map<String, Object> correctedAddress;
        @AuraEnabled public String rawResponse;
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

    @AuraEnabled
    public static OperationResult validateAddress(Id sourceRecordId, String sourceObjectApiName, Boolean updateSalesforce) {
        OperationResult result = newResult();
        try {
            FedExMappingService.MappingSet mappings = FedExMappingService.load(ACTION_VALIDATE_ADDRESS, sourceObjectApiName);
            SObject sourceRecord = FedExMappingService.queryMappedRecord(sourceRecordId, mappings, FedExMappingService.DIRECTION_TO_FEDEX);
            Map<String, Object> mappedPayload = FedExMappingService.buildRequestPayload(sourceRecord, mappings);
            Map<String, Object> requestBody = new Map<String, Object>{
                'addressesToValidate' => new List<Object>{
                    new Map<String, Object>{ 'address' => normalizeAddressPayload(mappedPayload) }
                }
            };

            HttpResponse response = sendFedEx('POST', '/address/v1/addresses/resolve', requestBody);
            Map<String, Object> responseBody = parseBody(response);
            requireSuccess(response, responseBody, 'FedEx address validation failed.');

            Map<String, Object> responseValues = normalizeAddressValidationResponse(responseBody);
            result.correctedAddress = (Map<String, Object>) responseValues.get('validatedAddress');
            result.rawResponse = response.getBody();
            result.success = true;
            result.message = 'Address validation completed.';

            if (updateSalesforce == true) {
                FedExMappingService.applyResponseMappings(sourceRecordId, mappings, responseValues);
                result.message = 'Address validation completed and Salesforce was updated.';
            }
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    @AuraEnabled
    public static OperationResult getRateQuote(Id sourceRecordId, String sourceObjectApiName) {
        OperationResult result = newResult();
        try {
            FedExMappingService.MappingSet mappings = FedExMappingService.load(ACTION_GET_RATE_QUOTE, sourceObjectApiName);
            SObject sourceRecord = FedExMappingService.queryMappedRecord(sourceRecordId, mappings, FedExMappingService.DIRECTION_TO_FEDEX);
            Map<String, Object> mappedPayload = FedExMappingService.buildRequestPayload(sourceRecord, mappings);
            Map<String, Object> requestBody = buildShipmentRequest(mappedPayload, false);

            HttpResponse response = sendFedEx('POST', '/rate/v1/rates/quotes', requestBody);
            Map<String, Object> responseBody = parseBody(response);
            requireSuccess(response, responseBody, 'FedEx rate quote failed.');

            List<RateQuoteOption> options = extractRateOptions(responseBody);
            persistRateOptions(sourceRecordId, null, options);

            result.success = true;
            result.message = options.isEmpty() ? 'No FedEx rate options were returned.' : 'FedEx rate options returned.';
            result.rateQuotes = options;
            result.rawResponse = response.getBody();
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    @AuraEnabled
    public static OperationResult selectRateQuote(Id rateQuoteId, Id targetRecordId, String targetObjectApiName) {
        OperationResult result = newResult();
        try {
            FedEx_Rate_Quote__c selectedQuote = [
                SELECT Id, Service_Type__c, Service_Name__c, Total_Net_Charge__c, Currency__c,
                       Transit_Time__c, Delivery_Timestamp__c, Rate_Response__c, Shipment__c
                FROM FedEx_Rate_Quote__c
                WHERE Id = :rateQuoteId
                LIMIT 1
            ];

            if (selectedQuote.Shipment__c != null) {
                update new FedEx_Rate_Quote__c(Id = selectedQuote.Id, Is_Selected__c = true);
                for (FedEx_Rate_Quote__c quote : [
                    SELECT Id
                    FROM FedEx_Rate_Quote__c
                    WHERE Shipment__c = :selectedQuote.Shipment__c AND Id != :selectedQuote.Id AND Is_Selected__c = true
                ]) {
                    quote.Is_Selected__c = false;
                    update quote;
                }
            }

            if (targetRecordId != null && String.isNotBlank(targetObjectApiName)) {
                Map<String, Object> responseValues = normalizeSelectedRate(selectedQuote);
                FedExMappingService.applyResponseMappings(
                    targetRecordId,
                    FedExMappingService.load(ACTION_GET_RATE_QUOTE, targetObjectApiName),
                    responseValues
                );
            }

            result.success = true;
            result.message = 'Selected FedEx rate saved.';
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    @AuraEnabled
    public static OperationResult createShipment(Id sourceRecordId, String sourceObjectApiName, Boolean generateLabel) {
        OperationResult result = newResult();
        try {
            Id shipmentId = ensureShipment(sourceRecordId, sourceObjectApiName, false, null);
            FedExMappingService.MappingSet mappings = FedExMappingService.load(ACTION_CREATE_SHIPMENT, sourceObjectApiName);
            SObject sourceRecord = FedExMappingService.queryMappedRecord(sourceRecordId, mappings, FedExMappingService.DIRECTION_TO_FEDEX);
            Map<String, Object> mappedPayload = FedExMappingService.buildRequestPayload(sourceRecord, mappings);
            Map<String, Object> requestBody = buildShipmentRequest(mappedPayload, generateLabel == true);

            HttpResponse response = sendFedEx('POST', '/ship/v1/shipments', requestBody);
            Map<String, Object> responseBody = parseBody(response);
            requireSuccess(response, responseBody, 'FedEx shipment creation failed.');

            Map<String, Object> responseValues = normalizeShipmentResponse(responseBody);
            Id fileId = saveLabelIfPresent(shipmentId, responseValues, 'FedEx Label');
            if (fileId != null) {
                putNested(responseValues, 'label.contentDocumentId', fileId);
            }

            applyShipmentCoreUpdate(shipmentId, responseValues, false);
            persistPackageTracking(shipmentId, responseValues);
            FedExMappingService.applyResponseMappings(sourceRecordId, mappings, responseValues);

            result.success = true;
            result.message = 'FedEx shipment created.';
            result.shipmentId = shipmentId;
            result.fileId = fileId;
            result.trackingNumber = stringValue(FedExMappingService.getPath(responseValues, 'shipment.masterTrackingNumber'));
            result.rawResponse = response.getBody();
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    @AuraEnabled
    public static OperationResult generateLabel(Id shipmentId) {
        OperationResult result = newResult();
        try {
            SObject shipmentRecord = queryRecordForMappings(shipmentId, 'FedEx_Shipment__c', ACTION_GENERATE_LABEL);
            FedExMappingService.MappingSet mappings = FedExMappingService.load(ACTION_GENERATE_LABEL, 'FedEx_Shipment__c');
            Map<String, Object> mappedPayload = FedExMappingService.buildRequestPayload(shipmentRecord, mappings);
            Map<String, Object> requestBody = buildShipmentRequest(mappedPayload, true);

            HttpResponse response = sendFedEx('POST', '/ship/v1/shipments', requestBody);
            Map<String, Object> responseBody = parseBody(response);
            requireSuccess(response, responseBody, 'FedEx label generation failed.');

            Map<String, Object> responseValues = normalizeShipmentResponse(responseBody);
            Id fileId = saveLabelIfPresent(shipmentId, responseValues, 'FedEx Label');
            if (fileId != null) {
                putNested(responseValues, 'label.contentDocumentId', fileId);
            }

            applyShipmentCoreUpdate(shipmentId, responseValues, false);
            FedExMappingService.applyResponseMappings(shipmentId, mappings, responseValues);

            result.success = true;
            result.message = 'FedEx label generated.';
            result.shipmentId = shipmentId;
            result.fileId = fileId;
            result.trackingNumber = stringValue(FedExMappingService.getPath(responseValues, 'shipment.masterTrackingNumber'));
            result.rawResponse = response.getBody();
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    @AuraEnabled
    public static OperationResult createReturnLabel(Id sourceRecordId, String sourceObjectApiName, Id originalShipmentId) {
        OperationResult result = newResult();
        try {
            Id returnShipmentId = ensureShipment(sourceRecordId, sourceObjectApiName, true, originalShipmentId);
            FedExMappingService.MappingSet mappings = FedExMappingService.load(ACTION_CREATE_RETURN_LABEL, sourceObjectApiName);
            SObject sourceRecord = FedExMappingService.queryMappedRecord(sourceRecordId, mappings, FedExMappingService.DIRECTION_TO_FEDEX);
            Map<String, Object> mappedPayload = FedExMappingService.buildRequestPayload(sourceRecord, mappings);
            Map<String, Object> requestBody = buildShipmentRequest(mappedPayload, true);
            putNested(requestBody, 'requestedShipment.returnShipmentDetail.returnType', 'PRINT_RETURN_LABEL');

            HttpResponse response = sendFedEx('POST', '/ship/v1/shipments', requestBody);
            Map<String, Object> responseBody = parseBody(response);
            requireSuccess(response, responseBody, 'FedEx return label creation failed.');

            Map<String, Object> responseValues = normalizeReturnShipmentResponse(responseBody);
            Id fileId = saveLabelIfPresent(returnShipmentId, responseValues, 'FedEx Return Label');
            if (fileId != null) {
                putNested(responseValues, 'returnShipment.labelContentDocumentId', fileId);
            }

            applyShipmentCoreUpdate(returnShipmentId, responseValues, true);
            FedExMappingService.applyResponseMappings(sourceRecordId, mappings, responseValues);

            result.success = true;
            result.message = 'FedEx return label created.';
            result.shipmentId = returnShipmentId;
            result.fileId = fileId;
            result.trackingNumber = stringValue(FedExMappingService.getPath(responseValues, 'returnShipment.trackingNumber'));
            result.rawResponse = response.getBody();
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    @AuraEnabled
    public static OperationResult syncTrackingStatus(Id shipmentId) {
        OperationResult result = newResult();
        try {
            FedEx_Shipment__c shipment = [
                SELECT Id, Master_Tracking_Number__c, Is_Terminal__c
                FROM FedEx_Shipment__c
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

            Map<String, Object> requestBody = new Map<String, Object>{
                'trackingInfo' => new List<Object>{
                    new Map<String, Object>{
                        'trackingNumberInfo' => new Map<String, Object>{
                            'trackingNumber' => shipment.Master_Tracking_Number__c
                        }
                    }
                },
                'includeDetailedScans' => true
            };

            HttpResponse response = sendFedEx('POST', '/track/v1/trackingnumbers', requestBody);
            Map<String, Object> responseBody = parseBody(response);
            requireSuccess(response, responseBody, 'FedEx tracking sync failed.');

            Map<String, Object> responseValues = normalizeTrackingResponse(responseBody, shipment.Master_Tracking_Number__c);
            upsertTrackingEvents(shipmentId, responseValues);
            updateShipmentTrackingStatus(shipmentId, responseValues);
            handleDeliveryException(shipmentId, responseValues);

            FedExMappingService.applyResponseMappings(
                shipmentId,
                FedExMappingService.load(ACTION_SYNC_TRACKING_STATUS, 'FedEx_Shipment__c'),
                responseValues
            );

            result.success = true;
            result.message = 'FedEx tracking status synced.';
            result.shipmentId = shipmentId;
            result.trackingNumber = shipment.Master_Tracking_Number__c;
            result.rawResponse = response.getBody();
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    @AuraEnabled
    public static OperationResult voidShipment(Id shipmentId) {
        OperationResult result = newResult();
        try {
            FedEx_Shipment__c shipment = [
                SELECT Id, Master_Tracking_Number__c, FedEx_Shipment_Id__c, Is_Terminal__c, Shipment_Status__c
                FROM FedEx_Shipment__c
                WHERE Id = :shipmentId
                LIMIT 1
            ];
            if (shipment.Is_Terminal__c || shipment.Shipment_Status__c == 'Delivered') {
                throw new AuraHandledException('Delivered or terminal shipments cannot be voided.');
            }
            if (String.isBlank(shipment.Master_Tracking_Number__c) && String.isBlank(shipment.FedEx_Shipment_Id__c)) {
                throw new AuraHandledException('A tracking number or FedEx shipment identifier is required to void a shipment.');
            }

            Map<String, Object> requestBody = new Map<String, Object>{
                'accountNumber' => new Map<String, Object>{ 'value' => getAccountNumber() },
                'trackingNumber' => shipment.Master_Tracking_Number__c,
                'deletionControl' => 'DELETE_ALL_PACKAGES'
            };

            HttpResponse response = sendFedEx('PUT', '/ship/v1/shipments/cancel', requestBody);
            Map<String, Object> responseBody = parseBody(response);
            requireSuccess(response, responseBody, 'FedEx void shipment failed.');

            Map<String, Object> responseValues = normalizeVoidResponse(responseBody);
            update new FedEx_Shipment__c(
                Id = shipmentId,
                Shipment_Status__c = 'Voided',
                Is_Terminal__c = true
            );
            FedExMappingService.applyResponseMappings(
                shipmentId,
                FedExMappingService.load(ACTION_VOID_SHIPMENT, 'FedEx_Shipment__c'),
                responseValues
            );

            result.success = true;
            result.message = 'FedEx shipment voided.';
            result.shipmentId = shipmentId;
            result.trackingNumber = shipment.Master_Tracking_Number__c;
            result.rawResponse = response.getBody();
        } catch (Exception e) {
            applyError(result, e);
        }
        return result;
    }

    private static HttpResponse sendFedEx(String method, String path, Map<String, Object> body) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(FedExAuthService.getBaseUrl() + path);
        request.setMethod(method);
        request.setTimeout(60000);
        request.setHeader('Authorization', 'Bearer ' + FedExAuthService.getAccessToken());
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        if (body != null && method != 'GET') {
            request.setBody(JSON.serialize(body));
        }
        return new Http().send(request);
    }

    private static Map<String, Object> buildShipmentRequest(Map<String, Object> mappedPayload, Boolean includeLabel) {
        FedExAuthService.FedExCredentialConfig config = FedExAuthService.getCredentialConfig();
        Map<String, Object> requestedShipment = new Map<String, Object>();
        requestedShipment.putAll(mappedPayload == null ? new Map<String, Object>() : mappedPayload);

        if (requestedShipment.containsKey('shipment') && requestedShipment.get('shipment') instanceof Map<String, Object>) {
            Map<String, Object> shipmentDetails = (Map<String, Object>) requestedShipment.remove('shipment');
            requestedShipment.putAll(shipmentDetails);
        }

        defaultIfBlank(requestedShipment, 'serviceType', String.isBlank(config.defaultServiceType) ? 'FEDEX_GROUND' : config.defaultServiceType);
        defaultIfBlank(requestedShipment, 'packagingType', String.isBlank(config.defaultPackagingType) ? 'YOUR_PACKAGING' : config.defaultPackagingType);
        defaultIfBlank(requestedShipment, 'pickupType', String.isBlank(config.defaultPickupType) ? 'USE_SCHEDULED_PICKUP' : config.defaultPickupType);
        defaultIfBlank(requestedShipment, 'shipDatestamp', String.valueOf(Date.today()));

        if (!requestedShipment.containsKey('requestedPackageLineItems')) {
            Map<String, Object> packageInfo = requestedShipment.containsKey('package') && requestedShipment.get('package') instanceof Map<String, Object>
                ? (Map<String, Object>) requestedShipment.remove('package')
                : new Map<String, Object>();
            if (!packageInfo.containsKey('weight')) {
                packageInfo.put('weight', new Map<String, Object>{ 'units' => 'LB', 'value' => 1 });
            }
            requestedShipment.put('requestedPackageLineItems', new List<Object>{ packageInfo });
        }

        if (includeLabel == true) {
            requestedShipment.put('labelSpecification', new Map<String, Object>{
                'imageType' => 'PDF',
                'labelStockType' => 'PAPER_85X11_TOP_HALF_LABEL'
            });
        }

        return new Map<String, Object>{
            'labelResponseOptions' => includeLabel == true ? 'LABEL' : 'URL_ONLY',
            'accountNumber' => new Map<String, Object>{ 'value' => config.accountNumber },
            'requestedShipment' => requestedShipment
        };
    }

    private static Map<String, Object> normalizeAddressPayload(Map<String, Object> mappedPayload) {
        if (mappedPayload != null && mappedPayload.get('address') instanceof Map<String, Object>) {
            return (Map<String, Object>) mappedPayload.get('address');
        }
        return mappedPayload == null ? new Map<String, Object>() : mappedPayload;
    }

    private static Map<String, Object> normalizeAddressValidationResponse(Map<String, Object> responseBody) {
        Map<String, Object> result = new Map<String, Object>();
        Object resolvedAddress = FedExMappingService.getPath(responseBody, 'output.resolvedAddresses.0');
        Map<String, Object> resolved = resolvedAddress instanceof Map<String, Object>
            ? (Map<String, Object>) resolvedAddress
            : new Map<String, Object>();
        Object address = resolved.get('streetLines') != null ? resolved : resolved.get('address');
        result.put('validatedAddress', address instanceof Map<String, Object> ? address : resolved);
        result.put('addressClassification', resolved.get('classification'));
        result.put('residential', resolved.get('residential'));
        return result;
    }

    private static List<RateQuoteOption> extractRateOptions(Map<String, Object> responseBody) {
        List<RateQuoteOption> options = new List<RateQuoteOption>();
        Object rateDetailsObject = FedExMappingService.getPath(responseBody, 'output.rateReplyDetails');
        if (!(rateDetailsObject instanceof List<Object>)) {
            return options;
        }

        for (Object detailObject : (List<Object>) rateDetailsObject) {
            if (!(detailObject instanceof Map<String, Object>)) continue;
            Map<String, Object> detail = (Map<String, Object>) detailObject;
            Map<String, Object> normalized = normalizeRateResponse(detail);
            RateQuoteOption option = new RateQuoteOption();
            option.serviceType = stringValue(normalized.get('serviceType'));
            option.serviceName = stringValue(normalized.get('serviceName'));
            option.totalNetCharge = decimalValue(normalized.get('totalNetCharge'));
            option.currencyCode = stringValue(normalized.get('currency'));
            option.transitTime = stringValue(normalized.get('transitTime'));
            option.deliveryTimestamp = stringValue(normalized.get('deliveryTimestamp'));
            option.rawResponse = JSON.serialize(detail);
            options.add(option);
        }
        return options;
    }

    private static void persistRateOptions(Id sourceRecordId, Id shipmentId, List<RateQuoteOption> options) {
        List<FedEx_Rate_Quote__c> records = new List<FedEx_Rate_Quote__c>();
        for (RateQuoteOption option : options) {
            records.add(new FedEx_Rate_Quote__c(
                Name = String.isBlank(option.serviceName) ? option.serviceType : option.serviceName,
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

    private static Map<String, Object> normalizeRateResponse(Map<String, Object> detail) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('serviceType', detail.get('serviceType'));
        result.put('serviceName', detail.get('serviceName'));
        result.put('transitTime', detail.get('commit') instanceof Map<String, Object> ? ((Map<String, Object>) detail.get('commit')).get('transitTime') : detail.get('transitTime'));
        result.put('deliveryTimestamp', FedExMappingService.getPath(detail, 'commit.dateDetail.dayOfWeek'));

        Object ratedShipmentDetails = detail.get('ratedShipmentDetails');
        if (ratedShipmentDetails instanceof List<Object> && !((List<Object>) ratedShipmentDetails).isEmpty()) {
            Map<String, Object> firstRated = (Map<String, Object>) ((List<Object>) ratedShipmentDetails)[0];
            result.put('totalNetCharge', FedExMappingService.getPath(firstRated, 'totalNetCharge'));
            result.put('totalBaseCharge', FedExMappingService.getPath(firstRated, 'totalBaseCharge'));
            result.put('currency', FedExMappingService.getPath(firstRated, 'currency'));
            Object shipmentRateDetail = firstRated.get('shipmentRateDetail');
            if (shipmentRateDetail instanceof Map<String, Object>) {
                Object totalNetCharge = FedExMappingService.getPath((Map<String, Object>) shipmentRateDetail, 'totalNetCharge.amount');
                if (totalNetCharge != null) result.put('totalNetCharge', totalNetCharge);
                Object currencyValue = FedExMappingService.getPath((Map<String, Object>) shipmentRateDetail, 'totalNetCharge.currency');
                if (currencyValue != null) result.put('currency', currencyValue);
            }
        }
        result.put('selectedRate', result.clone());
        return result;
    }

    private static Map<String, Object> normalizeSelectedRate(FedEx_Rate_Quote__c quote) {
        Map<String, Object> selectedRate = new Map<String, Object>{
            'serviceType' => quote.Service_Type__c,
            'serviceName' => quote.Service_Name__c,
            'totalNetCharge' => quote.Total_Net_Charge__c,
            'currency' => quote.Currency__c,
            'transitTime' => quote.Transit_Time__c,
            'deliveryTimestamp' => quote.Delivery_Timestamp__c
        };
        return new Map<String, Object>{ 'selectedRate' => selectedRate };
    }

    private static Map<String, Object> normalizeShipmentResponse(Map<String, Object> responseBody) {
        Map<String, Object> result = new Map<String, Object>();
        Object shipmentObject = FedExMappingService.getPath(responseBody, 'output.transactionShipments.0');
        Map<String, Object> shipment = shipmentObject instanceof Map<String, Object>
            ? (Map<String, Object>) shipmentObject
            : new Map<String, Object>();

        Map<String, Object> shipmentValues = new Map<String, Object>();
        shipmentValues.put('fedexShipmentId', shipment.get('transactionId'));
        shipmentValues.put('masterTrackingNumber', shipment.get('masterTrackingNumber'));
        shipmentValues.put('status', 'Created');
        shipmentValues.put('serviceType', shipment.get('serviceType'));
        Object totalNetCharge = FedExMappingService.getPath(shipment, 'shipmentRating.totalNetCharge.amount');
        Object currencyCode = FedExMappingService.getPath(shipment, 'shipmentRating.totalNetCharge.currency');
        if (totalNetCharge == null) {
            totalNetCharge = FedExMappingService.getPath(shipment, 'shipmentRating.shipmentRateDetails.0.totalNetCharge');
            currencyCode = FedExMappingService.getPath(shipment, 'shipmentRating.shipmentRateDetails.0.currency');
        }
        if (totalNetCharge == null) {
            totalNetCharge = FedExMappingService.getPath(shipment, 'pieceResponses.0.netChargeAmount');
        }
        shipmentValues.put('totalNetCharge', totalNetCharge);
        shipmentValues.put('currency', currencyCode);
        result.put('shipment', shipmentValues);

        Object piece = FedExMappingService.getPath(shipment, 'pieceResponses.0');
        if (piece instanceof Map<String, Object>) {
            Map<String, Object> pieceMap = (Map<String, Object>) piece;
            result.put('package', new Map<String, Object>{ 'trackingNumber' => pieceMap.get('trackingNumber') });
            Object packageDoc = FedExMappingService.getPath(pieceMap, 'packageDocuments.0');
            if (packageDoc instanceof Map<String, Object>) {
                Map<String, Object> doc = (Map<String, Object>) packageDoc;
                result.put('label', new Map<String, Object>{
                    'encodedLabel' => doc.get('encodedLabel'),
                    'imageType' => doc.get('contentType'),
                    'trackingNumber' => pieceMap.get('trackingNumber'),
                    'generatedTimestamp' => Datetime.now()
                });
            }
        }
        return result;
    }

    private static Map<String, Object> normalizeReturnShipmentResponse(Map<String, Object> responseBody) {
        Map<String, Object> shipmentResponse = normalizeShipmentResponse(responseBody);
        Map<String, Object> shipment = (Map<String, Object>) shipmentResponse.get('shipment');
        Map<String, Object> label = (Map<String, Object>) shipmentResponse.get('label');
        Map<String, Object> returnShipment = new Map<String, Object>{
            'fedexShipmentId' => shipment == null ? null : shipment.get('fedexShipmentId'),
            'trackingNumber' => shipment == null ? null : shipment.get('masterTrackingNumber'),
            'status' => 'Created'
        };
        if (label != null) {
            returnShipment.put('encodedLabel', label.get('encodedLabel'));
            shipmentResponse.put('label', label);
        }
        shipmentResponse.put('returnShipment', returnShipment);
        return shipmentResponse;
    }

    private static Map<String, Object> normalizeTrackingResponse(Map<String, Object> responseBody, String trackingNumber) {
        Map<String, Object> result = new Map<String, Object>();
        Object trackResult = FedExMappingService.getPath(responseBody, 'output.completeTrackResults.0.trackResults.0');
        Map<String, Object> track = trackResult instanceof Map<String, Object>
            ? (Map<String, Object>) trackResult
            : new Map<String, Object>();

        Object latestStatusDetail = track.get('latestStatusDetail');
        Map<String, Object> latest = latestStatusDetail instanceof Map<String, Object>
            ? (Map<String, Object>) latestStatusDetail
            : new Map<String, Object>();

        Map<String, Object> tracking = new Map<String, Object>{
            'trackingNumber' => trackingNumber,
            'latestStatus' => latest.get('statusByLocale'),
            'statusCode' => latest.get('code'),
            'statusDescription' => latest.get('description'),
            'lastEventTimestamp' => null,
            'deliveredTimestamp' => track.get('dateAndTimes'),
            'isTerminal' => false
        };

        List<Object> normalizedEvents = new List<Object>();
        Object scanEvents = track.get('scanEvents');
        if (scanEvents instanceof List<Object>) {
            for (Object eventObject : (List<Object>) scanEvents) {
                if (!(eventObject instanceof Map<String, Object>)) continue;
                Map<String, Object> eventMap = (Map<String, Object>) eventObject;
                Map<String, Object> normalizedEvent = new Map<String, Object>{
                    'eventType' => eventMap.get('eventType'),
                    'eventCode' => eventMap.get('eventType'),
                    'description' => eventMap.get('eventDescription'),
                    'timestamp' => eventMap.get('date')
                };
                normalizedEvents.add(normalizedEvent);
                if (tracking.get('lastEventTimestamp') == null) {
                    tracking.put('lastEventTimestamp', eventMap.get('date'));
                }
            }
        }
        result.put('tracking', tracking);
        result.put('events', normalizedEvents);
        return result;
    }

    private static Map<String, Object> normalizeVoidResponse(Map<String, Object> responseBody) {
        return new Map<String, Object>{
            'void' => new Map<String, Object>{
                'status' => 'Voided',
                'confirmationNumber' => FedExMappingService.getPath(responseBody, 'output.transactionId'),
                'voidedTimestamp' => Datetime.now()
            }
        };
    }

    private static Id ensureShipment(Id sourceRecordId, String sourceObjectApiName, Boolean isReturn, Id originalShipmentId) {
        if (sourceObjectApiName == 'FedEx_Shipment__c') {
            return sourceRecordId;
        }

        List<FedEx_Shipment__c> existing = [
            SELECT Id
            FROM FedEx_Shipment__c
            WHERE Source_Record_Id__c = :String.valueOf(sourceRecordId)
            AND Is_Return__c = :isReturn
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        FedEx_Shipment__c shipment = new FedEx_Shipment__c(
            Name = (isReturn ? 'Return ' : '') + 'FedEx Shipment',
            Source_Record_Id__c = sourceRecordId == null ? null : String.valueOf(sourceRecordId),
            Source_Object__c = sourceObjectApiName,
            Is_Return__c = isReturn,
            Original_Shipment__c = originalShipmentId,
            Shipment_Status__c = 'Draft'
        );
        insert shipment;
        return shipment.Id;
    }

    private static SObject queryRecordForMappings(Id recordId, String objectApiName, String actionName) {
        return FedExMappingService.queryMappedRecord(
            recordId,
            FedExMappingService.load(actionName, objectApiName),
            FedExMappingService.DIRECTION_TO_FEDEX
        );
    }

    private static void applyShipmentCoreUpdate(Id shipmentId, Map<String, Object> responseValues, Boolean isReturn) {
        Object shipmentValuesObject = isReturn
            ? responseValues.get('returnShipment')
            : responseValues.get('shipment');
        if (!(shipmentValuesObject instanceof Map<String, Object>)) {
            return;
        }
        Map<String, Object> shipmentValues = (Map<String, Object>) shipmentValuesObject;

        FedEx_Shipment__c updateRecord = new FedEx_Shipment__c(
            Id = shipmentId,
            FedEx_Shipment_Id__c = stringValue(shipmentValues.get('fedexShipmentId')),
            Master_Tracking_Number__c = isReturn ? stringValue(shipmentValues.get('trackingNumber')) : stringValue(shipmentValues.get('masterTrackingNumber')),
            Shipment_Status__c = stringValue(shipmentValues.get('status')),
            Total_Net_Charge__c = decimalValue(shipmentValues.get('totalNetCharge')),
            Currency__c = stringValue(shipmentValues.get('currency')),
            Service_Type__c = stringValue(shipmentValues.get('serviceType')),
            Label_Content_Document_Id__c = stringValue(FedExMappingService.getPath(responseValues, isReturn ? 'returnShipment.labelContentDocumentId' : 'label.contentDocumentId'))
        );
        update updateRecord;
    }

    private static void persistPackageTracking(Id shipmentId, Map<String, Object> responseValues) {
        String trackingNumber = stringValue(FedExMappingService.getPath(responseValues, 'package.trackingNumber'));
        if (String.isBlank(trackingNumber)) {
            return;
        }
        insert new FedEx_Package__c(
            Name = 'Package ' + trackingNumber,
            Shipment__c = shipmentId,
            Tracking_Number__c = trackingNumber,
            Package_Status__c = 'Created'
        );
    }

    private static void updateShipmentTrackingStatus(Id shipmentId, Map<String, Object> responseValues) {
        Map<String, Object> tracking = (Map<String, Object>) responseValues.get('tracking');
        String statusCode = tracking == null ? null : stringValue(tracking.get('statusCode'));
        String statusLabel = tracking == null ? null : stringValue(tracking.get('latestStatus'));
        Boolean isTerminal = false;

        if (String.isNotBlank(statusCode)) {
            List<FedEx_Status_Mapping__c> mappings = [
                SELECT Status_Label__c, Is_Terminal__c
                FROM FedEx_Status_Mapping__c
                WHERE Status_Code__c = :statusCode
                LIMIT 1
            ];
            if (!mappings.isEmpty()) {
                statusLabel = String.isBlank(mappings[0].Status_Label__c) ? statusLabel : mappings[0].Status_Label__c;
                isTerminal = mappings[0].Is_Terminal__c;
            }
        }

        update new FedEx_Shipment__c(
            Id = shipmentId,
            Latest_Status__c = statusLabel,
            Shipment_Status__c = statusLabel,
            Is_Terminal__c = isTerminal
        );
        if (tracking != null) {
            tracking.put('isTerminal', isTerminal);
        }
    }

    private static void upsertTrackingEvents(Id shipmentId, Map<String, Object> responseValues) {
        Map<String, Object> tracking = (Map<String, Object>) responseValues.get('tracking');
        String trackingNumber = tracking == null ? null : stringValue(tracking.get('trackingNumber'));
        Object eventsObject = responseValues.get('events');
        if (!(eventsObject instanceof List<Object>)) {
            return;
        }

        List<FedEx_Tracking_Event__c> events = new List<FedEx_Tracking_Event__c>();
        for (Object eventObject : (List<Object>) eventsObject) {
            if (!(eventObject instanceof Map<String, Object>)) continue;
            Map<String, Object> eventMap = (Map<String, Object>) eventObject;
            String eventCode = stringValue(eventMap.get('eventCode'));
            String timestampValue = stringValue(eventMap.get('timestamp'));
            String dedupeKey = trackingNumber + '|' + eventCode + '|' + timestampValue;
            events.add(new FedEx_Tracking_Event__c(
                Name = String.isBlank(eventCode) ? 'FedEx Tracking Event' : eventCode,
                Shipment__c = shipmentId,
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

    private static void handleDeliveryException(Id shipmentId, Map<String, Object> responseValues) {
        Map<String, Object> tracking = (Map<String, Object>) responseValues.get('tracking');
        String statusCode = tracking == null ? null : stringValue(tracking.get('statusCode'));
        String statusDescription = tracking == null ? null : stringValue(tracking.get('statusDescription'));
        if (String.isBlank(statusCode)) {
            return;
        }

        List<FedEx_Status_Mapping__c> statusMappings = [
            SELECT Is_Exception__c
            FROM FedEx_Status_Mapping__c
            WHERE Status_Code__c = :statusCode
            LIMIT 1
        ];
        if (statusMappings.isEmpty() || !statusMappings[0].Is_Exception__c) {
            return;
        }

        update new FedEx_Shipment__c(
            Id = shipmentId,
            Exception_Reason__c = statusDescription,
            Exception_Timestamp__c = Datetime.now()
        );

        List<FedEx_Exception_Rule__c> rules = [
            SELECT Action__c, Priority__c, Notification_Target__c
            FROM FedEx_Exception_Rule__c
            WHERE Active__c = true
            AND Status_Code__c = :statusCode
            LIMIT 1
        ];
        if (rules.isEmpty()) {
            return;
        }

        FedEx_Exception_Rule__c rule = rules[0];
        if (rule.Action__c == 'Task') {
            insert new Task(
                WhatId = shipmentId,
                Subject = 'FedEx delivery exception',
                Priority = String.isBlank(rule.Priority__c) ? 'Normal' : rule.Priority__c,
                Status = 'Not Started',
                Description = statusDescription
            );
        } else if (rule.Action__c == 'Case') {
            insert new Case(
                Subject = 'FedEx delivery exception',
                Origin = 'FedEx',
                Status = 'New',
                Priority = String.isBlank(rule.Priority__c) ? 'Medium' : rule.Priority__c,
                Description = statusDescription
            );
        }
    }

    private static Id saveLabelIfPresent(Id parentId, Map<String, Object> responseValues, String titlePrefix) {
        String encodedLabel = stringValue(FedExMappingService.getPath(responseValues, 'label.encodedLabel'));
        if (String.isBlank(encodedLabel)) {
            encodedLabel = stringValue(FedExMappingService.getPath(responseValues, 'returnShipment.encodedLabel'));
        }
        if (String.isBlank(encodedLabel)) {
            return null;
        }

        ContentVersion contentVersion = new ContentVersion(
            Title = titlePrefix + ' - ' + Datetime.now().format('yyyyMMddHHmmss'),
            PathOnClient = titlePrefix.replace(' ', '') + '.pdf',
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

    private static Map<String, Object> parseBody(HttpResponse response) {
        if (response == null || String.isBlank(response.getBody())) {
            return new Map<String, Object>();
        }
        Object parsed = JSON.deserializeUntyped(response.getBody());
        return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : new Map<String, Object>();
    }

    private static void requireSuccess(HttpResponse response, Map<String, Object> responseBody, String defaultMessage) {
        Integer statusCode = response == null ? 0 : response.getStatusCode();
        if (statusCode >= 200 && statusCode < 300) {
            return;
        }
        throw new AuraHandledException(defaultMessage + ' ' + extractFedExError(responseBody, statusCode));
    }

    private static String extractFedExError(Map<String, Object> responseBody, Integer statusCode) {
        List<String> messages = new List<String>();
        Object errorsObject = responseBody == null ? null : responseBody.get('errors');
        if (errorsObject instanceof List<Object>) {
            for (Object errorObject : (List<Object>) errorsObject) {
                if (!(errorObject instanceof Map<String, Object>)) continue;
                Map<String, Object> errorMap = (Map<String, Object>) errorObject;
                messages.add('[' + stringValue(errorMap.get('code')) + '] ' + stringValue(errorMap.get('message')));
            }
        }
        return messages.isEmpty() ? 'HTTP ' + statusCode : String.join(messages, '; ');
    }

    private static String getAccountNumber() {
        return FedExAuthService.getCredentialConfig().accountNumber;
    }

    private static OperationResult newResult() {
        OperationResult result = new OperationResult();
        result.success = false;
        result.rateQuotes = new List<RateQuoteOption>();
        return result;
    }

    private static void applyError(OperationResult result, Exception e) {
        result.success = false;
        result.message = e.getMessage();
        ErrorLogUtility.logPaymentError(
            'FedEx',
            'FedExOperationsService',
            e.getMessage() + '\n' + e.getStackTraceString(),
            result.shipmentId == null ? null : String.valueOf(result.shipmentId)
        );
    }

    private static void putNested(Map<String, Object> values, String path, Object value) {
        FedExMappingService.putPath(values, path, value);
    }

    private static void defaultIfBlank(Map<String, Object> values, String key, Object defaultValue) {
        if (!values.containsKey(key) || values.get(key) == null || String.isBlank(String.valueOf(values.get(key)))) {
            values.put(key, defaultValue);
        }
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal decimalValue(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) return null;
        if (value instanceof Decimal) return (Decimal) value;
        return Decimal.valueOf(String.valueOf(value));
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