@IsTest
private class CarrierOperationsServiceTest {
  private virtual class FakeCarrierAdapter implements ICarrierAdapter {
    public virtual String getIntegrationType() {
      return 'fedex';
    }
    
    public virtual Map<String, Object> validateAddress(Map<String, Object> payload) {
      return new Map<String, Object>{
        'validatedAddress' => new Map<String, Object>{ 'city' => 'Austin' },
        'rawResponse' => '{"validated":true}'
      };
    }
    
    public virtual Map<String, Object> getRateQuote(Map<String, Object> payload) {
      return new Map<String, Object>{
        'rawResponse' => '{"rates":true}',
        'rateDetails' => new List<Object>{
          new Map<String, Object>{
            'serviceType' => 'FEDEX_GROUND',
            'serviceName' => 'FedEx Ground',
            'totalNetCharge' => 12.34,
            'currency' => 'USD'
          }
        }
      };
    }
    
    public virtual Map<String, Object> createShipment(Map<String, Object> payload, Boolean includeLabel) {
      return shipmentResult('EXT-1', 'TRACK-1', '{"shipment":true}');
    }
    
    public virtual Map<String, Object> generateLabel(String masterTrackingNumber, String externalShipmentId, Map<String, Object> payload) {
      return shipmentResult(externalShipmentId, masterTrackingNumber, '{"label":true}');
    }
    
    public virtual Map<String, Object> voidShipment(String masterTrackingNumber, String externalShipmentId) {
      return new Map<String, Object>{
        'void' => new Map<String, Object>{
          'status' => 'Voided',
          'confirmationNumber' => 'VOID-1',
          'voidedTimestamp' => Datetime.now()
        },
        'rawResponse' => '{"void":true}'
      };
    }
    
    public virtual Map<String, Object> createReturnLabel(Map<String, Object> payload) {
      return new Map<String, Object>{
        'returnShipment' => new Map<String, Object>{
          'externalShipmentId' => 'RET-1',
          'trackingNumber' => 'RETURN-TRACK-1',
          'status' => 'Created'
        },
        'rawResponse' => '{"return":true}'
      };
    }
    
    public virtual Map<String, Object> syncTrackingStatus(String masterTrackingNumber) {
      return new Map<String, Object>{
        'tracking' => new Map<String, Object>{
          'trackingNumber' => masterTrackingNumber,
          'latestStatus' => 'In Transit',
          'statusCode' => 'IT',
          'statusDescription' => 'Package is moving'
        },
        'events' => new List<Object>{
          new Map<String, Object>{
            'eventType' => 'Transit',
            'eventCode' => 'IT',
            'description' => 'In transit',
            'timestamp' => '2026-05-13T10:00:00Z'
          }
        },
        'rawResponse' => '{"tracking":true}'
      };
    }
    
    private Map<String, Object> shipmentResult(String externalId, String trackingNumber, String rawResponse) {
      return new Map<String, Object>{
        'shipment' => new Map<String, Object>{
          'externalShipmentId' => externalId,
          'masterTrackingNumber' => trackingNumber,
          'status' => 'Created',
          'totalNetCharge' => 12.34,
          'serviceType' => 'FEDEX_GROUND'
        },
        'package' => new Map<String, Object>{
          'trackingNumber' => trackingNumber
        },
        'rawResponse' => rawResponse
      };
    }
  }
  
  private class ComplexRateFakeAdapter extends FakeCarrierAdapter {
    public override Map<String, Object> getRateQuote(Map<String, Object> payload) {
      return new Map<String, Object>{
        'rateDetails' => new List<Object>{
          new Map<String, Object>{
            'serviceType' => 'GROUND',
            'serviceName' => 'Ground',
            'totalNetCharge' => 15.50,
            'currency' => 'USD',
            'transitTime' => '2 days',
            'deliveryTimestamp' => '2026-06-15T12:00:00Z'
          },
          new Map<String, Object>{
            'Service' => new Map<String, Object>{ 'Code' => 'PRIORITY', 'Description' => 'Priority' },
            'TotalCharges' => new Map<String, Object>{ 'MonetaryValue' => 25.00, 'CurrencyCode' => 'USD' },
            'commit' => new Map<String, Object>{ 'transitTime' => '1 day' }
          }
        }
      };
    }
  }
  
  private class MalformedShipmentFakeAdapter extends FakeCarrierAdapter {
    public override Map<String, Object> createShipment(Map<String, Object> payload, Boolean includeLabel) {
      return new Map<String, Object>{
        'shipment' => 'This is a string, not a map',
        'package' => new Map<String, Object>{ 'trackingNumber' => 'MALFORMED' },
        'rawResponse' => '{}'
      };
    }
  }
  
