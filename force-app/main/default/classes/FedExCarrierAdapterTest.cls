@isTest
public with sharing class FedExCarrierAdapterTest {

    // ------------------------------------------------------------------------
    // HTTP Mock: handles OAuth token + all FedEx endpoints
    // ------------------------------------------------------------------------
    private class FedExMock implements HttpCalloutMock {
        private String expectedPath;
        private Integer statusCode;
        private String responseBody;

        public FedExMock(String expectedPath, Integer statusCode, String responseBody) {
            this.expectedPath = expectedPath;
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest request) {
            String endpoint = request.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            // ---- OAuth token endpoint ----
            if (endpoint.contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token_123","token_type":"Bearer","expires_in":3600}');
                return res;
            }

            // ---- All other FedEx API endpoints ----
            System.assert(endpoint.contains(expectedPath),
                'Expected path: ' + expectedPath + ' not found in endpoint: ' + endpoint);
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }

    // ------------------------------------------------------------------------
    // Test Setup: Create Connector Config (without namespace)
    // ------------------------------------------------------------------------
    @testSetup
    static void setupConnectorConfig() {
        // 1. Create Connector_Instance__c record
        Connector_Instance__c instance = new Connector_Instance__c(
            Connector_Key__c = 'fedex',
            Active__c = true,
            Connector_Label__c = 'FedEx',
            Environment__c = 'Sandbox',
            Expiry_Date__c = Date.newInstance(2027, 6, 2)
        );
        insert instance;

        // 2. Create Connector_Config_Value__c records for all required fields
        List<Connector_Config_Value__c> configValues = new List<Connector_Config_Value__c>();

        // Map of field keys to values 
        Map<String, String> fieldValueMap = new Map<String, String>{
            'FedEx_Active__c'           => 'TRUE',
            'FedEx_Client_Id__c'         => 'l7d5cfd04834fc40cbaacf94e03059ebcf',
            'FedEx_Client_Secret__c'     => 'b2f0d4f362664d15910ab39d3feded22',
            'FedEx_Account_Number__c'    => '740561073',
            'FedEx_Environment__c'       => 'Sandbox',
            'FedEx_Default_Service_Type__c'  => 'FEDEX_GROUND',
            'FedEx_Default_Packaging_Type__c'=> 'YOUR_PACKAGING',
            'FedEx_Default_Pickup_Type__c'   => 'USE_SCHEDULED_PICKUP',
            'FedEx_End_Date__c'          => '2027-06-02',
            'FedEx_Start_Date__c'        => '2026-06-02'
        };

        for (String fieldKey : fieldValueMap.keySet()) {
            Connector_Config_Value__c cv = new Connector_Config_Value__c(
                Connector_Instance__c = instance.Id,
                Field_Key__c = fieldKey,
                Value__c = fieldValueMap.get(fieldKey),
                Is_Secret_Reference__c = false,
                Connector_Key__c = 'fedex'
            );
            configValues.add(cv);
        }
        insert configValues;
    }

    // ------------------------------------------------------------------------
    // Helper: Build Payloads
    // ------------------------------------------------------------------------
    private static Map<String, Object> buildAddressPayload() {
        return new Map<String, Object>{
            'address' => new Map<String, Object>{
                'streetLines' => new List<String>{ '123 Main St' },
                'city' => 'Anytown',
                'stateOrProvinceCode' => 'CA',
                'postalCode' => '12345',
                'countryCode' => 'US',
                'residential' => false
            }
        };
    }

    private static Map<String, Object> buildShipmentPayload() {
        Map<String, Object> packageMap = new Map<String, Object>{
            'weight' => new Map<String, Object>{ 'value' => 10, 'units' => 'LB' },
            'dimensions' => new Map<String, Object>{ 'length' => 10, 'width' => 10, 'height' => 10, 'units' => 'IN' }
        };
        return new Map<String, Object>{
            'shipper' => new Map<String, Object>{
                'address' => new Map<String, Object>{
                    'streetLines' => new List<String>{ '456 Shipper Ave' },
                    'city' => 'Shippertown',
                    'stateOrProvinceCode' => 'NY',
                    'postalCode' => '10001',
                    'countryCode' => 'US'
                }
            },
            'recipient' => new Map<String, Object>{
                'address' => new Map<String, Object>{
                    'streetLines' => new List<String>{ '789 Receiver Blvd' },
                    'city' => 'Receiverville',
                    'stateOrProvinceCode' => 'TX',
                    'postalCode' => '75001',
                    'countryCode' => 'US'
                }
            },
            'package' => packageMap,
            'serviceType' => 'FEDEX_GROUND',
            'packagingType' => 'YOUR_PACKAGING',
            'shipDatestamp' => String.valueOf(Date.today())
        };
    }

    // ------------------------------------------------------------------------
    // Mock JSON Responses (Success)
    // ------------------------------------------------------------------------
    private static String getAddressSuccessResponse() {
        return '{"output":{"resolvedAddresses":[{"streetLines":["123 Main St"],"city":"Anytown","stateOrProvinceCode":"CA","postalCode":"12345","countryCode":"US","classification":"BUSINESS","residential":false}]}}';
    }

    private static String getRateQuoteSuccessResponse() {
        return '{"output":{"rateReplyDetails":[{"serviceType":"FEDEX_GROUND","totalNetCharge":"25.50","currency":"USD"}]}}';
    }

    private static String getShipmentSuccessResponse() {
        return '{"output":{"transactionShipments":[{"transactionId":"ship-123","masterTrackingNumber":"123456789012","serviceType":"FEDEX_GROUND","shipmentRating":{"totalNetCharge":{"amount":"25.50","currency":"USD"}},"pieceResponses":[{"trackingNumber":"123456789012","packageDocuments":[{"encodedLabel":"base64EncodedLabel","contentType":"application/pdf"}]}]}]}}';
    }

    private static String getVoidSuccessResponse() {
        return '{"output":{"transactionId":"void-456"}}';
    }

    private static String getTrackingSuccessResponse() {
        return '{"output":{"completeTrackResults":[{"trackResults":[{"trackingNumber":"123456789012","latestStatusDetail":{"statusByLocale":"Delivered","code":"DL","description":"Delivered"},"scanEvents":[{"eventType":"Delivered","eventDescription":"Package delivered","date":"2025-01-15T10:00:00Z"}]}]}]}}';
    }

    private static String getErrorResponse(String code, String message) {
        return '{"errors":[{"code":"' + code + '","message":"' + message + '"}]}';
    }

    // ------------------------------------------------------------------------
    // Test Methods
    // ------------------------------------------------------------------------

    @isTest
    static void testValidateAddress_Success() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/address/v1/addresses/resolve', 200, getAddressSuccessResponse()
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();
        Map<String, Object> payload = buildAddressPayload();

        Test.startTest();
        Map<String, Object> result = adapter.validateAddress(payload);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('validatedAddress'));
        System.assert(result.containsKey('addressClassification'));
        System.assert(result.containsKey('residential'));
        System.assert(result.containsKey('rawResponse'));
    }

    @isTest
    static void testValidateAddress_Error() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/address/v1/addresses/resolve', 400, getErrorResponse('INVALID.INPUT', 'Invalid address')
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        try {
            adapter.validateAddress(buildAddressPayload());
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('FedEx address validation failed'));
        }
        Test.stopTest();
    }

    @isTest
    static void testGetRateQuote_Success() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/rate/v1/rates/quotes', 200, getRateQuoteSuccessResponse()
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();
        Map<String, Object> payload = buildShipmentPayload();

        Test.startTest();
        Map<String, Object> result = adapter.getRateQuote(payload);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('rateDetails'));
        System.assert(result.containsKey('rawResponse'));
    }

    @isTest
    static void testGetRateQuote_Error() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/rate/v1/rates/quotes', 400, getErrorResponse('RATE.ERROR', 'Rate calculation failed')
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        try {
            adapter.getRateQuote(buildShipmentPayload());
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('FedEx rate quote failed'));
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateShipment_Success() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/ship/v1/shipments', 200, getShipmentSuccessResponse()
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();
        Map<String, Object> payload = buildShipmentPayload();

        Test.startTest();
        Map<String, Object> result = adapter.createShipment(payload, true);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('shipment'));
        System.assert(result.containsKey('package'));
        System.assert(result.containsKey('label'));
        System.assert(result.containsKey('rawResponse'));

        Map<String, Object> shipment = (Map<String, Object>) result.get('shipment');
        System.assertEquals('ship-123', shipment.get('externalShipmentId'));
        System.assertEquals('123456789012', shipment.get('masterTrackingNumber'));
        System.assertEquals('Created', shipment.get('status'));
        System.assertEquals('FEDEX_GROUND', shipment.get('serviceType'));
        System.assertEquals('25.50', shipment.get('totalNetCharge'));
        System.assertEquals('USD', shipment.get('currency'));
    }

    @isTest
    static void testCreateShipment_Error() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/ship/v1/shipments', 500, getErrorResponse('SHIP.FAIL', 'Shipment creation failed')
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        try {
            adapter.createShipment(buildShipmentPayload(), true);
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('FedEx shipment creation failed'));
        }
        Test.stopTest();
    }

    @isTest
    static void testVoidShipment_Success() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/ship/v1/shipments/cancel', 200, getVoidSuccessResponse()
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        Map<String, Object> result = adapter.voidShipment('123456789012', 'ship-123');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('void'));
        System.assert(result.containsKey('rawResponse'));
        Map<String, Object> voidMap = (Map<String, Object>) result.get('void');
        System.assertEquals('Voided', voidMap.get('status'));
        System.assertEquals('void-456', voidMap.get('confirmationNumber'));
        System.assertNotEquals(null, voidMap.get('voidedTimestamp'));
    }

    @isTest
    static void testVoidShipment_Error() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/ship/v1/shipments/cancel', 404, getErrorResponse('VOID.NOTFOUND', 'Shipment not found')
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        try {
            adapter.voidShipment('123456789012', 'ship-123');
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('FedEx void shipment failed'));
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateReturnLabel_Success() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/ship/v1/shipments', 200, getShipmentSuccessResponse()
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();
        Map<String, Object> payload = buildShipmentPayload();

        Test.startTest();
        Map<String, Object> result = adapter.createReturnLabel(payload);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('returnShipment'));
        System.assert(result.containsKey('label'));
        System.assert(result.containsKey('rawResponse'));
        Map<String, Object> returnShip = (Map<String, Object>) result.get('returnShipment');
        System.assertEquals('ship-123', returnShip.get('externalShipmentId'));
        System.assertEquals('123456789012', returnShip.get('trackingNumber'));
        System.assertEquals('Created', returnShip.get('status'));
        System.assert(returnShip.containsKey('encodedLabel'));
    }

    @isTest
    static void testCreateReturnLabel_Error() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/ship/v1/shipments', 400, getErrorResponse('RETURN.ERR', 'Return label failed')
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        try {
            adapter.createReturnLabel(buildShipmentPayload());
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('FedEx return label creation failed'));
        }
        Test.stopTest();
    }

    @isTest
    static void testSyncTrackingStatus_Success() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/track/v1/trackingnumbers', 200, getTrackingSuccessResponse()
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        Map<String, Object> result = adapter.syncTrackingStatus('123456789012');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('tracking'));
        System.assert(result.containsKey('events'));
        System.assert(result.containsKey('rawResponse'));

        Map<String, Object> tracking = (Map<String, Object>) result.get('tracking');
        System.assertEquals('123456789012', tracking.get('trackingNumber'));
        System.assertEquals('Delivered', tracking.get('latestStatus'));
        System.assertEquals('DL', tracking.get('statusCode'));
        System.assertNotEquals(null, tracking.get('lastEventTimestamp'));
        System.assertEquals(false, tracking.get('isTerminal'));

        List<Object> events = (List<Object>) result.get('events');
        System.assertEquals(1, events.size());
        Map<String, Object> event = (Map<String, Object>) events[0];
        System.assertEquals('Delivered', event.get('eventType'));
    }

    @isTest
    static void testSyncTrackingStatus_Error() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/track/v1/trackingnumbers', 404, getErrorResponse('TRACK.NOTFOUND', 'Tracking number not found')
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        try {
            adapter.syncTrackingStatus('123456789012');
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('FedEx tracking sync failed'));
        }
        Test.stopTest();
    }

    // ------------------------------------------------------------------------
    // Edge Cases
    // ------------------------------------------------------------------------
    @isTest
    static void testValidateAddress_NullPayload() {
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/address/v1/addresses/resolve', 200, getAddressSuccessResponse()
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        Map<String, Object> result = adapter.validateAddress(null);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('validatedAddress'));
    }

    @isTest
    static void testCreateShipment_WithoutPackage() {
        Map<String, Object> payload = new Map<String, Object>{
            'shipper' => new Map<String, Object>{
                'address' => new Map<String, Object>{
                    'streetLines' => new List<String>{ '456 Shipper Ave' },
                    'city' => 'Shippertown',
                    'stateOrProvinceCode' => 'NY',
                    'postalCode' => '10001',
                    'countryCode' => 'US'
                }
            },
            'recipient' => new Map<String, Object>{
                'address' => new Map<String, Object>{
                    'streetLines' => new List<String>{ '789 Receiver Blvd' },
                    'city' => 'Receiverville',
                    'stateOrProvinceCode' => 'TX',
                    'postalCode' => '75001',
                    'countryCode' => 'US'
                }
            }
        };

        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/ship/v1/shipments', 200, getShipmentSuccessResponse()
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        Map<String, Object> result = adapter.createShipment(payload, true);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('shipment'));
    }

    @isTest
    static void testCreateShipment_PayloadWithShipmentNested() {
        Map<String, Object> shipmentPayload = buildShipmentPayload();
        Map<String, Object> payload = new Map<String, Object>{
            'shipment' => shipmentPayload
        };

        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/ship/v1/shipments', 200, getShipmentSuccessResponse()
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        Map<String, Object> result = adapter.createShipment(payload, true);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('shipment'));
    }

    @isTest
    static void testGetRateQuote_WithRecipientsArray() {
        Map<String, Object> payload = buildShipmentPayload();
        payload.put('recipients', new List<Object>{ payload.remove('recipient') });

        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/rate/v1/rates/quotes', 200, getRateQuoteSuccessResponse()
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        Map<String, Object> result = adapter.getRateQuote(payload);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('rateDetails'));
    }

    // Additional test to ensure error handling when parameterList is present
    @isTest
    static void testRequireSuccess_WithParameterListErrors() {
        String errorJson = '{"errors":[{"code":"INVALID.INPUT.EXCEPTION","message":"Input validation failed","parameterList":[{"value":"Invalid street"}]}]}';
        Test.setMock(HttpCalloutMock.class, new FedExMock(
            '/address/v1/addresses/resolve', 400, errorJson
        ));

        FedExCarrierAdapter adapter = new FedExCarrierAdapter();

        Test.startTest();
        try {
            adapter.validateAddress(buildAddressPayload());
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            // Should include the parameterList value
            System.assert(e.getMessage().contains('Invalid street'));
        }
        Test.stopTest();
    }
}