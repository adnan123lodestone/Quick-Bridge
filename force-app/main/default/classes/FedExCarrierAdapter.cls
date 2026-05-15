public with sharing class FedExCarrierAdapter implements ICarrierAdapter {
    private class FedExCalloutException extends Exception {}

    public String getIntegrationType() {
        return 'fedex';
    }

    public Map<String, Object> validateAddress(Map<String, Object> payload) {
        Map<String, Object> requestBody = new Map<String, Object>{
            'addressesToValidate' => new List<Object>{
                new Map<String, Object>{ 'address' => normalizeAddressPayload(payload) }
            }
        };
        HttpResponse response = send('POST', '/address/v1/addresses/resolve', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'FedEx address validation failed.');
        Map<String, Object> result = normalizeAddressValidationResponse(responseBody);
        result.put('rawResponse', response.getBody());
        return result;
    }

    public Map<String, Object> getRateQuote(Map<String, Object> payload) {
        Map<String, Object> requestBody = buildShipmentRequest(payload, false);

        // Rate API differences vs ship API:
        // - Does not accept labelResponseOptions or labelSpecification
        // - Uses singular "recipient" not "recipients" array
        requestBody.remove('labelResponseOptions');
        Map<String, Object> requestedShipment = (Map<String, Object>) requestBody.get('requestedShipment');
        if (requestedShipment != null) {
            requestedShipment.remove('labelSpecification');
            // Undo the recipients→recipient array conversion done by buildShipmentRequest
            if (requestedShipment.containsKey('recipients') && !requestedShipment.containsKey('recipient')) {
                Object recipientsList = requestedShipment.get('recipients');
                if (recipientsList instanceof List<Object> && !((List<Object>) recipientsList).isEmpty()) {
                    requestedShipment.put('recipient', ((List<Object>) recipientsList)[0]);
                }
                requestedShipment.remove('recipients');
            }
            if (!requestedShipment.containsKey('rateRequestType')) {
                requestedShipment.put('rateRequestType', new List<String>{ 'ACCOUNT' });
            }
        }
        HttpResponse response = send('POST', '/rate/v1/rates/quotes', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'FedEx rate quote failed.');
        return new Map<String, Object>{
            'rawResponse' => response.getBody(),
            'rateDetails' => CarrierMappingService.getPath(responseBody, 'output.rateReplyDetails')
        };
    }

    public Map<String, Object> createShipment(Map<String, Object> payload, Boolean includeLabel) {
        Map<String, Object> requestBody = buildShipmentRequest(payload, includeLabel == true);
        HttpResponse response = send('POST', '/ship/v1/shipments', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'FedEx shipment creation failed.');
        Map<String, Object> result = normalizeShipmentResponse(responseBody);
        result.put('rawResponse', response.getBody());
        return result;
    }


    public Map<String, Object> voidShipment(String masterTrackingNumber, String externalShipmentId) {
        FedExAuthService.FedExCredentialConfig config = FedExAuthService.getCredentialConfig();
        Map<String, Object> requestBody = new Map<String, Object>{
            'accountNumber' => new Map<String, Object>{ 'value' => config.accountNumber },
            'trackingNumber' => masterTrackingNumber,
            'deletionControl' => 'DELETE_ALL_PACKAGES'
        };
        HttpResponse response = send('PUT', '/ship/v1/shipments/cancel', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'FedEx void shipment failed.');
        return new Map<String, Object>{
            'void' => new Map<String, Object>{
                'status' => 'Voided',
                'confirmationNumber' => CarrierMappingService.getPath(responseBody, 'output.transactionId'),
                'voidedTimestamp' => Datetime.now()
            },
            'rawResponse' => response.getBody()
        };
    }

    public Map<String, Object> createReturnLabel(Map<String, Object> payload) {
        Map<String, Object> requestBody = buildShipmentRequest(payload, true);
        CarrierMappingService.putPath(requestBody, 'requestedShipment.returnShipmentDetail.returnType', 'PRINT_RETURN_LABEL');
        HttpResponse response = send('POST', '/ship/v1/shipments', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'FedEx return label creation failed.');
        Map<String, Object> result = normalizeReturnShipmentResponse(responseBody);
        result.put('rawResponse', response.getBody());
        return result;
    }

    public Map<String, Object> syncTrackingStatus(String masterTrackingNumber) {
        Map<String, Object> requestBody = new Map<String, Object>{
            'trackingInfo' => new List<Object>{
                new Map<String, Object>{
                    'trackingNumberInfo' => new Map<String, Object>{
                        'trackingNumber' => masterTrackingNumber
                    }
                }
            },
            'includeDetailedScans' => true
        };
        HttpResponse response = send('POST', '/track/v1/trackingnumbers', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'FedEx tracking sync failed.');
        Map<String, Object> result = normalizeTrackingResponse(responseBody, masterTrackingNumber);
        result.put('rawResponse', response.getBody());
        return result;
    }

    private HttpResponse send(String method, String path, Map<String, Object> body) {
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
        try {
            return new Http().send(request);
        } catch (Exception e) {
            ErrorLogUtility.logException('FedEx', 'FedExCarrierAdapter.send', e, null, null);
            throw e;
        } finally {
            IntegrationUsageService.incrementEndpointUsage(getIntegrationType(), 1);
        }
    }

    private Map<String, Object> buildShipmentRequest(Map<String, Object> mappedPayload, Boolean includeLabel) {
        FedExAuthService.FedExCredentialConfig config = FedExAuthService.getCredentialConfig();
        Map<String, Object> requestedShipment = new Map<String, Object>();
        requestedShipment.putAll(mappedPayload == null ? new Map<String, Object>() : mappedPayload);

        if (requestedShipment.containsKey('shipment') && requestedShipment.get('shipment') instanceof Map<String, Object>) {
            Map<String, Object> shipmentDetails = (Map<String, Object>) requestedShipment.remove('shipment');
            requestedShipment.putAll(shipmentDetails);
        }

        normalizePartyAddress(requestedShipment, 'shipper');
        normalizePartyAddress(requestedShipment, 'recipient');

        // FedEx API requires recipients as an array and a shippingChargesPayment block
        if (requestedShipment.containsKey('recipient') && !requestedShipment.containsKey('recipients')) {
            requestedShipment.put('recipients', new List<Object>{ requestedShipment.remove('recipient') });
        }
        if (!requestedShipment.containsKey('shippingChargesPayment')) {
            requestedShipment.put('shippingChargesPayment', new Map<String, Object>{
                'paymentType' => 'SENDER',
                'payor' => new Map<String, Object>{
                    'responsibleParty' => new Map<String, Object>{
                        'accountNumber' => new Map<String, Object>{ 'value' => config.accountNumber }
                    }
                }
            });
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
                packageInfo.put('weight', new Map<String, Object>{ 'units' => 'LB', 'value' => 0 });
            } else if (packageInfo.get('weight') instanceof Map<String, Object>) {
                Map<String, Object> weightMap = (Map<String, Object>) packageInfo.get('weight');
                if (!weightMap.containsKey('units')) {
                    weightMap.put('units', 'LB');
                }
            }
            requestedShipment.put('requestedPackageLineItems', new List<Object>{ packageInfo });
        } else if (requestedShipment.get('requestedPackageLineItems') instanceof List<Object>) {
            List<Object> lineItems = (List<Object>) requestedShipment.get('requestedPackageLineItems');
            if (!lineItems.isEmpty() && lineItems[0] instanceof Map<String, Object>) {
                Map<String, Object> firstItem = (Map<String, Object>) lineItems[0];
                if (firstItem.get('weight') instanceof Map<String, Object>) {
                    Map<String, Object> weightMap = (Map<String, Object>) firstItem.get('weight');
                    if (!weightMap.containsKey('units')) {
                        weightMap.put('units', 'LB');
                    }
                }
            }
        }

        requestedShipment.put('labelSpecification', new Map<String, Object>{
            'imageType' => 'PDF',
            'labelStockType' => 'PAPER_85X11_TOP_HALF_LABEL'
        });

        return new Map<String, Object>{
            'labelResponseOptions' => 'LABEL',
            'accountNumber' => new Map<String, Object>{ 'value' => config.accountNumber },
            'requestedShipment' => requestedShipment
        };
    }

    private Map<String, Object> normalizeAddressPayload(Map<String, Object> mappedPayload) {
        if (mappedPayload != null && mappedPayload.get('address') instanceof Map<String, Object>) {
            return (Map<String, Object>) mappedPayload.get('address');
        }
        return mappedPayload == null ? new Map<String, Object>() : mappedPayload;
    }

    private Map<String, Object> normalizeAddressValidationResponse(Map<String, Object> responseBody) {
        Map<String, Object> result = new Map<String, Object>();
        Object resolvedAddress = CarrierMappingService.getPath(responseBody, 'output.resolvedAddresses.0');
        Map<String, Object> resolved = resolvedAddress instanceof Map<String, Object>
            ? (Map<String, Object>) resolvedAddress
            : new Map<String, Object>();
        Boolean hasStreet = resolved.get('streetLines') != null || resolved.get('streetLinesToken') != null;
        Object address = hasStreet ? resolved : resolved.get('address');
        result.put('validatedAddress', address instanceof Map<String, Object> ? address : resolved);
        result.put('addressClassification', resolved.get('classification'));
        result.put('residential', resolved.get('residential'));
        return result;
    }

    private Map<String, Object> normalizeShipmentResponse(Map<String, Object> responseBody) {
        Map<String, Object> result = new Map<String, Object>();
        Object shipmentObject = CarrierMappingService.getPath(responseBody, 'output.transactionShipments.0');
        Map<String, Object> shipment = shipmentObject instanceof Map<String, Object>
            ? (Map<String, Object>) shipmentObject
            : new Map<String, Object>();

        Map<String, Object> shipmentValues = new Map<String, Object>();
        shipmentValues.put('externalShipmentId', shipment.get('transactionId'));
        shipmentValues.put('masterTrackingNumber', shipment.get('masterTrackingNumber'));
        shipmentValues.put('status', 'Created');
        shipmentValues.put('serviceType', shipment.get('serviceType'));
        Object totalNetCharge = CarrierMappingService.getPath(shipment, 'shipmentRating.totalNetCharge.amount');
        Object currencyCode = CarrierMappingService.getPath(shipment, 'shipmentRating.totalNetCharge.currency');
        if (totalNetCharge == null) {
            totalNetCharge = CarrierMappingService.getPath(shipment, 'shipmentRating.shipmentRateDetails.0.totalNetCharge');
            currencyCode = CarrierMappingService.getPath(shipment, 'shipmentRating.shipmentRateDetails.0.currency');
        }
        if (totalNetCharge == null) {
            totalNetCharge = CarrierMappingService.getPath(shipment, 'pieceResponses.0.netChargeAmount');
        }
        shipmentValues.put('totalNetCharge', totalNetCharge);
        shipmentValues.put('currency', currencyCode);
        result.put('shipment', shipmentValues);

        Object piece = CarrierMappingService.getPath(shipment, 'pieceResponses.0');
        if (piece instanceof Map<String, Object>) {
            Map<String, Object> pieceMap = (Map<String, Object>) piece;
            result.put('package', new Map<String, Object>{ 'trackingNumber' => pieceMap.get('trackingNumber') });
            Object packageDoc = CarrierMappingService.getPath(pieceMap, 'packageDocuments.0');
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

    private Map<String, Object> normalizeReturnShipmentResponse(Map<String, Object> responseBody) {
        Map<String, Object> shipmentResponse = normalizeShipmentResponse(responseBody);
        Map<String, Object> shipment = (Map<String, Object>) shipmentResponse.get('shipment');
        Map<String, Object> label = (Map<String, Object>) shipmentResponse.get('label');
        Map<String, Object> returnShipment = new Map<String, Object>{
            'externalShipmentId' => shipment == null ? null : shipment.get('externalShipmentId'),
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

    private Map<String, Object> normalizeTrackingResponse(Map<String, Object> responseBody, String trackingNumber) {
        Map<String, Object> result = new Map<String, Object>();
        Object trackResult = CarrierMappingService.getPath(responseBody, 'output.completeTrackResults.0.trackResults.0');
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

    private Map<String, Object> parseBody(HttpResponse response) {
        if (response == null || String.isBlank(response.getBody())) {
            return new Map<String, Object>();
        }
        Object parsed = JSON.deserializeUntyped(response.getBody());
        return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : new Map<String, Object>();
    }

    private void requireSuccess(HttpResponse response, Map<String, Object> responseBody, String defaultMessage) {
        Integer statusCode = response == null ? 0 : response.getStatusCode();
        if (statusCode >= 200 && statusCode < 300) {
            return;
        }
        List<String> messages = new List<String>();
        Object errorsObject = responseBody == null ? null : responseBody.get('errors');
        if (errorsObject instanceof List<Object>) {
            for (Object errorObject : (List<Object>) errorsObject) {
                if (!(errorObject instanceof Map<String, Object>)) continue;
                Map<String, Object> errorMap = (Map<String, Object>) errorObject;
                messages.add('[' + errorMap.get('code') + '] ' + errorMap.get('message'));
            }
        }
        String errorDetail = messages.isEmpty() ? 'HTTP ' + statusCode : String.join(messages, '; ');
        ErrorLogUtility.logCalloutFailure(
            'FedEx',
            'FedExCarrierAdapter.requireSuccess',
            defaultMessage + ' ' + errorDetail,
            statusCode,
            null,
            null
        );
        throw new FedExCalloutException(defaultMessage + ' ' + errorDetail);
    }

    private void defaultIfBlank(Map<String, Object> values, String key, Object defaultValue) {
        if (!values.containsKey(key) || values.get(key) == null || String.isBlank(String.valueOf(values.get(key)))) {
            values.put(key, defaultValue);
        }
    }

    private void normalizePartyAddress(Map<String, Object> requestedShipment, String partyKey) {
        Object partyObject = requestedShipment.get(partyKey);
        if (!(partyObject instanceof Map<String, Object>)) {
            return;
        }

        Map<String, Object> party = (Map<String, Object>) partyObject;
        if (party.get('address') instanceof Map<String, Object>) {
            return;
        }

        Map<String, Object> address = new Map<String, Object>();
        moveIfPresent(party, address, 'streetLines');
        moveIfPresent(party, address, 'city');
        moveIfPresent(party, address, 'stateOrProvinceCode');
        moveIfPresent(party, address, 'postalCode');
        moveIfPresent(party, address, 'countryCode');
        moveIfPresent(party, address, 'residential');

        if (!address.isEmpty()) {
            party.put('address', address);
        }
    }

    private void moveIfPresent(Map<String, Object> source, Map<String, Object> target, String key) {
        if (source.containsKey(key)) {
            target.put(key, source.remove(key));
        }
    }
}