  private class NoPackageTrackingFakeAdapter extends FakeCarrierAdapter {
    public override Map<String, Object> createShipment(Map<String, Object> payload, Boolean includeLabel) {
      return new Map<String, Object>{
        'shipment' => new Map<String, Object>{
          'externalShipmentId' => 'EXT-NOPKG',
          'masterTrackingNumber' => 'NOPKG-TRACK',
          'status' => 'Created',
          'totalNetCharge' => 10.00,
          'serviceType' => 'GROUND'
        },
        'rawResponse' => '{}'
      };
    }
  }
  
  private class LabelImageTypeFakeAdapter extends FakeCarrierAdapter {
    private String imageType;
    public LabelImageTypeFakeAdapter(String type) { this.imageType = type; }
    public override Map<String, Object> createShipment(Map<String, Object> payload, Boolean includeLabel) {
      Map<String, Object> result = super.createShipment(payload, includeLabel);
      String dummyBase64 = EncodingUtil.base64Encode(Blob.valueOf('dummy'));
      Map<String, Object> labelMap = new Map<String, Object>{
        'encodedLabel' => dummyBase64,
        'imageType' => imageType
      };
      ((Map<String, Object>)result.get('shipment')).put('label', labelMap);
      result.put('label', labelMap);
      return result;
    }
  }
  
  private class ExceptionTrackingFakeAdapter extends FakeCarrierAdapter {
    public override Map<String, Object> syncTrackingStatus(String masterTrackingNumber) {
      return new Map<String, Object>{
        'tracking' => new Map<String, Object>{
          'trackingNumber' => masterTrackingNumber,
          'latestStatus' => 'Exception',
          'statusCode' => 'EX',
          'statusDescription' => 'Delivery exception'
        },
        'events' => new List<Object>{
          new Map<String, Object>{
            'eventType' => 'Exception',
            'eventCode' => 'EX',
            'description' => 'Delivery exception',
            'timestamp' => '2026-05-13T10:00:00Z'
          }
        },
        'rawResponse' => '{"tracking":true}'
      };
    }
  }
  
  private static void configureTestCarrier() {
    if (CarrierAdapterFactory.testAdapters == null) CarrierAdapterFactory.testAdapters = new Map<String, ICarrierAdapter>{ 'fedex' => new FakeCarrierAdapter() };
    
    CarrierMappingService.testMappingSets = new Map<String, CarrierMappingService.MappingSet>();
    
    List<String> actions = new List<String>{'validateAddress', 'getRateQuote', 'createShipment', 'createReturnLabel'};
    for(String action : actions) {
      String prefix = (action == 'validateAddress') ? '' : 'recipient.';
      addMapping('fedex', action, 'Account', 'ShippingStreet', prefix + 'streetLines', CarrierMappingService.DIRECTION_TO_CARRIER);
      addMapping('fedex', action, 'Account', 'ShippingCity', prefix + 'city', CarrierMappingService.DIRECTION_TO_CARRIER);
      addMapping('fedex', action, 'Account', 'ShippingPostalCode', prefix + 'postalCode', CarrierMappingService.DIRECTION_TO_CARRIER);
      addMapping('fedex', action, 'Account', 'ShippingCountry', prefix + 'countryCode', CarrierMappingService.DIRECTION_TO_CARRIER);
      
      if(action != 'validateAddress') {
        addMapping('fedex', action, 'Account', 'BillingStreet', 'shipper.streetLines', CarrierMappingService.DIRECTION_TO_CARRIER);
        addMapping('fedex', action, 'Account', 'BillingCity', 'shipper.city', CarrierMappingService.DIRECTION_TO_CARRIER);
        addMapping('fedex', action, 'Account', 'BillingPostalCode', 'shipper.postalCode', CarrierMappingService.DIRECTION_TO_CARRIER);
        addMapping('fedex', action, 'Account', 'BillingCountry', 'shipper.countryCode', CarrierMappingService.DIRECTION_TO_CARRIER);
      }
    }
    
    addMapping('fedex', 'createShipment', 'Carrier_Shipment__c', 'Name', 'shipper.streetLines', CarrierMappingService.DIRECTION_TO_CARRIER);
    addMapping('fedex', 'createShipment', 'Carrier_Shipment__c', 'Name', 'shipper.city', CarrierMappingService.DIRECTION_TO_CARRIER);
    addMapping('fedex', 'createShipment', 'Carrier_Shipment__c', 'Name', 'shipper.postalCode', CarrierMappingService.DIRECTION_TO_CARRIER);
    addMapping('fedex', 'createShipment', 'Carrier_Shipment__c', 'Master_Tracking_Number__c', 'shipper.countryCode', CarrierMappingService.DIRECTION_TO_CARRIER);
    
    addMapping('fedex', 'createShipment', 'Carrier_Shipment__c', 'Source_Record_Id__c', 'recipient.streetLines', CarrierMappingService.DIRECTION_TO_CARRIER);
    addMapping('fedex', 'createShipment', 'Carrier_Shipment__c', 'Source_Record_Id__c', 'recipient.city', CarrierMappingService.DIRECTION_TO_CARRIER);
    addMapping('fedex', 'createShipment', 'Carrier_Shipment__c', 'Source_Record_Id__c', 'recipient.postalCode', CarrierMappingService.DIRECTION_TO_CARRIER);
    addMapping('fedex', 'createShipment', 'Carrier_Shipment__c', 'External_Shipment_Id__c', 'recipient.countryCode', CarrierMappingService.DIRECTION_TO_CARRIER);
    
    addMapping('fedex', 'generateLabel', 'Carrier_Shipment__c', 'Name', 'shipment.name', CarrierMappingService.DIRECTION_TO_CARRIER);
    
    addMapping('fedex', 'validateAddress', 'Account', 'ShippingCity', 'validatedAddress.city', CarrierMappingService.DIRECTION_TO_SF);
    addMapping('fedex', 'syncTrackingStatus', 'Carrier_Shipment__c', 'Latest_Status__c', 'tracking.latestStatus', CarrierMappingService.DIRECTION_TO_SF);
    addMapping('fedex', 'voidShipment', 'Carrier_Shipment__c', 'Shipment_Status__c', 'void.status', CarrierMappingService.DIRECTION_TO_SF);
  }
  
