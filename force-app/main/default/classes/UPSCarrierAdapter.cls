public with sharing class UPSCarrierAdapter implements ICarrierAdapter {

    public String getIntegrationType() {
        return 'ups';
    }

    public Map<String, Object> validateAddress(Map<String, Object> payload) {
        Map<String, Object> addressKey = buildAddressKeyFormat(payload);
        Map<String, Object> requestBody = new Map<String, Object>{
            'XAVRequest' => new Map<String, Object>{
                'AddressKeyFormat' => addressKey
            }
        };

        HttpResponse response = send('POST', '/addressvalidation/v2/3?regionalrequestindicator=True&maximumcandidatelistsize=20', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'UPS address validation failed.');
        Map<String, Object> result = normalizeAddressValidationResponse(responseBody);
        result.put('rawResponse', response.getBody());
        return result;
    }

    public Map<String, Object> getRateQuote(Map<String, Object> payload) {
        UPSAuthService.UPSCredentialConfig config = UPSAuthService.getCredentialConfig();
        Map<String, Object> shipmentBlock = buildShipmentBlock(payload, config, false);
        Map<String, Object> requestBody = new Map<String, Object>{
            'RateRequest' => new Map<String, Object>{
                'Request' => new Map<String, Object>{
                    'RequestOption' => 'Shop',
                    'SubVersion' => '2403',
                    'TransactionReference' => new Map<String, Object>{ 'CustomerContext' => 'Rate Quote' }
                },
                'Shipment' => shipmentBlock
            }
        };

        HttpResponse response = send('POST', '/rating/v2403/Shop?additionalinfo=timeintransit', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'UPS rate quote failed.');

        return new Map<String, Object>{
            'rawResponse' => response.getBody(),
            'rateDetails' => CarrierMappingService.getPath(responseBody, 'RateResponse.RatedShipment')
        };
    }

    public Map<String, Object> createShipment(Map<String, Object> payload, Boolean includeLabel) {
        UPSAuthService.UPSCredentialConfig config = UPSAuthService.getCredentialConfig();
        Map<String, Object> shipmentBlock = buildShipmentBlock(payload, config, false);
        Map<String, Object> requestBody = new Map<String, Object>{
            'ShipmentRequest' => new Map<String, Object>{
                'Request' => new Map<String, Object>{
                    'RequestOption' => 'nonvalidate',
                    'SubVersion' => '2403',
                    'TransactionReference' => new Map<String, Object>{ 'CustomerContext' => 'Create Shipment' }
                },
                'Shipment' => shipmentBlock
            }
        };
        if (includeLabel == true) {
            ((Map<String, Object>) requestBody.get('ShipmentRequest')).put(
                'LabelSpecification',
                new Map<String, Object>{
                    'LabelImageFormat' => new Map<String, Object>{ 'Code' => 'GIF', 'Description' => 'GIF' }
                }
            );
        }

        HttpResponse response = send('POST', '/shipments/v2403/ship', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'UPS shipment creation failed.');
        Map<String, Object> result = normalizeShipmentResponse(responseBody);
        result.put('rawResponse', response.getBody());
        return result;
    }

    public Map<String, Object> generateLabel(String masterTrackingNumber, String externalShipmentId, Map<String, Object> payload) {
        String trackingNumber = String.isNotBlank(masterTrackingNumber) ? masterTrackingNumber : externalShipmentId;
        if (String.isBlank(trackingNumber)) {
            throw new AuraHandledException('A tracking number is required to recover a UPS label.');
        }

        Map<String, Object> requestBody = new Map<String, Object>{
            'LabelRecoveryRequest' => new Map<String, Object>{
                'Request' => new Map<String, Object>{
                    'RequestOption' => 'Non_Validate',
                    'SubVersion' => '1903',
                    'TransactionReference' => new Map<String, Object>{ 'CustomerContext' => 'Label Recovery' }
                },
                'LabelSpecification' => new Map<String, Object>{
                    'LabelImageFormat' => new Map<String, Object>{ 'Code' => 'GIF' }
                },
                'Translate' => new Map<String, Object>{
                    'LanguageCode' => 'eng',
                    'DialectCode' => 'US',
                    'Code' => '01'
                },
                'TrackingNumber' => trackingNumber
            }
        };

        HttpResponse response = send('POST', '/labels/v1/recovery', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'UPS label recovery failed.');
        Map<String, Object> result = normalizeLabelRecoveryResponse(responseBody, trackingNumber);
        result.put('rawResponse', response.getBody());
        return result;
    }

    public Map<String, Object> voidShipment(String masterTrackingNumber, String externalShipmentId) {
        String shipmentId = String.isNotBlank(externalShipmentId) ? externalShipmentId : masterTrackingNumber;
        if (String.isBlank(shipmentId)) {
            throw new AuraHandledException('A shipment identifier is required to void a UPS shipment.');
        }
        String path = '/shipments/v2403/void/cancel/' + EncodingUtil.urlEncode(shipmentId, 'UTF-8');
        if (String.isNotBlank(masterTrackingNumber) && masterTrackingNumber != shipmentId) {
            path += '?trackingnumber=' + EncodingUtil.urlEncode(masterTrackingNumber, 'UTF-8');
        }
        HttpResponse response = send('DELETE', path, null);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'UPS void shipment failed.');
        return new Map<String, Object>{
            'void' => new Map<String, Object>{
                'status' => 'Voided',
                'confirmationNumber' => CarrierMappingService.getPath(responseBody, 'VoidShipmentResponse.SummaryResult.Status.Code'),
                'voidedTimestamp' => Datetime.now()
            },
            'rawResponse' => response.getBody()
        };
    }

    public Map<String, Object> createReturnLabel(Map<String, Object> payload) {
        UPSAuthService.UPSCredentialConfig config = UPSAuthService.getCredentialConfig();
        Map<String, Object> shipmentBlock = buildShipmentBlock(payload, config, true);
        Map<String, Object> requestBody = new Map<String, Object>{
            'ShipmentRequest' => new Map<String, Object>{
                'Request' => new Map<String, Object>{
                    'RequestOption' => 'nonvalidate',
                    'SubVersion' => '2403',
                    'TransactionReference' => new Map<String, Object>{ 'CustomerContext' => 'Return Label' }
                },
                'Shipment' => shipmentBlock,
                'LabelSpecification' => new Map<String, Object>{
                    'LabelImageFormat' => new Map<String, Object>{ 'Code' => 'GIF', 'Description' => 'GIF' }
                }
            }
        };

        HttpResponse response = send('POST', '/shipments/v2403/ship', requestBody);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'UPS return label creation failed.');
        Map<String, Object> result = normalizeReturnShipmentResponse(responseBody);
        result.put('rawResponse', response.getBody());
        return result;
    }

    public Map<String, Object> syncTrackingStatus(String masterTrackingNumber) {
        if (String.isBlank(masterTrackingNumber)) {
            throw new AuraHandledException('A tracking number is required before syncing UPS status.');
        }
        String path = '/track/v1/details/' + EncodingUtil.urlEncode(masterTrackingNumber, 'UTF-8') +
            '?locale=en_US&returnSignature=false';
        HttpResponse response = send('GET', path, null);
        Map<String, Object> responseBody = parseBody(response);
        requireSuccess(response, responseBody, 'UPS tracking sync failed.');
        Map<String, Object> result = normalizeTrackingResponse(responseBody, masterTrackingNumber);
        result.put('rawResponse', response.getBody());
        return result;
    }

    private HttpResponse send(String method, String path, Map<String, Object> body) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(UPSAuthService.getApiBaseUrl() + path);
        request.setMethod(method);
        request.setTimeout(60000);
        request.setHeader('Authorization', 'Bearer ' + UPSAuthService.getAccessToken());
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setHeader('transId', UPSAuthService.generateTransId());
        request.setHeader('transactionSrc', 'QuickBridge');
        if (body != null && (method == 'POST' || method == 'PUT')) {
            request.setBody(JSON.serialize(body));
        }
        try {
            return new Http().send(request);
        } catch (Exception e) {
            ErrorLogUtility.logException('UPS', 'UPSCarrierAdapter.send', e, null, null);
            throw e;
        } finally {
            IntegrationUsageService.incrementEndpointUsage(getIntegrationType(), 1);
        }
    }

    private Map<String, Object> buildShipmentBlock(Map<String, Object> payload, UPSAuthService.UPSCredentialConfig config, Boolean isReturn) {
        Map<String, Object> shipment = new Map<String, Object>();
        if (payload != null) {
            shipment.putAll(payload);
        }

        if (!shipment.containsKey('Shipper')) {
            shipment.put('Shipper', new Map<String, Object>{
                'Name' => 'Shipper',
                'ShipperNumber' => config.accountNumber,
                'Address' => new Map<String, Object>{ 'CountryCode' => 'US' }
            });
        } else if (shipment.get('Shipper') instanceof Map<String, Object>) {
            Map<String, Object> shipper = (Map<String, Object>) shipment.get('Shipper');
            if (!shipper.containsKey('ShipperNumber')) {
                shipper.put('ShipperNumber', config.accountNumber);
            }
        }

        if (!shipment.containsKey('Service')) {
            shipment.put('Service', new Map<String, Object>{
                'Code' => String.isBlank(config.defaultServiceCode) ? '03' : config.defaultServiceCode,
                'Description' => 'UPS Ground'
            });
        }

        if (!shipment.containsKey('PaymentInformation')) {
            shipment.put('PaymentInformation', new Map<String, Object>{
                'ShipmentCharge' => new Map<String, Object>{
                    'Type' => '01',
                    'BillShipper' => new Map<String, Object>{ 'AccountNumber' => config.accountNumber }
                }
            });
        }

        if (!shipment.containsKey('Package')) {
            shipment.put('Package', new Map<String, Object>{
                'Description' => isReturn ? 'Return Package' : 'Package',
                'Packaging' => new Map<String, Object>{ 'Code' => '02', 'Description' => 'Package' },
                'PackageWeight' => new Map<String, Object>{
                    'UnitOfMeasurement' => new Map<String, Object>{ 'Code' => 'LBS' },
                    'Weight' => '0'
                }
            });
        } else if (shipment.get('Package') instanceof Map<String, Object>) {
            Map<String, Object> pkg = (Map<String, Object>) shipment.get('Package');
            if (pkg.get('PackageWeight') instanceof Map<String, Object>) {
                Map<String, Object> pkgWeight = (Map<String, Object>) pkg.get('PackageWeight');
                if (!pkgWeight.containsKey('UnitOfMeasurement')) {
                    pkgWeight.put('UnitOfMeasurement', new Map<String, Object>{ 'Code' => 'LBS' });
                }
            }
            if (isReturn && !pkg.containsKey('Description')) {
                pkg.put('Description', 'Return Package');
            }
        }

        if (isReturn && !shipment.containsKey('ReturnService')) {
            shipment.put('ReturnService', new Map<String, Object>{
                'Code' => '9',
                'Description' => 'UPS Print Return Label'
            });
        }

        return shipment;
    }

    private Map<String, Object> buildAddressKeyFormat(Map<String, Object> payload) {
        Map<String, Object> addressKey = new Map<String, Object>();
        if (payload == null) {
            return addressKey;
        }

        Object addressObj = payload.get('address');
        Map<String, Object> address = addressObj instanceof Map<String, Object>
            ? (Map<String, Object>) addressObj
            : payload;

        if (address.containsKey('streetLines')) {
            addressKey.put('AddressLine', address.get('streetLines'));
        } else if (address.containsKey('AddressLine')) {
            addressKey.put('AddressLine', address.get('AddressLine'));
        }
        if (address.containsKey('AddressLine2') && address.get('AddressLine2') != null) {
            Object existingLine = addressKey.get('AddressLine');
            if (existingLine instanceof List<Object>) {
                ((List<Object>) existingLine).add(address.get('AddressLine2'));
            } else if (existingLine != null) {
                addressKey.put('AddressLine', new List<Object>{ existingLine, address.get('AddressLine2') });
            } else {
                addressKey.put('AddressLine', address.get('AddressLine2'));
            }
        }

        mapIfPresent(address, 'city', addressKey, 'PoliticalDivision2');
        mapIfPresent(address, 'City', addressKey, 'PoliticalDivision2');
        mapIfPresent(address, 'stateOrProvinceCode', addressKey, 'PoliticalDivision1');
        mapIfPresent(address, 'StateProvinceCode', addressKey, 'PoliticalDivision1');
        mapIfPresent(address, 'postalCode', addressKey, 'PostcodePrimaryLow');
        mapIfPresent(address, 'PostalCode', addressKey, 'PostcodePrimaryLow');
        mapIfPresent(address, 'countryCode', addressKey, 'CountryCode');
        mapIfPresent(address, 'CountryCode', addressKey, 'CountryCode');
        mapIfPresent(address, 'PoliticalDivision2', addressKey, 'PoliticalDivision2');
        mapIfPresent(address, 'PoliticalDivision1', addressKey, 'PoliticalDivision1');
        mapIfPresent(address, 'PostcodePrimaryLow', addressKey, 'PostcodePrimaryLow');

        if (!addressKey.containsKey('CountryCode')) {
            addressKey.put('CountryCode', 'US');
        }

        return addressKey;
    }

    private void mapIfPresent(Map<String, Object> source, String sourceKey, Map<String, Object> target, String targetKey) {
        if (source.containsKey(sourceKey) && source.get(sourceKey) != null) {
            target.put(targetKey, source.get(sourceKey));
        }
    }

    private Map<String, Object> normalizeAddressValidationResponse(Map<String, Object> responseBody) {
        Map<String, Object> result = new Map<String, Object>();
        Object xavResponse = responseBody.get('XAVResponse');
        Map<String, Object> xav = xavResponse instanceof Map<String, Object>
            ? (Map<String, Object>) xavResponse
            : new Map<String, Object>();

        Object candidatesObj = xav.get('Candidate');
        Map<String, Object> firstCandidate = new Map<String, Object>();
        if (candidatesObj instanceof List<Object> && !((List<Object>) candidatesObj).isEmpty()) {
            Object first = ((List<Object>) candidatesObj)[0];
            if (first instanceof Map<String, Object>) {
                firstCandidate = (Map<String, Object>) first;
            }
        } else if (candidatesObj instanceof Map<String, Object>) {
            firstCandidate = (Map<String, Object>) candidatesObj;
        }

        Object addressKeyObj = firstCandidate.get('AddressKeyFormat');
        Map<String, Object> addressKey = addressKeyObj instanceof Map<String, Object>
            ? (Map<String, Object>) addressKeyObj
            : new Map<String, Object>();

        Map<String, Object> normalizedAddress = new Map<String, Object>{
            'city' => addressKey.get('PoliticalDivision2'),
            'stateOrProvinceCode' => addressKey.get('PoliticalDivision1'),
            'postalCode' => addressKey.get('PostcodePrimaryLow'),
            'countryCode' => addressKey.get('CountryCode')
        };
        if (addressKey.get('AddressLine') instanceof List<Object>) {
            List<Object> lines = (List<Object>) addressKey.get('AddressLine');
            if (!lines.isEmpty()) normalizedAddress.put('streetLine1', lines[0]);
        } else if (addressKey.get('AddressLine') != null) {
            normalizedAddress.put('streetLine1', addressKey.get('AddressLine'));
        }

        Object classObj = firstCandidate.get('AddressClassification');
        String classification = '';
        if (classObj instanceof Map<String, Object>) {
            classification = String.valueOf(((Map<String, Object>) classObj).get('Description'));
        }

        result.put('validatedAddress', normalizedAddress);
        result.put('addressClassification', classification);
        result.put('residential', classification == 'RESIDENTIAL');
        result.put('isValid', !xav.containsKey('NoCandidatesIndicator'));
        result.put('isAmbiguous', xav.containsKey('AmbiguousAddressIndicator'));
        return result;
    }

    private Map<String, Object> normalizeShipmentResponse(Map<String, Object> responseBody) {
        Map<String, Object> result = new Map<String, Object>();
        Object shipResultsObj = CarrierMappingService.getPath(responseBody, 'ShipmentResponse.ShipmentResults');
        Map<String, Object> shipResults = shipResultsObj instanceof Map<String, Object>
            ? (Map<String, Object>) shipResultsObj
            : new Map<String, Object>();

        String masterTrackingNumber = String.valueOf(shipResults.get('ShipmentIdentificationNumber'));
        Object totalChargesObj = CarrierMappingService.getPath(shipResults, 'ShipmentCharges.TotalCharges');
        Map<String, Object> totalCharges = totalChargesObj instanceof Map<String, Object>
            ? (Map<String, Object>) totalChargesObj
            : new Map<String, Object>();

        Map<String, Object> shipmentValues = new Map<String, Object>{
            'externalShipmentId' => masterTrackingNumber,
            'masterTrackingNumber' => masterTrackingNumber,
            'status' => 'Created',
            'totalNetCharge' => totalCharges.get('MonetaryValue'),
            'currency' => totalCharges.get('CurrencyCode')
        };
        result.put('shipment', shipmentValues);

        Object packageResultsObj = shipResults.get('PackageResults');
        Map<String, Object> packageResults = new Map<String, Object>();
        if (packageResultsObj instanceof List<Object> && !((List<Object>) packageResultsObj).isEmpty()) {
            Object first = ((List<Object>) packageResultsObj)[0];
            if (first instanceof Map<String, Object>) packageResults = (Map<String, Object>) first;
        } else if (packageResultsObj instanceof Map<String, Object>) {
            packageResults = (Map<String, Object>) packageResultsObj;
        }

        String packageTracking = String.valueOf(packageResults.get('TrackingNumber'));
        result.put('package', new Map<String, Object>{ 'trackingNumber' => packageTracking });

        Object shippingLabelObj = packageResults.get('ShippingLabel');
        if (shippingLabelObj instanceof Map<String, Object>) {
            Map<String, Object> shippingLabel = (Map<String, Object>) shippingLabelObj;
            result.put('label', new Map<String, Object>{
                'encodedLabel' => shippingLabel.get('GraphicImage'),
                'imageType' => CarrierMappingService.getPath(shippingLabel, 'ImageFormat.Code'),
                'trackingNumber' => packageTracking,
                'generatedTimestamp' => Datetime.now()
            });
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

    private Map<String, Object> normalizeLabelRecoveryResponse(Map<String, Object> responseBody, String fallbackTrackingNumber) {
        Map<String, Object> result = new Map<String, Object>();
        Object labelResultsObj = CarrierMappingService.getPath(responseBody, 'LabelRecoveryResponse.LabelResults');
        Map<String, Object> labelResults = labelResultsObj instanceof Map<String, Object>
            ? (Map<String, Object>) labelResultsObj
            : new Map<String, Object>();
        Object labelImageObj = labelResults.get('LabelImage');
        Map<String, Object> labelImage = labelImageObj instanceof Map<String, Object>
            ? (Map<String, Object>) labelImageObj
            : new Map<String, Object>();
        String trackingNumber = labelResults.get('TrackingNumber') == null
            ? fallbackTrackingNumber
            : String.valueOf(labelResults.get('TrackingNumber'));

        result.put('shipment', new Map<String, Object>{
            'externalShipmentId' => CarrierMappingService.getPath(responseBody, 'LabelRecoveryResponse.ShipmentIdentificationNumber'),
            'masterTrackingNumber' => trackingNumber,
            'status' => 'Created'
        });
        result.put('label', new Map<String, Object>{
            'encodedLabel' => labelImage.get('GraphicImage'),
            'imageType' => CarrierMappingService.getPath(labelImage, 'LabelImageFormat.Code'),
            'trackingNumber' => trackingNumber,
            'generatedTimestamp' => Datetime.now()
        });
        return result;
    }

    private Map<String, Object> normalizeTrackingResponse(Map<String, Object> responseBody, String trackingNumber) {
        Map<String, Object> result = new Map<String, Object>();
        Object packageObj = CarrierMappingService.getPath(responseBody, 'trackResponse.shipment.0.package.0');
        Map<String, Object> pkg = packageObj instanceof Map<String, Object>
            ? (Map<String, Object>) packageObj
            : new Map<String, Object>();

        Object currentStatusObj = pkg.get('currentStatus');
        if (!(currentStatusObj instanceof Map<String, Object>)) {
            Object activitiesObjForStatus = pkg.get('activity');
            if (activitiesObjForStatus instanceof List<Object> && !((List<Object>) activitiesObjForStatus).isEmpty()) {
                Object firstActivity = ((List<Object>) activitiesObjForStatus)[0];
                if (firstActivity instanceof Map<String, Object>) {
                    currentStatusObj = ((Map<String, Object>) firstActivity).get('status');
                }
            }
        }
        Map<String, Object> currentStatus = currentStatusObj instanceof Map<String, Object>
            ? (Map<String, Object>) currentStatusObj
            : new Map<String, Object>();

        Map<String, Object> tracking = new Map<String, Object>{
            'trackingNumber' => trackingNumber,
            'latestStatus' => currentStatus.containsKey('simplifiedTextDescription') ? currentStatus.get('simplifiedTextDescription') : currentStatus.get('description'),
            'statusCode' => currentStatus.containsKey('code') ? currentStatus.get('code') : currentStatus.get('statusCode'),
            'statusDescription' => currentStatus.get('description'),
            'lastEventTimestamp' => null,
            'isTerminal' => false
        };

        List<Object> normalizedEvents = new List<Object>();
        Object activitiesObj = pkg.get('activity');
        if (activitiesObj instanceof List<Object>) {
            for (Object activityObject : (List<Object>) activitiesObj) {
                if (!(activityObject instanceof Map<String, Object>)) continue;
                Map<String, Object> activity = (Map<String, Object>) activityObject;
                String activityDate = String.valueOf(activity.get('date'));
                String activityTime = String.valueOf(activity.get('time'));
                String isoTimestamp = null;
                if (String.isNotBlank(activityDate) && activityDate.length() == 8) {
                    isoTimestamp = activityDate.substring(0, 4) + '-' + activityDate.substring(4, 6) + '-' + activityDate.substring(6, 8);
                    if (String.isNotBlank(activityTime) && activityTime.length() >= 6) {
                        isoTimestamp += 'T' + activityTime.substring(0, 2) + ':' + activityTime.substring(2, 4) + ':' + activityTime.substring(4, 6) + 'Z';
                    }
                }

                Map<String, Object> normalizedEvent = new Map<String, Object>{
                    'eventType' => currentStatus.get('code'),
                    'eventCode' => currentStatus.get('code'),
                    'description' => activity.get('description'),
                    'timestamp' => isoTimestamp
                };
                normalizedEvents.add(normalizedEvent);
                if (tracking.get('lastEventTimestamp') == null) {
                    tracking.put('lastEventTimestamp', isoTimestamp);
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
        Object errorsObj = CarrierMappingService.getPath(responseBody, 'response.errors');
        if (errorsObj instanceof List<Object>) {
            for (Object e : (List<Object>) errorsObj) {
                if (e instanceof Map<String, Object>) {
                    Map<String, Object> err = (Map<String, Object>) e;
                    messages.add('[' + err.get('code') + '] ' + err.get('message'));
                }
            }
        }
        String errorDetail = messages.isEmpty() ? 'HTTP ' + statusCode : String.join(messages, '; ');
        ErrorLogUtility.logCalloutFailure(
            'UPS',
            'UPSCarrierAdapter.requireSuccess',
            defaultMessage + ' ' + errorDetail,
            statusCode,
            null,
            null
        );
        throw new AuraHandledException(defaultMessage + ' ' + errorDetail);
    }
}