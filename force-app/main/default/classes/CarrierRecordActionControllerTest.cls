@IsTest
private class CarrierRecordActionControllerTest {
    @IsTest
    static void runActionReadsFedExCarrierType() {
        Account account = new Account(Name = 'FedEx Source', Carrier_Type__c = 'FedEx');
        insert account;

        CarrierOperationsService.OperationResult result =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'unknownAction');

        System.assertEquals(false, result.success);
        System.assertEquals('Unknown action: unknownAction', result.message);
    }

    @IsTest
    static void runActionReadsUpsCarrierType() {
        Account account = new Account(Name = 'UPS Source', Carrier_Type__c = 'UPS');
        insert account;

        CarrierOperationsService.OperationResult result =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'unknownAction');

        System.assertEquals(false, result.success);
        System.assertEquals('Unknown action: unknownAction', result.message);
    }

    @IsTest
    static void runActionErrorsWhenCarrierTypeMissing() {
        Account account = new Account(Name = 'Missing Carrier');
        insert account;

        Boolean didThrow = false;
        try {
            CarrierRecordActionController.runAction(account.Id, 'Account', 'unknownAction');
        } catch (AuraHandledException e) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow);
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log__c
            WHERE Account__c = :account.Id
            AND Class_Method_Name__c = 'CarrierRecordActionController.runAction'
        ]);
    }

    @IsTest
    static void runActionResolvesCarrierShipmentForShipmentActions() {
        Carrier_Shipment__c shipment = new Carrier_Shipment__c(
            Name = 'Terminal UPS Shipment',
            Integration_Type__c = 'ups',
            Is_Terminal__c = true,
            Shipment_Status__c = 'Delivered'
        );
        insert shipment;

        CarrierOperationsService.OperationResult result =
            CarrierRecordActionController.runAction(shipment.Id, 'QuickBridgeTLG__Carrier_Shipment__c', 'syncTrackingStatus');

        System.assertEquals(true, result.success);
        System.assertEquals(shipment.Id, result.shipmentId);
        System.assertEquals('Shipment is terminal. Tracking sync skipped.', result.message);
    }

    @IsTest
    static void normalizeCarrierRejectsUnsupportedValues() {
        Boolean didThrow = false;
        try {
            CarrierOperationsService.normalizeCarrier('DHL');
        } catch (AuraHandledException e) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow);
    }

    @IsTest
    static void rateQuoteDtoUsesLwcFields() {
        CarrierOperationsService.RateQuoteOption option = new CarrierOperationsService.RateQuoteOption();
        option.rateQuoteId = UserInfo.getUserId();
        option.totalNetCharge = 12.34;
        option.currencyCode = 'USD';

        System.assertEquals(UserInfo.getUserId(), option.rateQuoteId);
        System.assertEquals(12.34, option.totalNetCharge);
        System.assertEquals('USD', option.currencyCode);
    }

    @IsTest
    static void getActionsForObjectReturnsNullCarrierWhenNotSet() {
        Account account = new Account(Name = 'No Carrier Account');
        insert account;

        CarrierRecordActionController.ActionPanelData data =
            CarrierRecordActionController.getActionsForObject(account.Id, 'Account');

        System.assertEquals(null, data.carrierType);
        System.assertEquals(0, data.actions.size());
    }

    @IsTest
    static void getActionsForObjectReturnsFedExCarrierType() {
        Account account = new Account(Name = 'FedEx Account', Carrier_Type__c = 'FedEx');
        insert account;

        CarrierRecordActionController.ActionPanelData data =
            CarrierRecordActionController.getActionsForObject(account.Id, 'Account');

        System.assertEquals('FedEx', data.carrierType);
        System.assertNotEquals(null, data.actions);
    }

    @IsTest
    static void getActionsForObjectReturnsUPSCarrierType() {
        Account account = new Account(Name = 'UPS Account', Carrier_Type__c = 'UPS');
        insert account;

        CarrierRecordActionController.ActionPanelData data =
            CarrierRecordActionController.getActionsForObject(account.Id, 'Account');

        System.assertEquals('UPS', data.carrierType);
        System.assertNotEquals(null, data.actions);
    }

    @IsTest
    static void updateCarrierTypeSavesToRecord() {
        Account account = new Account(Name = 'Carrier Switch Account', Carrier_Type__c = 'FedEx');
        insert account;

        CarrierRecordActionController.updateCarrierType(account.Id, 'Account', 'UPS');

        Account updated = [SELECT Carrier_Type__c FROM Account WHERE Id = :account.Id LIMIT 1];
        System.assertEquals('UPS', updated.Carrier_Type__c);
    }

    @IsTest
    static void updateCarrierTypeRejectsInvalidCarrier() {
        Account account = new Account(Name = 'Invalid Carrier Account');
        insert account;

        Boolean didThrow = false;
        try {
            CarrierRecordActionController.updateCarrierType(account.Id, 'Account', 'DHL');
        } catch (AuraHandledException e) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow);
    }

    @IsTest
    static void getActiveCarriersReturnsResult() {
        // Quickbridge_Config__mdt is read-only in tests; method must not throw
        CarrierRecordActionController.ActiveCarriersResult result =
            CarrierRecordActionController.getActiveCarriers();
        System.assertNotEquals(null, result);
        // booleans default false when no mdt record exists in test context
        System.assertNotEquals(null, result.fedexActive);
        System.assertNotEquals(null, result.upsActive);
    }

    @IsTest
    static void carrierOperationFailureLogsAgainstSourceRecord() {
        Account account = new Account(Name = 'FedEx Missing Mapping Account', Carrier_Type__c = 'FedEx');
        insert account;

        Test.startTest();
        CarrierOperationsService.OperationResult result =
            CarrierRecordActionController.runAction(account.Id, 'Account', 'getRateQuote');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(1, [
            SELECT Count()
            FROM Error_Log__c
            WHERE Account__c = :account.Id
            AND Gateway_Name__c = 'FedEx'
            AND Class_Method_Name__c = 'CarrierOperationsService.getRateQuote'
        ]);
    }
}