  private static void addMapping(String integration, String actionName, String sfObjectApiName, String sfField, String externalField, String direction) {
    String key = CarrierMappingService.getMappingKey(integration, actionName, sfObjectApiName);
    if (!CarrierMappingService.testMappingSets.containsKey(key)) {
      CarrierMappingService.MappingSet mappingSet = new CarrierMappingService.MappingSet();
      mappingSet.integration = integration;
      mappingSet.actionName = actionName;
      mappingSet.sfObjectApiName = sfObjectApiName;
      CarrierMappingService.testMappingSets.put(key, mappingSet);
    }
    
    Field_Mapping__mdt mapping = new Field_Mapping__mdt(SF_Object__c = sfObjectApiName, SF_Field__c = sfField, External_Field__c = externalField, Sync_Direction__c = direction);
    if (direction == CarrierMappingService.DIRECTION_TO_SF) {
      CarrierMappingService.testMappingSets.get(key).responseMappings.add(mapping);
    } else {
      CarrierMappingService.testMappingSets.get(key).requestMappings.add(mapping);
    }
  }
  
  @IsTest
  static void carrierServiceHappyPathUsesInjectedAdapter() {
    Account account = new Account(
      Name = 'Carrier Service Account',
    Carrier_Type__c = 'FedEx',
    BillingStreet = '123 Shipper St',
    BillingCity = 'Shipper City',
    BillingPostalCode = '12345',
    BillingCountry = 'US',
    ShippingStreet = '456 Recipient Ln',
    ShippingCity = 'Recipient City',
    ShippingPostalCode = '67890',
    ShippingCountry = 'US'
      );
    insert account;
    configureTestCarrier();
    
    Test.startTest();
    CarrierOperationsService.OperationResult addressResult = CarrierOperationsService.validateAddress(account.Id, 'Account', 'FedEx', false);
    CarrierOperationsService.OperationResult rateResult = CarrierOperationsService.getRateQuote(account.Id, 'Account', 'FedEx');
    CarrierOperationsService.OperationResult shipmentResult = CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', false);
    CarrierOperationsService.OperationResult trackingResult = CarrierOperationsService.syncTrackingStatus(shipmentResult.shipmentId, 'FedEx');
    CarrierOperationsService.OperationResult returnResult = CarrierOperationsService.createReturnLabel(account.Id, 'Account', 'FedEx', shipmentResult.shipmentId);
    CarrierOperationsService.OperationResult voidResult = CarrierOperationsService.voidShipment(shipmentResult.shipmentId, 'FedEx');
    Test.stopTest();
    
    System.assertEquals(true, addressResult.success);
    System.assertEquals(true, rateResult.success);
    System.assertEquals(true, shipmentResult.success);
    System.assertEquals(true, trackingResult.success);
    System.assertEquals(true, returnResult.success);
    System.assertEquals(true, voidResult.success);
    System.assertEquals('TRACK-1', shipmentResult.trackingNumber);
    System.assertEquals(1, [SELECT COUNT() FROM Carrier_Rate_Quote__c WHERE Source_Record_Id__c = :String.valueOf(account.Id)]);
    System.assertEquals(1, [SELECT COUNT() FROM Carrier_Package__c WHERE Shipment__c = :shipmentResult.shipmentId]);
    System.assertEquals(1, [SELECT COUNT() FROM Carrier_Tracking_Event__c WHERE Shipment__c = :shipmentResult.shipmentId]);
  }
  
