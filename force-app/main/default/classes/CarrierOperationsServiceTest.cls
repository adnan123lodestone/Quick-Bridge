@IsTest
private class CarrierOperationsServiceTest {
    private class FakeCarrierAdapter implements ICarrierAdapter {
        public String getIntegrationType() {
            return 'fedex';
        }

        public Map<String, Object> validateAddress(Map<String, Object> payload) {
            return new Map<String, Object>{
                'validatedAddress' => new Map<String, Object>{ 'city' => 'Austin' },
                'rawResponse' => '{"validated":true}'
            };
        }

        public Map<String, Object> getRateQuote(Map<String, Object> payload) {
            return new Map<String, Object>{
                'rawResponse' => '{"rates":true}',
                'rateDetails' => new List<Object>{
                    new Map<String, Object>{
                        'serviceType' => 'FEDEX_GROUND',
                        'serviceName' => 'FedEx Ground',
                        'ratedShipmentDetails' => new List<Object>{
                            new Map<String, Object>{
                                'shipmentRateDetail' => new Map<String, Object>{
                                    'totalNetCharge' => new Map<String, Object>{
                                        'amount' => 12.34,
                                        'currency' => 'USD'
                                    }
                                }
                            }
                        }
                    }
                }
            };
        }

        public Map<String, Object> createShipment(Map<String, Object> payload, Boolean includeLabel) {
            return shipmentResult('EXT-1', 'TRACK-1', '{"shipment":true}');
        }

        public Map<String, Object> generateLabel(String masterTrackingNumber, String externalShipmentId, Map<String, Object> payload) {
            return shipmentResult(externalShipmentId, masterTrackingNumber, '{"label":true}');
        }

        public Map<String, Object> voidShipment(String masterTrackingNumber, String externalShipmentId) {
            return new Map<String, Object>{
                'void' => new Map<String, Object>{
                    'status' => 'Voided',
                    'confirmationNumber' => 'VOID-1',
                    'voidedTimestamp' => Datetime.now()
                },
                'rawResponse' => '{"void":true}'
            };
        }

        public Map<String, Object> createReturnLabel(Map<String, Object> payload) {
            return new Map<String, Object>{
                'returnShipment' => new Map<String, Object>{
                    'externalShipmentId' => 'RET-1',
                    'trackingNumber' => 'RETURN-TRACK-1',
                    'status' => 'Created'
                },
                'rawResponse' => '{"return":true}'
            };
        }

