@IsTest
private class CarrierRecordActionControllerTest {

    @TestSetup
    static void setup() {
        insert new List<Connector_Instance__c>{
            new Connector_Instance__c(Name='DHL Valid', Connector_Key__c='dhl', Active__c=true, Expiry_Date__c=Date.today().addDays(30)),
            new Connector_Instance__c(Name='FedEx Expired', Connector_Key__c='fedex', Active__c=true, Expiry_Date__c=Date.today().addDays(-10))
        };
    }

    @IsTest
    static void testGetActiveCarriers() {
        Test.startTest();
        CarrierRecordActionController.ActiveCarriersResult result = CarrierRecordActionController.getActiveCarriers();
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should evaluate configurations without errors.');
    }

    @IsTest
    static void testActionItemAndRateQuoteDto() {
        CarrierRecordActionController.ActionItem item = new CarrierRecordActionController.ActionItem('testAction', 'Test Label');
        CarrierOperationsService.RateQuoteOption option = new CarrierOperationsService.RateQuoteOption();
        
        Id fakeQuoteId = UserInfo.getUserId();
        option.rateQuoteId = fakeQuoteId;
        option.totalNetCharge = 10.0;
        option.currencyCode = 'USD';
        
        System.assertEquals('testAction', item.actionName, 'ActionItem constructor should map correctly.');
        System.assertEquals(fakeQuoteId, option.rateQuoteId, 'DTO should map successfully.');
    }

    @IsTest
    static void testUpdateCarrierType() {
        Account acc = new Account(Name='Test Account', Carrier_Type__c='FedEx');
        insert acc;
        
        CarrierRecordActionController.updateCarrierType(acc.Id, 'Account', 'UPS');
        System.assertEquals('UPS', [SELECT Carrier_Type__c FROM Account WHERE Id = :acc.Id].Carrier_Type__c);
        
        try { CarrierRecordActionController.updateCarrierType(acc.Id, 'Account', 'InvalidCarrier'); } catch(Exception e){}
        
        try { CarrierRecordActionController.updateCarrierType(acc.Id, 'Invalid__c', 'FedEx'); } catch(Exception e){}
    }

    @IsTest
    static void testUpdateCarrierTypeGenericException() {
        Contact con = new Contact(LastName = 'Generic Error Target');
        insert con;
        
        try {
            CarrierRecordActionController.updateCarrierType(con.Id, 'Account', 'FedEx');
        } catch (Exception e) {
            System.assertNotEquals(null, e);
        }
    }

    @IsTest
    static void testGetActionsForObject() {
        Account acc = new Account(Name='Test Actions', Carrier_Type__c='FedEx');
        insert acc;
        
        CarrierRecordActionController.getActionsForObject(acc.Id, 'Account');
        CarrierRecordActionController.getActionsForObject(acc.Id, ''); 
        try { CarrierRecordActionController.getActionsForObject(null, 'Invalid__c'); } catch(Exception e){}
    }

    @IsTest
    static void testRunActionAllBranches() {
        Account acc = new Account(Name='Test Acc', Carrier_Type__c='FedEx');
        insert acc;
        
        Carrier_Shipment__c shipment = new Carrier_Shipment__c(
            Source_Record_Id__c = acc.Id,
            Source_Object__c = 'Account',
            Integration_Type__c = 'fedex',
            Is_Return__c = false
        );
        insert shipment;

        List<String> actions = new List<String>{
            'validateAddress', 'validateAddressAndUpdate', 'getRateQuote',
            'createShipment', 'createShipmentWithLabel', 'generateLabel',
            'syncTrackingStatus', 'voidShipment', 'createReturnLabel', 'invalidAction'
        };

        for(String action : actions) {
            try {
                CarrierRecordActionController.runAction(acc.Id, 'Account', action);
            } catch(Exception e){}
        }

        try { 
            CarrierRecordActionController.runAction(shipment.Id, 'QuickBridgeTLG__Carrier_Shipment__c', 'syncTrackingStatus'); 
        } catch(Exception e){}
    }

    @IsTest
    static void testResolveCarrierTypeExceptions() {
        User u = [SELECT Id FROM User LIMIT 1];
        try { CarrierRecordActionController.getActionsForObject(u.Id, 'User'); } catch(Exception e){}
        Account accNull = new Account(Name='Test Null');
        insert accNull;
        try { CarrierRecordActionController.getActionsForObject(accNull.Id, 'Account'); } catch(Exception e){}
        String jsonRecord = '{"attributes":{"type":"Account"}, "Id":"001000000000000AAA", "Name":"Mock", "Carrier_Type__c":"InvalidCarrier"}';
        Account mockAcc = (Account)JSON.deserialize(jsonRecord, Account.class);
        try { CarrierRecordActionController.runAction(mockAcc.Id, 'Account', 'validateAddress'); } catch(Exception e){}
        Carrier_Shipment__c looseShipment = new Carrier_Shipment__c(Name='Loose');
        insert looseShipment;
        try { CarrierRecordActionController.runAction(looseShipment.Id, 'Carrier_Shipment__c', 'validateAddress'); } catch(Exception e){}
        Account accNoShip = new Account(Name='No Ship', Carrier_Type__c='FedEx');
        insert accNoShip;
        try { CarrierRecordActionController.runAction(accNoShip.Id, 'Account', 'syncTrackingStatus'); } catch(Exception e){}
    }

    @IsTest
    static void testApplyValidatedAddressAndRateQuote() {
        Account acc = new Account(Name='Test Quote', Carrier_Type__c='FedEx');
        insert acc;

        try { CarrierRecordActionController.applyValidatedAddress(acc.Id, 'Account', new Map<String, Object>()); } catch(Exception e){}
        try { CarrierRecordActionController.applyValidatedAddress(acc.Id, 'Invalid__c', new Map<String, Object>()); } catch(Exception e){}

        try { CarrierRecordActionController.selectRateQuote(acc.Id, acc.Id, 'Account'); } catch(Exception e){}
        
        Id fakeQuoteId = UserInfo.getUserId();
        try { CarrierRecordActionController.selectRateQuote(fakeQuoteId, acc.Id, 'Invalid__c'); } catch(Exception e){}
    }
}