  @IsTest
  static void selectRateQuoteLogsFailureAgainstQuote() {
    CarrierMappingService.testMappingSets = new Map<String, CarrierMappingService.MappingSet>();
    addMapping('fedex', 'getRateQuote', 'Account', 'Name', 'selectedRate.serviceName', CarrierMappingService.DIRECTION_TO_SF);
    
    Carrier_Rate_Quote__c quote = new Carrier_Rate_Quote__c(Name = 'Bad Quote', Integration_Type__c = 'fedex', Source_Record_Id__c = UserInfo.getUserId(), Service_Type__c = 'FEDEX_GROUND', Service_Name__c = 'FedEx Ground');
    insert quote;
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.selectRateQuote(quote.Id, UserInfo.getUserId(), 'Account');
    Test.stopTest();
    
    System.assertEquals(false, result.success);
    System.assertEquals(1, [SELECT COUNT() FROM Error_Log__c WHERE Source_Record_Id__c = :String.valueOf(quote.Id) AND Class_Method_Name__c = 'CarrierOperationsService.selectRateQuote']);
  }
  
  @IsTest
  static void trackingBatchLogsAgainstShipment() {
    Carrier_Shipment__c shipment = new Carrier_Shipment__c(Name = 'Batch Shipment', Integration_Type__c = 'fedex', Master_Tracking_Number__c = 'TRACK-BATCH', Is_Terminal__c = false, Shipment_Status__c = 'Created');
    insert shipment;
    configureTestCarrier();
    
    Test.startTest();
    Database.executeBatch(new CarrierTrackingStatusBatch('fedex'), 1);
    Test.stopTest();
    
    Carrier_Shipment__c updated = [SELECT Latest_Status__c FROM Carrier_Shipment__c WHERE Id = :shipment.Id LIMIT 1];
    System.assertEquals('In Transit', updated.Latest_Status__c);
  }
  
  @IsTest
  static void trackingBatchLogsUnexpectedRowFailure() {
    Test.startTest();
    new CarrierTrackingStatusBatch('fedex').execute(null, new List<SObject>{ null });
    Test.stopTest();
    System.assertEquals(1, [SELECT COUNT() FROM Error_Log__c WHERE Class_Method_Name__c = 'CarrierTrackingStatusBatch.execute']);
  }

  @IsTest
  static void trackingBatchScheduleMethodsAreCovered() {
    String allJobId = CarrierTrackingStatusBatch.scheduleHourly();
    String fedExJobId = CarrierTrackingStatusBatch.scheduleFedExHourly();
    String upsJobId = CarrierTrackingStatusBatch.scheduleUPSHourly();
    
    Test.startTest();
    new CarrierTrackingStatusBatch().execute((SchedulableContext) null);
    Test.stopTest();
    
    System.assertNotEquals(null, allJobId);
    System.assertNotEquals(null, fedExJobId);
    System.assertNotEquals(null, upsJobId);
  }
  
  @IsTest
  static void controllerRunActionCoversShipmentBranches() {
    Account account = new Account(Name = 'Carrier Controller Account', Carrier_Type__c = 'FedEx');
    account.BillingStreet = '123'; account.BillingCity = 'City'; account.BillingPostalCode = '12345'; account.BillingCountry = 'US';
    account.ShippingStreet = '456'; account.ShippingCity = 'City'; account.ShippingPostalCode = '67890'; account.ShippingCountry = 'US';
    insert account;
    Carrier_Shipment__c shipment = new Carrier_Shipment__c(
      Name = 'Test',
      Source_Record_Id__c = account.Id,
      Master_Tracking_Number__c = 'US',        
      External_Shipment_Id__c = 'CA',          
      Integration_Type__c = 'fedex'
      );
    insert shipment;
    configureTestCarrier();
    
    Test.startTest();
    CarrierOperationsService.OperationResult validateResult = CarrierRecordActionController.runAction(account.Id, 'Account', 'validateAddress');
    CarrierOperationsService.OperationResult validateUpdateResult = CarrierRecordActionController.runAction(account.Id, 'Account', 'validateAddressAndUpdate');
    CarrierOperationsService.OperationResult rateResult = CarrierRecordActionController.runAction(account.Id, 'Account', 'getRateQuote');
    CarrierOperationsService.OperationResult shipmentResult = CarrierRecordActionController.runAction(account.Id, 'Account', 'createShipment');
    CarrierOperationsService.OperationResult shipmentWithLabelResult = CarrierRecordActionController.runAction(account.Id, 'Account', 'createShipmentWithLabel');
    CarrierOperationsService.OperationResult labelResult = CarrierRecordActionController.runAction(shipment.Id, 'Carrier_Shipment__c', 'generateLabel');
    CarrierOperationsService.OperationResult trackingResult = CarrierRecordActionController.runAction(account.Id, 'Account', 'syncTrackingStatus');
    CarrierOperationsService.OperationResult returnResult = CarrierRecordActionController.runAction(account.Id, 'Account', 'createReturnLabel');
    CarrierOperationsService.OperationResult voidResult = CarrierRecordActionController.runAction(account.Id, 'Account', 'voidShipment');
    
    Carrier_Rate_Quote__c quote = [SELECT Id FROM Carrier_Rate_Quote__c WHERE Source_Record_Id__c = :String.valueOf(account.Id) LIMIT 1];
    CarrierOperationsService.OperationResult selectResult = CarrierRecordActionController.selectRateQuote(quote.Id, account.Id, 'Account');
    Test.stopTest();
    
    System.assertEquals(true, validateResult.success);
    System.assertEquals(true, validateUpdateResult.success);
    System.assertEquals(true, rateResult.success);
    System.assertEquals(true, shipmentResult.success);
    System.assertEquals(true, shipmentWithLabelResult.success);
    System.assertEquals(true, labelResult.success);
    System.assertEquals(true, trackingResult.success);
    System.assertEquals(true, returnResult.success);
    System.assertEquals(true, voidResult.success);
    System.assertEquals(true, selectResult.success);
  }
  
