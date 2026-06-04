@IsTest
private class DHLCarrierAdapterTest {
  private class DHLMock implements HttpCalloutMock {
    private Integer statusCode;
    private String body;
    private String expectedPath;

    DHLMock(Integer statusCode, String body, String expectedPath) {
      this.statusCode = statusCode;
      this.body = body;
      this.expectedPath = expectedPath;
    }

    public HttpResponse respond(HttpRequest request) {
      System.assert(
        request.getEndpoint().contains(expectedPath),
        request.getEndpoint()
      );
      System.assertEquals(
        'Basic ' +
        EncodingUtil.base64Encode(Blob.valueOf('dhl-key:dhl-secret')),
        request.getHeader('Authorization')
      );
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(body);
      return response;
    }
  }

  @TestSetup
  static void setupConfig() {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'DHL',
      Connector_Key__c = 'dhl',
      Connector_Label__c = 'DHL',
      Active__c = true,
      Environment__c = 'Sandbox',
      Entitlement_Status__c = 'Active',
      Expiry_Date__c = Date.today().addDays(30),
      Health_Status__c = 'Unknown'
    );
    insert instanceRecord;
    insert new List<Connector_Config_Value__c>{
      configValue(instanceRecord, 'DHL_Api_Key__c', 'dhl-key', false),
      configValue(instanceRecord, 'apiSecretRef', 'dhl-secret', true),
      configValue(instanceRecord, 'DHL_Account_Number__c', '123456789', false),
      configValue(instanceRecord, 'DHL_Default_Product_Code__c', 'P', false)
    };
  }

  @IsTest
  static void validateAddressNormalizesResponse() {
    Test.setMock(
      HttpCalloutMock.class,
      new DHLMock(
        200,
        '{"warnings":[],"serviceArea":{"code":"NYC"}}',
        '/address-validate'
      )
    );

    Test.startTest();
    Map<String, Object> result = new DHLCarrierAdapter()
      .validateAddress(
        new Map<String, Object>{
          'address' => new Map<String, Object>{
            'streetLines' => new List<Object>{ '10 Main St' },
            'city' => 'New York',
            'postalCode' => '10001',
            'countryCode' => 'US'
          }
        }
      );
    Test.stopTest();

    System.assertEquals(true, result.get('isValid'));
    System.assertNotEquals(null, result.get('validatedAddress'));
    System.assertNotEquals(null, result.get('rawResponse'));
  }

  @IsTest
  static void rateQuoteNormalizesRateDetails() {
    Test.setMock(
      HttpCalloutMock.class,
      new DHLMock(
        200,
        '{"products":[{"productCode":"P","localProductCode":"P","productName":"EXPRESS WORLDWIDE","totalPrice":[{"price":12.34,"priceCurrency":"USD"}],"deliveryCapabilities":{"estimatedDeliveryDateAndTime":"2026-06-01T10:30:00Z","totalTransitDays":2}}]}',
        '/rates'
      )
    );

    Test.startTest();
    Map<String, Object> result = new DHLCarrierAdapter()
      .getRateQuote(minimalShipmentPayload());
    Test.stopTest();

    List<Object> rateDetails = (List<Object>) result.get('rateDetails');
    System.assertEquals(1, rateDetails.size());
    System.assertEquals(
      'P',
      ((Map<String, Object>) rateDetails[0]).get('serviceType')
    );
    System.assertEquals(
      12.34,
      ((Map<String, Object>) rateDetails[0]).get('totalNetCharge')
    );
  }

  @IsTest
  static void createShipmentNormalizesShipmentPackageAndLabel() {
    Test.setMock(
      HttpCalloutMock.class,
      new DHLMock(
        201,
        '{"shipmentTrackingNumber":"JD014600006230000001","trackingUrl":"https://dhl.test/track","documents":[{"content":"UERG","typeCode":"label","encodingFormat":"pdf"}],"packages":[{"trackingNumber":"JD014600006230000001"}],"productCode":"P","shipmentDetails":[{"serviceHandlingFeatureCodes":["P"]}]}',
        '/shipments'
      )
    );

    Test.startTest();
    Map<String, Object> result = new DHLCarrierAdapter()
      .createShipment(minimalShipmentPayload(), true);
    Test.stopTest();

    System.assertEquals(
      'JD014600006230000001',
      CarrierMappingService.getPath(result, 'shipment.masterTrackingNumber')
    );
    System.assertEquals(
      'JD014600006230000001',
      CarrierMappingService.getPath(result, 'package.trackingNumber')
    );
    System.assertEquals(
      'UERG',
      CarrierMappingService.getPath(result, 'label.encodedLabel')
    );
  }

  @IsTest
  static void createReturnLabelNormalizesReturnShipment() {
    Test.setMock(
      HttpCalloutMock.class,
      new DHLMock(
        201,
        '{"shipmentTrackingNumber":"JD014600006230000002","documents":[{"content":"UkVUVVJO","typeCode":"label","encodingFormat":"pdf"}]}',
        '/shipments'
      )
    );

    Test.startTest();
    Map<String, Object> result = new DHLCarrierAdapter()
      .createReturnLabel(minimalShipmentPayload());
    Test.stopTest();

    System.assertEquals(
      'JD014600006230000002',
      CarrierMappingService.getPath(result, 'returnShipment.trackingNumber')
    );
    System.assertEquals(
      'UkVUVVJO',
      CarrierMappingService.getPath(result, 'returnShipment.encodedLabel')
    );
  }

  @IsTest
  static void trackingNormalizesEvents() {
    Test.setMock(
      HttpCalloutMock.class,
      new DHLMock(
        200,
        '{"shipments":[{"id":"JD014600006230000001","status":{"statusCode":"delivered","description":"Delivered","timestamp":"2026-06-01T12:00:00Z"},"events":[{"typeCode":"PU","description":"Picked up","timestamp":"2026-05-31T12:00:00Z"},{"typeCode":"OK","description":"Delivered","timestamp":"2026-06-01T12:00:00Z"}]}]}',
        '/tracking'
      )
    );

    Test.startTest();
    Map<String, Object> result = new DHLCarrierAdapter()
      .syncTrackingStatus('JD014600006230000001');
    Test.stopTest();

    System.assertEquals(
      'Delivered',
      CarrierMappingService.getPath(result, 'tracking.latestStatus')
    );
    System.assertEquals(2, ((List<Object>) result.get('events')).size());
  }

  @IsTest
  static void voidShipmentNormalizesConfirmation() {
    Test.setMock(
      HttpCalloutMock.class,
      new DHLMock(
        200,
        '{"status":"cancelled","shipmentTrackingNumber":"JD014600006230000001"}',
        '/shipments/JD014600006230000001'
      )
    );

    Test.startTest();
    Map<String, Object> result = new DHLCarrierAdapter()
      .voidShipment('JD014600006230000001', null);
    Test.stopTest();

    System.assertEquals(
      'Voided',
      CarrierMappingService.getPath(result, 'void.status')
    );
  }

  @IsTest
  static void httpFailureLogsAndThrows() {
    Test.setMock(
      HttpCalloutMock.class,
      new DHLMock(
        400,
        '{"detail":"Bad request","additionalDetails":[{"message":"Invalid DHL payload"}]}',
        '/rates'
      )
    );

    Boolean didThrow = false;
    Test.startTest();
    try {
      new DHLCarrierAdapter().getRateQuote(minimalShipmentPayload());
    } catch (Exception e) {
      didThrow = true;
      System.assert(e.getMessage().contains('DHL rate quote failed'));
    }
    Test.stopTest();
    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void unauthorizedReturnsActionableMessage() {
    Test.setMock(
      HttpCalloutMock.class,
      new DHLMock(401, '{"detail":"Invalid credentials"}', '/address-validate')
    );

    Test.startTest();
    Boolean threw = false;
    String message;
    try {
      new DHLCarrierAdapter()
        .validateAddress(
          new Map<String, Object>{
            'address' => new Map<String, Object>{
              'streetLines' => new List<Object>{ '10 Main St' },
              'city' => 'New York',
              'postalCode' => '10001',
              'countryCode' => 'US'
            }
          }
        );
    } catch (Exception e) {
      threw = true;
      message = e.getMessage();
    }
    Test.stopTest();

    System.assertEquals(true, threw, 'A 401 must raise an exception.');
    System.assert(
      message.contains('401') && message.contains('authentication'),
      'Message should explain the auth failure: ' + message
    );
    System.assert(
      message.contains('Sandbox'),
      'Message should name the active environment: ' + message
    );

    // The callout failure log should capture HTTP 401.
    List<Error_Log__c> logs = [
      SELECT Http_Status_Code__c
      FROM Error_Log__c
      WHERE Gateway_Name__c = 'DHL' AND Http_Status_Code__c = 401
    ];
    System.assert(!logs.isEmpty(), 'A DHL 401 error log should be written.');
  }

  private static Connector_Config_Value__c configValue(
    Connector_Instance__c instanceRecord,
    String fieldKey,
    String value,
    Boolean isSecretReference
  ) {
    return new Connector_Config_Value__c(
      Name = 'dhl:' + fieldKey,
      Connector_Instance__c = instanceRecord.Id,
      Connector_Key__c = 'dhl',
      Field_Key__c = fieldKey,
      Value__c = value,
      Is_Secret_Reference__c = isSecretReference
    );
  }

  private static Map<String, Object> minimalShipmentPayload() {
    return new Map<String, Object>{
      'shipper' => new Map<String, Object>{
        'name' => 'Sender',
        'address' => new Map<String, Object>{
          'streetLines' => new List<Object>{ '1 Origin St' },
          'city' => 'New York',
          'postalCode' => '10001',
          'countryCode' => 'US'
        }
      },
      'recipient' => new Map<String, Object>{
        'name' => 'Receiver',
        'address' => new Map<String, Object>{
          'streetLines' => new List<Object>{ '2 Dest St' },
          'city' => 'London',
          'postalCode' => 'SW1A 1AA',
          'countryCode' => 'GB'
        }
      },
      'package' => new Map<String, Object>{
        'weight' => new Map<String, Object>{ 'value' => 1, 'unit' => 'LB' }
      }
    };
  }
}