public with sharing class DHLCarrierAdapter implements ICarrierAdapter {
  private class DHLCalloutException extends Exception {
  }

  public String getIntegrationType() {
    return 'dhl';
  }

  public Map<String, Object> validateAddress(Map<String, Object> payload) {
    Map<String, Object> address = normalizeAddressPayload(payload);
    String path =
      '/address-validate?type=delivery' +
      queryParam(
        'countryCode',
        stringValue(
          firstPresent(
            address,
            new List<String>{ 'countryCode', 'CountryCode' }
          )
        )
      ) +
      queryParam(
        'postalCode',
        stringValue(
          firstPresent(address, new List<String>{ 'postalCode', 'PostalCode' })
        )
      ) +
      queryParam(
        'cityName',
        stringValue(firstPresent(address, new List<String>{ 'city', 'City' }))
      ) +
      queryParam('strictValidation', 'false');
    HttpResponse response = send('GET', path, null);
    Map<String, Object> responseBody = parseBody(response);
    requireSuccess(response, responseBody, 'DHL address validation failed.');
    Map<String, Object> result = normalizeAddressValidationResponse(
      responseBody,
      address
    );
    result.put('rawResponse', response.getBody());
    return result;
  }

  public Map<String, Object> getRateQuote(Map<String, Object> payload) {
    Map<String, Object> requestBody = buildRateRequest(payload);
    HttpResponse response = send('POST', '/rates', requestBody);
    Map<String, Object> responseBody = parseBody(response);
    requireSuccess(response, responseBody, 'DHL rate quote failed.');
    return new Map<String, Object>{
      'rawResponse' => response.getBody(),
      'rateDetails' => normalizeRateDetails(responseBody)
    };
  }

  public Map<String, Object> createShipment(
    Map<String, Object> payload,
    Boolean includeLabel
  ) {
    Map<String, Object> requestBody = buildShipmentRequest(
      payload,
      includeLabel == true,
      false
    );
    HttpResponse response = send('POST', '/shipments', requestBody);
    Map<String, Object> responseBody = parseBody(response);
    requireSuccess(response, responseBody, 'DHL shipment creation failed.');
    Map<String, Object> result = normalizeShipmentResponse(responseBody);
    result.put('rawResponse', response.getBody());
    return result;
  }

  public Map<String, Object> voidShipment(
    String masterTrackingNumber,
    String externalShipmentId
  ) {
    DHLAuthService.DHLCredentialConfig config = DHLAuthService.getCredentialConfig();
    String shipmentId = String.isNotBlank(externalShipmentId)
      ? externalShipmentId
      : masterTrackingNumber;
    if (String.isBlank(shipmentId)) {
      throw new AuraHandledException(
        'A shipment identifier is required to void a DHL shipment.'
      );
    }
    String path =
      '/shipments/' +
      EncodingUtil.urlEncode(shipmentId, 'UTF-8') +
      '?shipperAccountNumber=' +
      EncodingUtil.urlEncode(config.accountNumber, 'UTF-8');
    HttpResponse response = send('DELETE', path, null);
    Map<String, Object> responseBody = parseBody(response);
    requireSuccess(response, responseBody, 'DHL void shipment failed.');
    return new Map<String, Object>{
      'void' => new Map<String, Object>{
        'status' => 'Voided',
        'confirmationNumber' => firstPresent(
          responseBody,
          new List<String>{
            'shipmentTrackingNumber',
            'dispatchConfirmationNumber',
            'status'
          }
        ),
        'voidedTimestamp' => Datetime.now()
      },
      'rawResponse' => response.getBody()
    };
  }

  public Map<String, Object> createReturnLabel(Map<String, Object> payload) {
    Map<String, Object> requestBody = buildShipmentRequest(payload, true, true);
    HttpResponse response = send('POST', '/shipments', requestBody);
    Map<String, Object> responseBody = parseBody(response);
    requireSuccess(response, responseBody, 'DHL return label creation failed.');
    Map<String, Object> result = normalizeReturnShipmentResponse(responseBody);
    result.put('rawResponse', response.getBody());
    return result;
  }

  public Map<String, Object> syncTrackingStatus(String masterTrackingNumber) {
    if (String.isBlank(masterTrackingNumber)) {
      throw new AuraHandledException(
        'A tracking number is required before syncing DHL status.'
      );
    }
    String path =
      '/tracking?shipmentTrackingNumber=' +
      EncodingUtil.urlEncode(masterTrackingNumber, 'UTF-8');
    HttpResponse response = send('GET', path, null);
    Map<String, Object> responseBody = parseBody(response);
    requireSuccess(response, responseBody, 'DHL tracking sync failed.');
    Map<String, Object> result = normalizeTrackingResponse(
      responseBody,
      masterTrackingNumber
    );
    result.put('rawResponse', response.getBody());
    return result;
  }

  private HttpResponse send(
    String method,
    String path,
    Map<String, Object> body
  ) {
    DHLAuthService.DHLCredentialConfig config = DHLAuthService.getCredentialConfig();
    HttpRequest request = new HttpRequest();
    request.setEndpoint(DHLAuthService.getBaseUrl(config.environment) + path);
    request.setMethod(method);
    request.setTimeout(60000);
    request.setHeader(
      'Authorization',
      DHLAuthService.getBasicAuthHeader(config)
    );
    request.setHeader('Content-Type', 'application/json');
    request.setHeader('Accept', 'application/json');
    if (
      body != null && (method == 'POST' || method == 'PUT' || method == 'PATCH')
    ) {
      request.setBody(JSON.serialize(body));
    }
    try {
      return new Http().send(request);
    } catch (Exception e) {
      ErrorLogUtility.logException(
        'DHL',
        'DHLCarrierAdapter.send',
        e,
        null,
        null
      );
      throw e;
    } finally {
      IntegrationUsageService.incrementEndpointUsage(getIntegrationType(), 1);
    }
  }

  private Map<String, Object> buildRateRequest(Map<String, Object> payload) {
    DHLAuthService.DHLCredentialConfig config = DHLAuthService.getCredentialConfig();
    Map<String, Object> requestBody = baseShipmentPayload(
      payload,
      config,
      false
    );
    requestBody.put('isCustomsDeclarable', false);
    requestBody.put(
      'estimatedDeliveryDate',
      new Map<String, Object>{ 'isRequested' => true }
    );
    requestBody.put(
      'getAdditionalInformation',
      new List<Object>{
        new Map<String, Object>{
          'typeCode' => 'allValueAddedServices',
          'isRequested' => false
        }
      }
    );
    return requestBody;
  }

  private Map<String, Object> buildShipmentRequest(
    Map<String, Object> payload,
    Boolean includeLabel,
    Boolean isReturn
  ) {
    DHLAuthService.DHLCredentialConfig config = DHLAuthService.getCredentialConfig();
    Map<String, Object> requestBody = baseShipmentPayload(
      payload,
      config,
      isReturn == true
    );
    requestBody.put(
      'plannedShippingDateAndTime',
      System.now().addDays(1).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss \'GMT\'Z')
    );
    requestBody.put(
      'pickup',
      new Map<String, Object>{ 'isRequested' => false }
    );
    requestBody.put(
      'content',
      new Map<String, Object>{
        'isCustomsDeclarable' => false,
        'description' => isReturn == true ? 'Return Package' : 'Package',
        'packages' => requestBody.remove('packages'),
        'unitOfMeasurement' => 'imperial'
      }
    );
    if (includeLabel == true) {
      requestBody.put(
        'outputImageProperties',
        new Map<String, Object>{
          'printerDPI' => 300,
          'encodingFormat' => 'pdf',
          'imageOptions' => new List<Object>{
            new Map<String, Object>{
              'typeCode' => 'label',
              'templateName' => 'ECOM26_84_001',
              'isRequested' => true
            }
          }
        }
      );
    }
    if (isReturn == true) {
      requestBody.put(
        'shipmentReferences',
        new List<Object>{
          new Map<String, Object>{
            'typeCode' => 'CU',
            'value' => 'QuickBridge Return'
          }
        }
      );
    }
    return requestBody;
  }

  private Map<String, Object> baseShipmentPayload(
    Map<String, Object> payload,
    DHLAuthService.DHLCredentialConfig config,
    Boolean isReturn
  ) {
    Map<String, Object> normalized = payload == null
      ? new Map<String, Object>()
      : new Map<String, Object>(payload);
    Map<String, Object> shipper = partyMap(normalized, 'shipper', 'Shipper');
    Map<String, Object> recipient = partyMap(
      normalized,
      'recipient',
      'receiver'
    );
    if (isReturn == true) {
      Map<String, Object> originalShipper = shipper;
      shipper = recipient;
      recipient = originalShipper;
    }

    Map<String, Object> requestBody = new Map<String, Object>();
    requestBody.put(
      'customerDetails',
      new Map<String, Object>{
        'shipperDetails' => dhlParty(shipper, 'Shipper'),
        'receiverDetails' => dhlParty(recipient, 'Receiver')
      }
    );
    requestBody.put(
      'accounts',
      new List<Object>{
        new Map<String, Object>{
          'typeCode' => 'shipper',
          'number' => config.accountNumber
        }
      }
    );
    requestBody.put(
      'productCode',
      stringValue(
        firstPresent(
          normalized,
          new List<String>{ 'productCode', 'serviceType' }
        )
      )
    );
    if (String.isBlank((String) requestBody.get('productCode'))) {
      requestBody.put('productCode', config.defaultProductCode);
    }
    requestBody.put('localProductCode', requestBody.get('productCode'));
    requestBody.put(
      'plannedShippingDateAndTime',
      System.now().addDays(1).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss \'GMT\'Z')
    );
    requestBody.put('unitOfMeasurement', 'imperial');
    requestBody.put(
      'packages',
      new List<Object>{ dhlPackage(packageMap(normalized)) }
    );
    return requestBody;
  }

  private Map<String, Object> partyMap(
    Map<String, Object> payload,
    String primaryKey,
    String alternateKey
  ) {
    Object party = payload.get(primaryKey);
    if (!(party instanceof Map<String, Object>)) {
      party = payload.get(alternateKey);
    }
    return party instanceof Map<String, Object>
      ? (Map<String, Object>) party
      : new Map<String, Object>();
  }

  private Map<String, Object> packageMap(Map<String, Object> payload) {
    Object packageObject = payload.get('package');
    if (!(packageObject instanceof Map<String, Object>)) {
      packageObject = payload.get('Package');
    }
    if (!(packageObject instanceof Map<String, Object>)) {
      Object packagesObject = payload.get('packages');
      if (
        packagesObject instanceof List<Object> &&
        !((List<Object>) packagesObject).isEmpty()
      ) {
        packageObject = ((List<Object>) packagesObject)[0];
      }
    }
    return packageObject instanceof Map<String, Object>
      ? (Map<String, Object>) packageObject
      : new Map<String, Object>();
  }

  private Map<String, Object> dhlParty(
    Map<String, Object> party,
    String fallbackName
  ) {
    Map<String, Object> address = normalizeAddressPayload(party);
    Map<String, Object> postalAddress = new Map<String, Object>{
      'postalCode' => firstPresent(
        address,
        new List<String>{ 'postalCode', 'PostalCode' }
      ),
      'cityName' => firstPresent(address, new List<String>{ 'city', 'City' }),
      'countryCode' => firstPresent(
        address,
        new List<String>{ 'countryCode', 'CountryCode' }
      ),
      'provinceCode' => firstPresent(
        address,
        new List<String>{
          'stateOrProvinceCode',
          'StateProvinceCode',
          'state',
          'State'
        }
      ),
      'addressLine1' => firstStreetLine(address)
    };
    return new Map<String, Object>{
      'postalAddress' => removeNulls(postalAddress),
      'contactInformation' => removeNulls(
        new Map<String, Object>{
          'companyName' => firstPresent(
            party,
            new List<String>{ 'companyName', 'Name', 'name' }
          ),
          'fullName' => firstPresent(
            party,
            new List<String>{ 'fullName', 'Name', 'name' }
          ),
          'phone' => firstPresent(party, new List<String>{ 'phone', 'Phone' }),
          'email' => firstPresent(party, new List<String>{ 'email', 'Email' })
        }
      ),
      'registrationNumbers' => new List<Object>(),
      'typeCode' => 'business'
    };
  }

  private Map<String, Object> dhlPackage(Map<String, Object> packageInfo) {
    Object weightObject = packageInfo.get('weight');
    Map<String, Object> weight = weightObject instanceof Map<String, Object>
      ? (Map<String, Object>) weightObject
      : new Map<String, Object>{ 'value' => weightObject };
    Decimal weightValue = decimalValue(
      firstPresent(weight, new List<String>{ 'value', 'Weight' })
    );
    if (weightValue == null || weightValue <= 0) {
      weightValue = 1;
    }
    return removeNulls(
      new Map<String, Object>{
        'weight' => weightValue,
        'dimensions' => new Map<String, Object>{
          'length' => decimalValue(
            firstPresent(packageInfo, new List<String>{ 'length', 'Length' })
          ),
          'width' => decimalValue(
            firstPresent(packageInfo, new List<String>{ 'width', 'Width' })
          ),
          'height' => decimalValue(
            firstPresent(packageInfo, new List<String>{ 'height', 'Height' })
          )
        }
      }
    );
  }

  private List<Object> normalizeRateDetails(Map<String, Object> responseBody) {
    List<Object> details = new List<Object>();
    Object productsObject = responseBody.get('products');
    if (!(productsObject instanceof List<Object>)) {
      productsObject = responseBody.get('rateDetails');
    }
    if (productsObject instanceof List<Object>) {
      for (Object productObject : (List<Object>) productsObject) {
        if (!(productObject instanceof Map<String, Object>))
          continue;
        Map<String, Object> product = (Map<String, Object>) productObject;
        Map<String, Object> detail = new Map<String, Object>{
          'serviceType' => firstPresent(
            product,
            new List<String>{ 'productCode', 'localProductCode' }
          ),
          'serviceName' => product.get('productName'),
          'totalNetCharge' => null,
          'currency' => null,
          'deliveryTimestamp' => CarrierMappingService.getPath(
            product,
            'deliveryCapabilities.estimatedDeliveryDateAndTime'
          ),
          'transitTime' => CarrierMappingService.getPath(
            product,
            'deliveryCapabilities.totalTransitDays'
          )
        };
        Object totalPrice = product.get('totalPrice');
        if (
          totalPrice instanceof List<Object> &&
          !((List<Object>) totalPrice).isEmpty() &&
          ((List<Object>) totalPrice)[0] instanceof Map<String, Object>
        ) {
          Map<String, Object> firstPrice = (Map<String, Object>) ((List<Object>) totalPrice)[0];
          detail.put(
            'totalNetCharge',
            firstPresent(firstPrice, new List<String>{ 'price', 'priceValue' })
          );
          detail.put(
            'currency',
            firstPresent(
              firstPrice,
              new List<String>{ 'priceCurrency', 'currencyCode' }
            )
          );
        }
        details.add(detail);
      }
    }
    return details;
  }

  private Map<String, Object> normalizeAddressValidationResponse(
    Map<String, Object> responseBody,
    Map<String, Object> requestAddress
  ) {
    Map<String, Object> address = new Map<String, Object>{
      'streetLines' => requestAddress.get('streetLines'),
      'streetLine1' => firstStreetLine(requestAddress),
      'city' => firstPresent(
        requestAddress,
        new List<String>{ 'city', 'City' }
      ),
      'stateOrProvinceCode' => firstPresent(
        requestAddress,
        new List<String>{
          'stateOrProvinceCode',
          'StateProvinceCode',
          'state',
          'State'
        }
      ),
      'postalCode' => firstPresent(
        requestAddress,
        new List<String>{ 'postalCode', 'PostalCode' }
      ),
      'countryCode' => firstPresent(
        requestAddress,
        new List<String>{ 'countryCode', 'CountryCode' }
      )
    };
    return new Map<String, Object>{
      'validatedAddress' => removeNulls(address),
      'addressClassification' => responseBody.get('serviceArea'),
      'residential' => null,
      'isValid' => true
    };
  }

  private Map<String, Object> normalizeShipmentResponse(
    Map<String, Object> responseBody
  ) {
    String trackingNumber = stringValue(
      firstPresent(
        responseBody,
        new List<String>{ 'shipmentTrackingNumber', 'trackingNumber' }
      )
    );
    Object packagesObject = responseBody.get('packages');
    Map<String, Object> firstPackage = new Map<String, Object>();
    if (
      packagesObject instanceof List<Object> &&
      !((List<Object>) packagesObject).isEmpty() &&
      ((List<Object>) packagesObject)[0] instanceof Map<String, Object>
    ) {
      firstPackage = (Map<String, Object>) ((List<Object>) packagesObject)[0];
    }
    String packageTracking = stringValue(
      firstPresent(
        firstPackage,
        new List<String>{ 'trackingNumber', 'packageTrackingNumber' }
      )
    );
    if (String.isBlank(packageTracking)) {
      packageTracking = trackingNumber;
    }

    Map<String, Object> result = new Map<String, Object>{
      'shipment' => new Map<String, Object>{
        'externalShipmentId' => trackingNumber,
        'masterTrackingNumber' => trackingNumber,
        'status' => 'Created',
        'serviceType' => firstPresent(
          responseBody,
          new List<String>{ 'productCode', 'localProductCode' }
        ),
        'totalNetCharge' => CarrierMappingService.getPath(
          responseBody,
          'shipmentCharges.0.price'
        ),
        'currency' => CarrierMappingService.getPath(
          responseBody,
          'shipmentCharges.0.priceCurrency'
        )
      },
      'package' => new Map<String, Object>{
        'trackingNumber' => packageTracking
      }
    };

    Map<String, Object> label = firstDocument(responseBody);
    if (!label.isEmpty()) {
      label.put('trackingNumber', packageTracking);
      label.put('generatedTimestamp', Datetime.now());
      result.put('label', label);
    }
    return result;
  }

  private Map<String, Object> normalizeReturnShipmentResponse(
    Map<String, Object> responseBody
  ) {
    Map<String, Object> shipmentResponse = normalizeShipmentResponse(
      responseBody
    );
    Map<String, Object> shipment = (Map<String, Object>) shipmentResponse.get(
      'shipment'
    );
    Map<String, Object> label = (Map<String, Object>) shipmentResponse.get(
      'label'
    );
    Map<String, Object> returnShipment = new Map<String, Object>{
      'externalShipmentId' => shipment == null
        ? null
        : shipment.get('externalShipmentId'),
      'trackingNumber' => shipment == null
        ? null
        : shipment.get('masterTrackingNumber'),
      'status' => 'Created'
    };
    if (label != null) {
      returnShipment.put('encodedLabel', label.get('encodedLabel'));
      returnShipment.put('imageType', label.get('imageType'));
    }
    shipmentResponse.put('returnShipment', returnShipment);
    return shipmentResponse;
  }

  private Map<String, Object> normalizeTrackingResponse(
    Map<String, Object> responseBody,
    String trackingNumber
  ) {
    Object shipmentObject = CarrierMappingService.getPath(
      responseBody,
      'shipments.0'
    );
    Map<String, Object> shipment = shipmentObject instanceof Map<String, Object>
      ? (Map<String, Object>) shipmentObject
      : responseBody;
    Object statusObject = shipment.get('status');
    Map<String, Object> status = statusObject instanceof Map<String, Object>
      ? (Map<String, Object>) statusObject
      : new Map<String, Object>();

    Map<String, Object> tracking = new Map<String, Object>{
      'trackingNumber' => String.isBlank(stringValue(shipment.get('id')))
        ? trackingNumber
        : stringValue(shipment.get('id')),
      'latestStatus' => firstPresent(
        status,
        new List<String>{ 'description', 'status' }
      ),
      'statusCode' => firstPresent(
        status,
        new List<String>{ 'statusCode', 'code' }
      ),
      'statusDescription' => firstPresent(
        status,
        new List<String>{ 'description', 'remark' }
      ),
      'lastEventTimestamp' => firstPresent(
        status,
        new List<String>{ 'timestamp', 'date' }
      ),
      'isTerminal' => false
    };

    List<Object> events = new List<Object>();
    Object eventsObject = shipment.get('events');
    if (eventsObject instanceof List<Object>) {
      for (Object eventObject : (List<Object>) eventsObject) {
        if (!(eventObject instanceof Map<String, Object>))
          continue;
        Map<String, Object> eventMap = (Map<String, Object>) eventObject;
        events.add(
          new Map<String, Object>{
            'eventType' => firstPresent(
              eventMap,
              new List<String>{ 'typeCode', 'statusCode' }
            ),
            'eventCode' => firstPresent(
              eventMap,
              new List<String>{ 'typeCode', 'statusCode' }
            ),
            'description' => eventMap.get('description'),
            'timestamp' => firstPresent(
              eventMap,
              new List<String>{ 'timestamp', 'date' }
            )
          }
        );
      }
    }
    return new Map<String, Object>{
      'tracking' => tracking,
      'events' => events
    };
  }

  private Map<String, Object> firstDocument(Map<String, Object> responseBody) {
    Object documentsObject = responseBody.get('documents');
    if (!(documentsObject instanceof List<Object>)) {
      documentsObject = CarrierMappingService.getPath(
        responseBody,
        'shipmentDocuments'
      );
    }
    if (documentsObject instanceof List<Object>) {
      for (Object documentObject : (List<Object>) documentsObject) {
        if (!(documentObject instanceof Map<String, Object>))
          continue;
        Map<String, Object> documentMap = (Map<String, Object>) documentObject;
        Object content = firstPresent(
          documentMap,
          new List<String>{ 'content', 'encodedLabel', 'base64Data' }
        );
        if (content == null)
          continue;
        return new Map<String, Object>{
          'encodedLabel' => content,
          'imageType' => firstPresent(
            documentMap,
            new List<String>{ 'encodingFormat', 'imageFormat', 'contentType' }
          )
        };
      }
    }
    return new Map<String, Object>();
  }

  private Map<String, Object> parseBody(HttpResponse response) {
    if (response == null || String.isBlank(response.getBody())) {
      return new Map<String, Object>();
    }
    Object parsed = JSON.deserializeUntyped(response.getBody());
    return parsed instanceof Map<String, Object>
      ? (Map<String, Object>) parsed
      : new Map<String, Object>();
  }

  private void requireSuccess(
    HttpResponse response,
    Map<String, Object> responseBody,
    String defaultMessage
  ) {
    Integer statusCode = response == null ? 0 : response.getStatusCode();
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    List<String> messages = new List<String>();
    Object additionalDetails = responseBody == null
      ? null
      : responseBody.get('additionalDetails');
    if (additionalDetails instanceof List<Object>) {
      for (Object detailObject : (List<Object>) additionalDetails) {
        if (detailObject instanceof Map<String, Object>) {
          messages.add(
            stringValue(((Map<String, Object>) detailObject).get('message'))
          );
        }
      }
    }
    if (responseBody != null && responseBody.get('detail') != null) {
      messages.add(stringValue(responseBody.get('detail')));
    }
    String errorDetail = messages.isEmpty()
      ? 'HTTP ' + statusCode
      : String.join(messages, '; ');
    ErrorLogUtility.logCalloutFailure(
      'DHL',
      'DHLCarrierAdapter.requireSuccess',
      defaultMessage + ' ' + errorDetail,
      statusCode,
      null,
      null
    );
    throw new DHLCalloutException(defaultMessage + ' ' + errorDetail);
  }

  private Map<String, Object> normalizeAddressPayload(
    Map<String, Object> mappedPayload
  ) {
    if (
      mappedPayload != null &&
      mappedPayload.get('address') instanceof Map<String, Object>
    ) {
      return (Map<String, Object>) mappedPayload.get('address');
    }
    if (
      mappedPayload != null &&
      mappedPayload.get('postalAddress') instanceof Map<String, Object>
    ) {
      return (Map<String, Object>) mappedPayload.get('postalAddress');
    }
    return mappedPayload == null ? new Map<String, Object>() : mappedPayload;
  }

  private Object firstPresent(Map<String, Object> values, List<String> keys) {
    if (values == null)
      return null;
    for (String key : keys) {
      if (
        values.containsKey(key) &&
        values.get(key) != null &&
        !String.isBlank(String.valueOf(values.get(key)))
      ) {
        return values.get(key);
      }
    }
    return null;
  }

  private String firstStreetLine(Map<String, Object> address) {
    Object streetLines = address == null ? null : address.get('streetLines');
    if (
      streetLines instanceof List<Object> &&
      !((List<Object>) streetLines).isEmpty()
    ) {
      return stringValue(((List<Object>) streetLines)[0]);
    }
    Object addressLine = firstPresent(
      address,
      new List<String>{ 'streetLine1', 'addressLine1', 'AddressLine', 'street' }
    );
    return stringValue(addressLine);
  }

  private Map<String, Object> removeNulls(Map<String, Object> values) {
    Map<String, Object> result = new Map<String, Object>();
    for (String key : values.keySet()) {
      Object value = values.get(key);
      if (value == null || String.isBlank(String.valueOf(value))) {
        continue;
      }
      if (value instanceof Map<String, Object>) {
        value = removeNulls((Map<String, Object>) value);
        if (((Map<String, Object>) value).isEmpty()) {
          continue;
        }
      }
      result.put(key, value);
    }
    return result;
  }

  private String queryParam(String key, String value) {
    if (String.isBlank(value)) {
      return '';
    }
    return '&' + key + '=' + EncodingUtil.urlEncode(value, 'UTF-8');
  }

  private String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private Decimal decimalValue(Object value) {
    if (value == null || String.isBlank(String.valueOf(value)))
      return null;
    if (value instanceof Decimal)
      return (Decimal) value;
    try {
      return Decimal.valueOf(String.valueOf(value));
    } catch (Exception e) {
      return null;
    }
  }
}