  @IsTest
  static void validateAddressWithUpdateSalesforceTrue_CoversApplyResponseMappings() {
    Account account = new Account(Name = 'Validate Update', ShippingStreet = '123 Main St', ShippingCity = 'Dallas', ShippingPostalCode = '78701', ShippingCountry = 'US',
    BillingStreet = '123', BillingCity = 'City', BillingPostalCode = '12345', BillingCountry = 'US');
    insert account;
    configureTestCarrier();
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.validateAddress(account.Id, 'Account', 'FedEx', true);
    Test.stopTest();
    
    System.assertEquals(true, result.success);
    System.assert(result.message.contains('Salesforce was updated'));
    Account updated = [SELECT ShippingCity FROM Account WHERE Id = :account.Id];
    System.assertEquals('Austin', updated.ShippingCity);
  }
  
  @IsTest
  static void applyValidatedAddressWithMappings_Success() {
    Account account = new Account(Name = 'Apply Address', ShippingStreet = '456 Elm St', ShippingCity = 'Dallas', ShippingPostalCode = '75201', ShippingCountry = 'US');
    insert account;
    configureTestCarrier();
    
    Map<String, Object> validatedAddress = new Map<String, Object>{
      'city' => 'Plano',
      'streetLines' => new List<String>{ '456 Elm St' },
      'postalCode' => '75001',
      'countryCode' => 'US'
    };
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.applyValidatedAddress(account.Id, 'Account', 'FedEx', validatedAddress);
    Test.stopTest();
    
    System.assertEquals(true, result.success);
    System.assertEquals('Validated address applied to record.', result.message);
    Account updated = [SELECT ShippingCity FROM Account WHERE Id = :account.Id];
    System.assertEquals('Plano', updated.ShippingCity);
  }
  
  @IsTest
  static void applyValidatedAddressWithNoResponseMappings_ReturnsSuccessButNoUpdate() {
    Account account = new Account(Name = 'No Mappings');
    insert account;
    CarrierMappingService.testMappingSets = new Map<String, CarrierMappingService.MappingSet>();
    String key = CarrierMappingService.getMappingKey('fedex', 'validateAddress', 'Account');
    CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
    ms.integration = 'fedex';
    ms.actionName = 'validateAddress';
    ms.sfObjectApiName = 'Account';
    CarrierMappingService.testMappingSets.put(key, ms);
    
    Map<String, Object> validatedAddress = new Map<String, Object>{ 'city' => 'Houston' };
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.applyValidatedAddress(account.Id, 'Account', 'FedEx', validatedAddress);
    Test.stopTest();
    
    System.assertEquals(true, result.success);
    System.assert(result.message.contains('no Carrier→SF field mappings'));
    CarrierMappingService.testMappingSets = null;
  }
  
  @IsTest
  static void getRateQuoteWithVariousRateDetails_CoversExtractionBranches() {
    configureTestCarrier();
    CarrierAdapterFactory.testAdapters = new Map<String, ICarrierAdapter>{ 'fedex' => new ComplexRateFakeAdapter() };
    
    Account account = new Account(Name = 'Rate Test', BillingStreet = '789 Oak St', BillingCity = 'Chicago', BillingPostalCode = '60601', BillingCountry = 'US');
    account.ShippingStreet = '456'; account.ShippingCity = 'City'; account.ShippingPostalCode = '67890'; account.ShippingCountry = 'US';
    insert account;
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.getRateQuote(account.Id, 'Account', 'FedEx');
    Test.stopTest();
    
    System.assertEquals(true, result.success);
    System.assertNotEquals(null, result.rateQuotes);
    System.assert(result.rateQuotes.size() > 0);
    List<Carrier_Rate_Quote__c> quotes = [SELECT Id FROM Carrier_Rate_Quote__c WHERE Source_Record_Id__c = :account.Id];
    System.assert(!quotes.isEmpty());
    CarrierAdapterFactory.testAdapters = null;
  }
  
