@IsTest
private class UPSCarrierAdapterTest {
  private class UPSMock implements HttpCalloutMock {
    private Integer statusCode;
    private String body;
    private String expectedPath;

    UPSMock(Integer statusCode, String body, String expectedPath) {
      this.statusCode = statusCode;
      this.body = body;
      this.expectedPath = expectedPath;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      if (request.getEndpoint().contains('/security/v1/oauth/token')) {
        System.assertEquals(
          'Basic ' + EncodingUtil.base64Encode(Blob.valueOf('ups-client:ups-secret')),
          request.getHeader('Authorization')
        );
        response.setStatusCode(200);
        response.setBody('{"access_token":"adapter-token","token_type":"Bearer","expires_in":"3600"}');
        return response;
      }

      System.assert(
        request.getEndpoint().contains(expectedPath),
        request.getEndpoint()
      );
      System.assertEquals('Bearer adapter-token', request.getHeader('Authorization'));
      System.assertNotEquals(null, request.getHeader('transId'));
      response.setStatusCode(statusCode);
      response.setBody(body);
      return response;
    }
  }

  @TestSetup
  static void setupConfig() {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'UPS',
      Connector_Key__c = 'ups',
      Connector_Label__c = 'UPS',
      Active__c = true,
      Environment__c = 'Sandbox',
      Entitlement_Status__c = 'Active',
      Expiry_Date__c = Date.today().addDays(30),
      Health_Status__c = 'Unknown'
    );
    insert instanceRecord;
    insert new List<Connector_Config_Value__c>{
      configValue(instanceRecord, 'UPS_Client_Id__c', 'ups-client', false),
      configValue(instanceRecord, 'UPS_Client_Secret__c', 'ups-secret', true),
      configValue(instanceRecord, 'UPS_Account_Number__c', 'A12345', false),
      configValue(instanceRecord, 'UPS_Default_Service_Code__c', '03', false)
    };
  }

  @IsTest
  static void validateAddressNormalizesCandidateList() {
    Test.setMock(
      HttpCalloutMock.class,
      new UPSMock(
        200,
        '{"XAVResponse":{"Candidate":[{"AddressClassification":{"Description":"RESIDENTIAL"},"AddressKeyFormat":{"AddressLine":["10 Main St"],"PoliticalDivision2":"New York","PoliticalDivision1":"NY","PostcodePrimaryLow":"10001","CountryCode":"US"}}]}}',
        '/addressvalidation/v2/3'
      )
    );

    Test.startTest();
    Map<String, Object> result = new UPSCarrierAdapter()
      .validateAddress(
        new Map<String, Object>{
          'address' => new Map<String, Object>{
            'streetLines' => new List<Object>{ '10 Main St' },
            'AddressLine2' => 'Floor 2',
            'city' => 'New York',
            'stateOrProvinceCode' => 'NY',
            'postalCode' => '10001'
          }
        }
      );
    Test.stopTest();

    System.assertEquals(true, result.get('isValid'));
    System.assertEquals(true, result.get('residential'));
    System.assertEquals('RESIDENTIAL', result.get('addressClassification'));
    System.assertNotEquals(null, result.get('rawResponse'));
  }

  @IsTest
  static void rateQuoteReturnsRatedShipment() {
    Test.setMock(
      HttpCalloutMock.class,
      new UPSMock(
        200,
        '{"RateResponse":{"RatedShipment":[{"Service":{"Code":"03"},"TotalCharges":{"MonetaryValue":"12.34","CurrencyCode":"USD"}}]}}',
        '/rating/v2403/Shop'
      )
    );

    Test.startTest();
    Map<String, Object> result = new UPSCarrierAdapter()
      .getRateQuote(minimalShipmentPayload());
    Test.stopTest();

    List<Object> rateDetails = (List<Object>) result.get('rateDetails');
    System.assertEquals(1, rateDetails.size());
    System.assertEquals('03', CarrierMappingService.getPath(result, 'rateDetails.0.Service.Code'));
  }

  @IsTest
  static void createShipmentNormalizesShipmentPackageAndLabel() {
    Test.setMock(
      HttpCalloutMock.class,
      new UPSMock(
        200,
        shipmentResponseBody('1Z999', '1ZPKG', 'R0lGODlh', 'GIF'),
        '/shipments/v2403/ship'
      )
    );

    Test.startTest();
    Map<String, Object> result = new UPSCarrierAdapter()
      .createShipment(minimalShipmentPayload(), true);
    Test.stopTest();

    System.assertEquals('1Z999', CarrierMappingService.getPath(result, 'shipment.masterTrackingNumber'));
    System.assertEquals('1ZPKG', CarrierMappingService.getPath(result, 'package.trackingNumber'));
    System.assertEquals('R0lGODlh', CarrierMappingService.getPath(result, 'label.encodedLabel'));
  }

  @IsTest
  static void createReturnLabelNormalizesReturnShipment() {
    Test.setMock(
      HttpCalloutMock.class,
      new UPSMock(
        200,
        shipmentResponseBody('1ZRET', '1ZRETPKG', 'UkVUVVJO', 'GIF'),
        '/shipments/v2403/ship'
      )
    );

    Test.startTest();
    Map<String, Object> result = new UPSCarrierAdapter()
      .createReturnLabel(minimalShipmentPayload());
    Test.stopTest();

    System.assertEquals('1ZRET', CarrierMappingService.getPath(result, 'returnShipment.trackingNumber'));
    System.assertEquals('UkVUVVJO', CarrierMappingService.getPath(result, 'returnShipment.encodedLabel'));
  }

  @IsTest
  static void generateLabelUsesFallbackTrackingAndNormalizesLabel() {
    Test.setMock(
      HttpCalloutMock.class,
      new UPSMock(
        200,
        '{"LabelRecoveryResponse":{"ShipmentIdentificationNumber":"SHIP123","LabelResults":{"LabelImage":{"GraphicImage":"TEFCRUw=","LabelImageFormat":{"Code":"GIF"}}}}}',
        '/labels/v1/recovery'
      )
    );

    Test.startTest();
    Map<String, Object> result = new UPSCarrierAdapter()
      .generateLabel(null, '1ZFALLBACK', null);
    Test.stopTest();

    System.assertEquals('1ZFALLBACK', CarrierMappingService.getPath(result, 'label.trackingNumber'));
    System.assertEquals('TEFCRUw=', CarrierMappingService.getPath(result, 'label.encodedLabel'));
  }

  @IsTest
  static void voidShipmentNormalizesConfirmation() {
    Test.setMock(
      HttpCalloutMock.class,
      new UPSMock(
        200,
        '{"VoidShipmentResponse":{"SummaryResult":{"Status":{"Code":"1"}}}}',
        '/shipments/v2403/void/cancel/SHIP123'
      )
    );

    Test.startTest();
    Map<String, Object> result = new UPSCarrierAdapter()
      .voidShipment('1ZTRACK', 'SHIP123');
    Test.stopTest();

    System.assertEquals('Voided', CarrierMappingService.getPath(result, 'void.status'));
    System.assertEquals('1', CarrierMappingService.getPath(result, 'void.confirmationNumber'));
  }

  @IsTest
  static void trackingNormalizesCurrentStatusAndEvents() {
    Test.setMock(
      HttpCalloutMock.class,
      new UPSMock(
        200,
        '{"trackResponse":{"shipment":[{"package":[{"currentStatus":{"code":"D","description":"Delivered","simplifiedTextDescription":"Delivered"},"activity":[{"date":"20260601","time":"123456","description":"Delivered"}]}]}]}}',
        '/track/v1/details/1ZTRACK'
      )
    );

    Test.startTest();
    Map<String, Object> result = new UPSCarrierAdapter()
      .syncTrackingStatus('1ZTRACK');
    Test.stopTest();

    System.assertEquals('Delivered', CarrierMappingService.getPath(result, 'tracking.latestStatus'));
    System.assertEquals(1, ((List<Object>) result.get('events')).size());
    System.assertEquals('2026-06-01T12:34:56Z', CarrierMappingService.getPath(result, 'events.0.timestamp'));
  }

  @IsTest
  static void httpFailureReportsUpsErrors() {
    Test.setMock(
      HttpCalloutMock.class,
      new UPSMock(
        400,
        '{"response":{"errors":[{"code":"BAD","message":"Invalid UPS payload"}]}}',
        '/rating/v2403/Shop'
      )
    );

    Boolean didThrow = false;
    Test.startTest();
    try {
      new UPSCarrierAdapter().getRateQuote(minimalShipmentPayload());
    } catch (Exception e) {
      didThrow = true;
    }
    Test.stopTest();
    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void blankIdentifiersAreRejectedBeforeCallout() {
    UPSCarrierAdapter adapter = new UPSCarrierAdapter();

    assertThrows(new LabelRecoveryCall(adapter));
    assertThrows(new VoidShipmentCall(adapter));
    assertThrows(new TrackingCall(adapter));
  }

  private interface ThrowingCall {
    void run();
  }

  private class LabelRecoveryCall implements ThrowingCall {
    private UPSCarrierAdapter adapter;
    LabelRecoveryCall(UPSCarrierAdapter adapter) {
      this.adapter = adapter;
    }
    public void run() {
      adapter.generateLabel(null, null, null);
    }
  }

  private class VoidShipmentCall implements ThrowingCall {
    private UPSCarrierAdapter adapter;
    VoidShipmentCall(UPSCarrierAdapter adapter) {
      this.adapter = adapter;
    }
    public void run() {
      adapter.voidShipment(null, null);
    }
  }

  private class TrackingCall implements ThrowingCall {
    private UPSCarrierAdapter adapter;
    TrackingCall(UPSCarrierAdapter adapter) {
      this.adapter = adapter;
    }
    public void run() {
      adapter.syncTrackingStatus(null);
    }
  }

  private static void assertThrows(ThrowingCall callToRun) {
    Boolean didThrow = false;
    try {
      callToRun.run();
    } catch (Exception e) {
      didThrow = true;
    }
    System.assertEquals(true, didThrow);
  }

  private static Connector_Config_Value__c configValue(
    Connector_Instance__c instanceRecord,
    String fieldKey,
    String value,
    Boolean isSecretReference
  ) {
    return new Connector_Config_Value__c(
      Name = 'ups:' + fieldKey,
      Connector_Instance__c = instanceRecord.Id,
      Connector_Key__c = 'ups',
      Field_Key__c = fieldKey,
      Value__c = value,
      Is_Secret_Reference__c = isSecretReference
    );
  }

  private static String shipmentResponseBody(String shipmentId, String packageTracking, String label, String imageType) {
    return '{"ShipmentResponse":{"ShipmentResults":{"ShipmentIdentificationNumber":"' + shipmentId + '",' +
      '"ShipmentCharges":{"TotalCharges":{"MonetaryValue":"22.50","CurrencyCode":"USD"}},' +
      '"PackageResults":{"TrackingNumber":"' + packageTracking + '","ShippingLabel":{"GraphicImage":"' + label + '","ImageFormat":{"Code":"' + imageType + '"}}}}}}';
  }

  private static Map<String, Object> minimalShipmentPayload() {
    return new Map<String, Object>{
      'ShipTo' => new Map<String, Object>{
        'Name' => 'Receiver',
        'Address' => new Map<String, Object>{
          'AddressLine' => new List<Object>{ '2 Dest St' },
          'City' => 'New York',
          'StateProvinceCode' => 'NY',
          'PostalCode' => '10001',
          'CountryCode' => 'US'
        }
      },
      'Package' => new Map<String, Object>{
        'PackageWeight' => new Map<String, Object>{ 'Weight' => '1' }
      }
    };
  }
}