        public Map<String, Object> syncTrackingStatus(String masterTrackingNumber) {
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
                'package' => new Map<String, Object>{ 'trackingNumber' => trackingNumber },
                'rawResponse' => rawResponse
            };
        }
    }

    @IsTest
    static void carrierServiceHappyPathUsesInjectedAdapter() {
        Account account = new Account(Name = 'Carrier Service Account', Carrier_Type__c = 'FedEx');
        insert account;
        configureTestCarrier();

        Test.startTest();
        CarrierOperationsService.OperationResult addressResult =
            CarrierOperationsService.validateAddress(account.Id, 'Account', 'FedEx', false);
        CarrierOperationsService.OperationResult rateResult =
            CarrierOperationsService.getRateQuote(account.Id, 'Account', 'FedEx');
        CarrierOperationsService.OperationResult shipmentResult =
            CarrierOperationsService.createShipment(account.Id, 'Account', 'FedEx', false);
        CarrierOperationsService.OperationResult trackingResult =
            CarrierOperationsService.syncTrackingStatus(shipmentResult.shipmentId, 'FedEx');
        CarrierOperationsService.OperationResult returnResult =
            CarrierOperationsService.createReturnLabel(account.Id, 'Account', 'FedEx', shipmentResult.shipmentId);
        CarrierOperationsService.OperationResult voidResult =
            CarrierOperationsService.voidShipment(shipmentResult.shipmentId, 'FedEx');
        Test.stopTest();

        System.assertEquals(true, addressResult.success);
        System.assertEquals(true, rateResult.success);
        System.assertEquals(true, shipmentResult.success);
        System.assertEquals(true, trackingResult.success);
        System.assertEquals(true, returnResult.success);
        System.assertEquals(true, voidResult.success);
        System.assertEquals('TRACK-1', shipmentResult.trackingNumber);
        System.assertEquals(1, [SELECT Count() FROM Carrier_Rate_Quote__c WHERE Source_Record_Id__c = :String.valueOf(account.Id)]);
        System.assertEquals(1, [SELECT Count() FROM Carrier_Package__c WHERE Shipment__c = :shipmentResult.shipmentId]);
        System.assertEquals(1, [SELECT Count() FROM Carrier_Tracking_Event__c WHERE Shipment__c = :shipmentResult.shipmentId]);
    }

    @IsTest
    static void selectRateQuoteLogsFailureAgainstQuote() {
        CarrierMappingService.testMappingSets = new Map<String, CarrierMappingService.MappingSet>();
        addMapping('fedex', 'getRateQuote', 'Account', 'Name', 'selectedRate.serviceName', CarrierMappingService.DIRECTION_TO_SF);

        Carrier_Rate_Quote__c quote = new Carrier_Rate_Quote__c(
            Name = 'Bad Quote',
            Integration_Type__c = 'fedex',
            Source_Record_Id__c = UserInfo.getUserId(),
            Service_Type__c = 'FEDEX_GROUND',
            Service_Name__c = 'FedEx Ground'
        );
        insert quote;

        Test.startTest();
        CarrierOperationsService.OperationResult result =
            CarrierOperationsService.selectRateQuote(quote.Id, UserInfo.getUserId(), 'Account');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log__c
            WHERE Carrier_Rate_Quote__c = :quote.Id
            AND Class_Method_Name__c = 'CarrierOperationsService.selectRateQuote'
        ]);
    }

    @IsTest
    static void trackingBatchLogsAgainstShipment() {
        Carrier_Shipment__c shipment = new Carrier_Shipment__c(
            Name = 'Batch Shipment',
            Integration_Type__c = 'fedex',
            Master_Tracking_Number__c = 'TRACK-BATCH',
            Is_Terminal__c = false,
            Shipment_Status__c = 'Created'
        );
        insert shipment;
        configureTestCarrier();

        Test.startTest();
        Database.executeBatch(new CarrierTrackingStatusBatch('fedex'), 1);
        Test.stopTest();

        Carrier_Shipment__c updated = [
            SELECT Latest_Status__c
            FROM Carrier_Shipment__c
            WHERE Id = :shipment.Id
            LIMIT 1
        ];
        System.assertEquals('In Transit', updated.Latest_Status__c);
    }

    @IsTest
    static void trackingBatchLogsUnexpectedRowFailure() {
        Test.startTest();
        new CarrierTrackingStatusBatch('fedex').execute(null, new List<SObject>{ null });
        Test.stopTest();

        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log__c
            WHERE Class_Method_Name__c = 'CarrierTrackingStatusBatch.execute'
        ]);
    }

    @IsTest
    static void trackingBatchScheduleMethodsAreCovered() {
        Test.startTest();
        String allJobId = CarrierTrackingStatusBatch.scheduleHourly();
        String fedExJobId = CarrierTrackingStatusBatch.scheduleFedExHourly();
        String upsJobId = CarrierTrackingStatusBatch.scheduleUPSHourly();
        new CarrierTrackingStatusBatch().execute((SchedulableContext) null);
        Test.stopTest();

        System.assertNotEquals(null, allJobId);
        System.assertNotEquals(null, fedExJobId);
        System.assertNotEquals(null, upsJobId);
    }

    @IsTest
    static void controllerRunActionCoversShipmentBranches() {
        Account account = new Account(Name = 'Carrier Controller Account', Carrier_Type__c = 'FedEx');
        insert account;
        configureTestCarrier();

        Test.startTest();
        CarrierOperationsService.OperationResult validateResult =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'validateAddress');
        CarrierOperationsService.OperationResult validateUpdateResult =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'validateAddressAndUpdate');
        CarrierOperationsService.OperationResult rateResult =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'getRateQuote');
        CarrierOperationsService.OperationResult shipmentResult =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'createShipment');
        CarrierOperationsService.OperationResult shipmentWithLabelResult =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'createShipmentWithLabel');
        CarrierOperationsService.OperationResult labelResult =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'generateLabel');
        CarrierOperationsService.OperationResult trackingResult =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'syncTrackingStatus');
        CarrierOperationsService.OperationResult returnResult =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'createReturnLabel');
        CarrierOperationsService.OperationResult voidResult =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'voidShipment');
        Carrier_Rate_Quote__c quote = [SELECT Id FROM Carrier_Rate_Quote__c WHERE Source_Record_Id__c = :String.valueOf(account.Id) LIMIT 1];
        CarrierOperationsService.OperationResult selectResult =
            CarrierRecordActionController.selectRateQuote(quote.Id, null, null);
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

    private static void configureTestCarrier() {
        CarrierAdapterFactory.testAdapters = new Map<String, ICarrierAdapter>{
            'fedex' => new FakeCarrierAdapter()
        };

        CarrierMappingService.testMappingSets = new Map<String, CarrierMappingService.MappingSet>();
        addMapping('fedex', 'validateAddress', 'Account', 'Name', 'address.city', CarrierMappingService.DIRECTION_TO_CARRIER);
        addMapping('fedex', 'validateAddress', 'Account', 'Phone', 'validatedAddress.city', CarrierMappingService.DIRECTION_TO_SF);
        addMapping('fedex', 'getRateQuote', 'Account', 'Name', 'recipient.contact.personName', CarrierMappingService.DIRECTION_TO_CARRIER);
        addMapping('fedex', 'createShipment', 'Account', 'Name', 'recipient.contact.personName', CarrierMappingService.DIRECTION_TO_CARRIER);
        addMapping('fedex', 'createReturnLabel', 'Account', 'Name', 'recipient.contact.personName', CarrierMappingService.DIRECTION_TO_CARRIER);
        addMapping('fedex', 'generateLabel', 'QuickBridgeTLG__Carrier_Shipment__c', 'Name', 'shipment.name', CarrierMappingService.DIRECTION_TO_CARRIER);
        addMapping('fedex', 'syncTrackingStatus', 'QuickBridgeTLG__Carrier_Shipment__c', 'Latest_Status__c', 'tracking.latestStatus', CarrierMappingService.DIRECTION_TO_SF);
        addMapping('fedex', 'voidShipment', 'QuickBridgeTLG__Carrier_Shipment__c', 'Shipment_Status__c', 'void.status', CarrierMappingService.DIRECTION_TO_SF);
    }

    private static void addMapping(
        String integration,
        String actionName,
        String sfObjectApiName,
        String sfField,
        String externalField,
        String direction
    ) {
        String key = CarrierMappingService.getMappingKey(integration, actionName, sfObjectApiName);
        if (!CarrierMappingService.testMappingSets.containsKey(key)) {
            CarrierMappingService.MappingSet mappingSet = new CarrierMappingService.MappingSet();
            mappingSet.integration = integration;
            mappingSet.actionName = actionName;
            mappingSet.sfObjectApiName = sfObjectApiName;
            CarrierMappingService.testMappingSets.put(key, mappingSet);
        }

        Field_Mapping__mdt mapping = new Field_Mapping__mdt(
            SF_Object__c = sfObjectApiName,
            SF_Field__c = sfField,
            External_Field__c = externalField,
            Sync_Direction__c = direction
        );
        if (direction == CarrierMappingService.DIRECTION_TO_SF) {
            CarrierMappingService.testMappingSets.get(key).responseMappings.add(mapping);
        } else {
            CarrierMappingService.testMappingSets.get(key).requestMappings.add(mapping);
        }
    }
}