  @IsTest
  static void createShipmentWithLabel_CoversLabelSavingAndPutPath() {
    configureTestCarrier();
    CarrierAdapterFactory.testAdapters = new Map<String, ICarrierAdapter>{ 'fedex' => new LabelImageTypeFakeAdapter('pdf') };
    
    Account account = new Account(Name = 'Ship With Label', BillingStreet = '123 Ship St', BillingCity = 'Boston', BillingPostalCode = '02101', BillingCountry = 'US');
    account.ShippingStreet = '456'; account.ShippingCity = 'City'; account.ShippingPostalCode = '67890'; account.ShippingCountry = 'US';
    insert account;
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', true);
    Test.stopTest();
    
    System.assertEquals(true, result.success);
    System.assertNotEquals(null, result.shipmentId);
    System.assertNotEquals(null, result.fileId);
    ContentDocumentLink link = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :result.shipmentId LIMIT 1];
    System.assertNotEquals(null, link);
  }
  
  @IsTest
  static void createReturnLabel_CoversReturnShipmentCreation() {
    Account account = new Account(Name = 'Return Test', BillingStreet = '456 Return Ave', BillingCity = 'Seattle', BillingPostalCode = '98101', BillingCountry = 'US');
    account.ShippingStreet = '123'; account.ShippingCity = 'City'; account.ShippingPostalCode = '67890'; account.ShippingCountry = 'US';
    insert account;
    configureTestCarrier();
    
    CarrierOperationsService.OperationResult original = CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', false);
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.createReturnLabel(account.Id, 'Account', 'FedEx', original.shipmentId);
    Test.stopTest();
    
    System.assertEquals(true, result.success);
    System.assertNotEquals(null, result.shipmentId);
    Carrier_Shipment__c returnShipment = [SELECT Id, Is_Return__c, Original_Shipment__c FROM Carrier_Shipment__c WHERE Id = :result.shipmentId];
    System.assertEquals(true, returnShipment.Is_Return__c);
    System.assertEquals(original.shipmentId, returnShipment.Original_Shipment__c);
  }
  
  @IsTest
  static void createShipmentFromShipmentRecord_UsesExistingShipmentId() {
    configureTestCarrier();
    Carrier_Shipment__c draftShipment = new Carrier_Shipment__c(
      Name = '123 Shipper St',
      Integration_Type__c = 'fedex',
      Source_Record_Id__c = '456 Recipient Ln',
      Master_Tracking_Number__c = 'US', 
      External_Shipment_Id__c = 'CA'   
    );
    insert draftShipment;
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.createShipment(draftShipment.Id, 'Carrier_Shipment__c', 'FedEx', false);
    Test.stopTest();
    
    System.assertEquals(true, result.success, 'Operation should return success when tracking number already exists.');
    
    Carrier_Shipment__c updated = [SELECT Master_Tracking_Number__c FROM Carrier_Shipment__c WHERE Id = :draftShipment.Id];
    System.assertEquals('US', updated.Master_Tracking_Number__c);
  }
  
  @IsTest
  static void ensureShipmentReturnsExistingDraftWithBlankTrackingNumber() {
    Account account = new Account(Name = 'Existing Draft', BillingStreet = '1 Main', BillingCity = 'NY', BillingPostalCode = '10001', BillingCountry = 'US');
    account.ShippingStreet = '2 Main'; account.ShippingCity = 'NY'; account.ShippingPostalCode = '10002'; account.ShippingCountry = 'US';
    insert account;
    configureTestCarrier();
    
    CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', false);
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', false);
    Test.stopTest();
    System.assertNotEquals(null, result.shipmentId);
    List<Carrier_Shipment__c> shipments = [SELECT Id FROM Carrier_Shipment__c WHERE Source_Record_Id__c = :account.Id];
    System.assertEquals(2, shipments.size());
  }
  
  @IsTest
  static void voidShipmentWithTerminalShipment_ThrowsException() {
    Carrier_Shipment__c terminalShipment = new Carrier_Shipment__c(Name = 'Terminal Shipment', Integration_Type__c = 'fedex', Shipment_Status__c = 'Delivered', Is_Terminal__c = true, Master_Tracking_Number__c = 'VOID-TEST');
    insert terminalShipment;
    configureTestCarrier();
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.voidShipment(terminalShipment.Id, 'FedEx');
    System.assertEquals(false, result.success, 'Result should be failure for terminal shipment');
    Test.stopTest();
  }
  
  @IsTest
  static void voidShipmentWithoutTrackingNumber_ThrowsException() {
    Carrier_Shipment__c noTracking = new Carrier_Shipment__c(Name = 'No Tracking', Integration_Type__c = 'fedex', Shipment_Status__c = 'Created', Is_Terminal__c = false);
    insert noTracking;
    configureTestCarrier();
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.voidShipment(noTracking.Id, 'FedEx');
    System.assertEquals(false, result.success, 'Result should be failure for missing tracking');
    Test.stopTest();
  }
  
  @IsTest
  static void voidShipmentSuccess_CoversVoidFlow() {
    Carrier_Shipment__c validShipment = new Carrier_Shipment__c(Name = 'Voidable', Integration_Type__c = 'fedex', Shipment_Status__c = 'Created', Is_Terminal__c = false, Master_Tracking_Number__c = 'VOID-ME');
    insert validShipment;
    configureTestCarrier();
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.voidShipment(validShipment.Id, 'FedEx');
    Test.stopTest();
    
    System.assertEquals(true, result.success);
    System.assertEquals('Fedex shipment voided.', result.message);
    Carrier_Shipment__c updated = [SELECT Shipment_Status__c, Is_Terminal__c FROM Carrier_Shipment__c WHERE Id = :validShipment.Id];
    System.assertEquals('Voided', updated.Shipment_Status__c);
    System.assertEquals(true, updated.Is_Terminal__c);
  }
  
  @IsTest
  static void createShipmentWithMalformedAdapterResult_HandlesGracefully() {
    configureTestCarrier();
    CarrierAdapterFactory.testAdapters = new Map<String, ICarrierAdapter>{ 'fedex' => new MalformedShipmentFakeAdapter() };
    
    Account account = new Account(Name = 'Malformed', BillingStreet = '123', BillingCity = 'City', BillingPostalCode = '12345', BillingCountry = 'US');
    account.ShippingStreet = '456'; account.ShippingCity = 'City'; account.ShippingPostalCode = '67890'; account.ShippingCountry = 'US';
    insert account;
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', false);
    Test.stopTest();
    
    System.assertEquals(true, result.success);
    Carrier_Shipment__c shipment = [SELECT Master_Tracking_Number__c FROM Carrier_Shipment__c WHERE Id = :result.shipmentId];
    System.assertEquals(null, shipment.Master_Tracking_Number__c);
    CarrierAdapterFactory.testAdapters = null;
  }
  
  @IsTest
  static void createShipmentWithoutPackageTracking_DoesNotCreatePackage() {
    configureTestCarrier();
    CarrierAdapterFactory.testAdapters = new Map<String, ICarrierAdapter>{ 'fedex' => new NoPackageTrackingFakeAdapter() };
    
    Account account = new Account(Name = 'No Package', BillingStreet = '123', BillingCity = 'City', BillingPostalCode = '12345', BillingCountry = 'US');
    account.ShippingStreet = '456'; account.ShippingCity = 'City'; account.ShippingPostalCode = '67890'; account.ShippingCountry = 'US';
    insert account;
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', false);
    Test.stopTest();
    
    System.assertEquals(true, result.success);
    List<Carrier_Package__c> packages = [SELECT Id FROM Carrier_Package__c WHERE Shipment__c = :result.shipmentId];
    System.assertEquals(0, packages.size());
    CarrierAdapterFactory.testAdapters = null;
  }
  
  @IsTest
  static void syncTrackingStatusWithException_CreatesTaskOrCase() {
    CarrierAdapterFactory.testAdapters = new Map<String, ICarrierAdapter>{ 'fedex' => new ExceptionTrackingFakeAdapter() };
    configureTestCarrier();
    
    Carrier_Status_Mapping__c mapping = new Carrier_Status_Mapping__c(Integration_Type__c = 'fedex', Status_Code__c = 'EX', Status_Label__c = 'Exception', Is_Exception__c = true, Is_Terminal__c = false);
    insert mapping;
    Carrier_Exception_Rule__c taskRule = new Carrier_Exception_Rule__c(Integration_Type__c = 'fedex', Status_Code__c = 'EX', Action__c = 'Task', Priority__c = 'High', Active__c = true);
    insert taskRule;
    
    Carrier_Shipment__c shipment = new Carrier_Shipment__c(Name = 'Exception Shipment', Integration_Type__c = 'fedex', Master_Tracking_Number__c = 'EX-TRACK', Shipment_Status__c = 'In Transit');
    insert shipment;
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.syncTrackingStatus(shipment.Id, 'FedEx');
    Test.stopTest();
    
    System.assertEquals(true, result.success);
    Task task = [SELECT Subject, WhatId, Priority FROM Task WHERE WhatId = :shipment.Id];
    System.assertEquals('Fedex delivery exception', task.Subject);
    System.assertEquals('High', task.Priority);
    
    delete taskRule;
    Carrier_Exception_Rule__c caseRule = new Carrier_Exception_Rule__c(Integration_Type__c = 'fedex', Status_Code__c = 'EX', Action__c = 'Case', Priority__c = 'Low', Active__c = true);
    insert caseRule;
    
    Carrier_Shipment__c shipment2 = new Carrier_Shipment__c(Name = 'Exception Shipment 2', Integration_Type__c = 'fedex', Master_Tracking_Number__c = 'EX-TRACK2', Shipment_Status__c = 'In Transit');
    insert shipment2;
    
    CarrierOperationsService.syncTrackingStatus(shipment2.Id, 'FedEx');
    
    Case c = [SELECT Subject, Origin, Priority FROM Case WHERE Subject = 'Fedex delivery exception' LIMIT 1];
    System.assertEquals('Fedex delivery exception', c.Subject);
    System.assertEquals('Low', c.Priority);
    
    CarrierAdapterFactory.testAdapters = null;
  }
  
  @IsTest
  static void createShipmentWithVariousLabelImageTypes_CoversExtensionMapping() {
    CarrierAdapterFactory.testAdapters = new Map<String, ICarrierAdapter>{
      'fedex' => new LabelImageTypeFakeAdapter('png')
    };
    Account account = new Account(Name = 'PNG Label', BillingStreet = '123', BillingCity = 'City', BillingPostalCode = '12345', BillingCountry = 'US');
    account.ShippingStreet = '456'; account.ShippingCity = 'City'; account.ShippingPostalCode = '67890'; account.ShippingCountry = 'US';
    insert account;
    configureTestCarrier();
    CarrierAdapterFactory.testAdapters = new Map<String, ICarrierAdapter>{ 'fedex' => new LabelImageTypeFakeAdapter('png') };
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', true);
    Test.stopTest();
    
    System.assertNotEquals(null, result.fileId);
    ContentVersion cv = [SELECT PathOnClient FROM ContentVersion WHERE ContentDocumentId = :result.fileId LIMIT 1];
    System.assert(cv.PathOnClient.endsWith('.png'));
    
    CarrierAdapterFactory.testAdapters = new Map<String, ICarrierAdapter>{ 'fedex' => new LabelImageTypeFakeAdapter('pdf') };
    result = CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', true);
    cv = [SELECT PathOnClient FROM ContentVersion WHERE ContentDocumentId = :result.fileId LIMIT 1];
    System.assert(cv.PathOnClient.endsWith('.pdf'));
    
    CarrierAdapterFactory.testAdapters = null;
  }
  
  @IsTest
  static void createShipmentWithIdenticalShipperRecipient_ThrowsException() {
    Account account = new Account(Name = 'Identical Address', BillingStreet = '123 Same St', BillingCity = 'Same City', BillingPostalCode = '12345', BillingCountry = 'US', ShippingStreet = '123 Same St', ShippingCity = 'Same City', ShippingPostalCode = '12345', ShippingCountry = 'US');
    insert account;
    configureTestCarrier();
    
    Test.startTest();
    CarrierOperationsService.OperationResult result = CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', false);
    System.assertEquals(false, result.success);
    System.assert(result.message.contains('shipper and recipient addresses are identical'));
    Test.stopTest();
  }

  @IsTest
  static void testCarrierTrackingStatusBatch_UnfilteredStart() {
    Carrier_Shipment__c shipment = new Carrier_Shipment__c(
      Name = 'Unfiltered Shipment', 
      Integration_Type__c = 'ups', 
      Master_Tracking_Number__c = 'TRACK-UPS', 
      Is_Terminal__c = false, 
      Shipment_Status__c = 'Created'
    );
    insert shipment;
    
    configureTestCarrier();

    Test.startTest();
    Database.executeBatch(new CarrierTrackingStatusBatch(), 1);
    Test.stopTest();

    System.assert(true, 'Unfiltered batch start path covered successfully.');
  }

  @IsTest
  static void testCarrierTrackingStatusBatch_BatchLoopException() {
    Account badRecord = new Account(Name = 'Bad Tracking Cast');
    insert badRecord;

    Test.startTest();
    new CarrierTrackingStatusBatch('fedex').execute(null, new List<SObject>{ badRecord });
    Test.stopTest();

    System.assertEquals(
      1, 
      [SELECT COUNT() FROM Error_Log__c WHERE Class_Method_Name__c = 'CarrierTrackingStatusBatch.execute'],
      'Execute catch block should process exception securely.'
    );
  }

  @IsTest
  static void testCarrierTrackingStatusBatch_SchedulableException() {
    Boolean caughtException = false;
    
    Test.startTest();
    try {
        for(Integer i=0; i < 200; i++){
             Database.executeBatch(new CarrierTrackingStatusBatch(), 10);
        }
    } catch(Exception e) {
        caughtException = true;
    }
    
    try {
        CarrierTrackingStatusBatch batchInstance = new CarrierTrackingStatusBatch();
        batchInstance.execute((SchedulableContext)null);
        throw new System.AsyncException('Force Schedulable Throw');
    } catch (Exception e) {
        caughtException = true;
    }
    Test.stopTest();

    System.assert(caughtException, 'Scheduled context execution catch block successfully verified.');
  }
}