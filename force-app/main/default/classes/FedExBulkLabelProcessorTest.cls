@isTest
public class FedExBulkLabelProcessorTest {

    // Utility: Create a Person Account
    private static Account createPersonAccount() {
        Id paRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id;

        Account acc = new Account(
            RecordTypeId = paRtId,
            LastName = 'TestLast',              // Required
            FirstName = 'TestFirst',            // Optional but good
            PersonEmail = 'test@example.com',   // Required for flow email matching
            Phone = '1234567890',
            BillingStreet = '123 Main St',
            BillingCity = 'Sydney',
            BillingStateCode = 'NSW',
            BillingPostalCode = '2000',
            BillingCountryCode = 'AU'
        );
        insert acc;
        return acc;
    }

    // Utility: Create a Case that satisfies the flow
    private static Case createCase(Account acc, String brand) {
        Case c = new Case(
            AccountId = acc.Id,
            ContactId = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1].Id, // ensure Contact exists
            Subject = 'Test Case',
            Origin = 'Phone',
            Status = 'New',
            Brand_Name__c = brand,
            SuppliedEmail = acc.PersonEmail // required for flow email automation
        );
        insert c;
        return c;
    }

    // Utility: Create Label__c
    private static Label__c createLabel(Case c, Account acc, Boolean withTracking) {
        Label__c lbl = new Label__c(
            Case__c = c.Id,
            Account__c = acc.Id,
            Packaging_Type__c = 'YOUR_PACK',
            Pickup_Type__c = 'DROPOFF',
            Service_Type__c = 'FEDEX_GROUND',
            Address__Street__s = '123 Test Street',
            Address__City__s = 'Sydney',
            Address__PostalCode__s = '2000',
            Address__StateCode__s = 'NSW',
            Address__CountryCode__s = 'AU',
            Ship_Date_Stamp__c = Date.today(),
            Units__c = 'KG',
            Value__c = 1
        );
        if (withTracking) {
            lbl.Master_Tracking_Number__c = 'EXISTING_TRACK';
        }
        insert lbl;
        return lbl;
    }

    @isTest
    static void test_generateLabel_success() {
        Test.setMock(HttpCalloutMock.class, new FedExMultiCalloutMock());
    
        Test.startTest();
        Account acc = createPersonAccount();
        Case c = createCase(acc, 'Chanel');
        c.Shipping_and_Accompaniments__c = 'Test Shipping';
        c.Risk_of_Loss__c = 'Test Risk';
        update c;
        
        Label__c lbl = createLabel(c, acc, false);
    
        FedExBulkLabelProcessor.CaseInput ci = new FedExBulkLabelProcessor.CaseInput();
        ci.caseId = c.Id;
        ci.poNumber = 'PO123';
    
        List<FedExBulkLabelProcessor.CaseInput> inputs = new List<FedExBulkLabelProcessor.CaseInput>{ ci };
    
        List<FedExBulkLabelProcessor.BulkLabelResult> results =
            FedExBulkLabelProcessor.generateLabel(inputs);
    
        Test.stopTest();
    }
    
    @isTest
    static void test_generateLabel_error() {
        Test.setMock(HttpCalloutMock.class, new FedExErrorHttpMock());
    
        Test.startTest();
        Account acc = createPersonAccount();
        Case c = createCase(acc, 'Chanel');
        c.Shipping_and_Accompaniments__c = 'Test Shipping';
        c.Risk_of_Loss__c = 'Test Risk';
        update c;
        
        Label__c lbl = createLabel(c, acc, false);
    
        FedExBulkLabelProcessor.CaseInput ci = new FedExBulkLabelProcessor.CaseInput();
        ci.caseId = c.Id;
        ci.poNumber = 'PO123';
    
        List<FedExBulkLabelProcessor.CaseInput> inputs = new List<FedExBulkLabelProcessor.CaseInput>{ ci };
    
        List<FedExBulkLabelProcessor.BulkLabelResult> results =
            FedExBulkLabelProcessor.generateLabel(inputs);
    
        Test.stopTest();
    }

  	@isTest
    static void test_generateLabel_noCases() {
        Test.startTest();
        // empty list of CaseInput
        List<FedExBulkLabelProcessor.CaseInput> emptyInputs = new List<FedExBulkLabelProcessor.CaseInput>();
        List<FedExBulkLabelProcessor.BulkLabelResult> results =
            FedExBulkLabelProcessor.generateLabel(emptyInputs);
        Test.stopTest();
    
        System.assertEquals(false, results[0].isSuccess, 'Should fail if no IDs');
        System.assert(results[0].message.contains('No Case Ids'), 'Should show no Ids message');
    }

    @isTest
    static void test_generateLabel_missingBrandName() {
        Test.setMock(HttpCalloutMock.class, new FedExMultiCalloutMock());
        
        Test.startTest();
        Account acc = createPersonAccount();
        Case c = createCase(acc, null);
        c.Shipping_and_Accompaniments__c = 'Test';
        c.Risk_of_Loss__c = 'Test';
        update c;
    
        FedExBulkLabelProcessor.CaseInput ci = new FedExBulkLabelProcessor.CaseInput();
        ci.caseId = c.Id;
        // ci.poNumber left null to test optional behavior
    
        List<FedExBulkLabelProcessor.CaseInput> inputs = new List<FedExBulkLabelProcessor.CaseInput>{ ci };
    
        List<FedExBulkLabelProcessor.BulkLabelResult> results =
            FedExBulkLabelProcessor.generateLabel(inputs);
        Test.stopTest();
        
        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].message.contains('Brand Name'));
    }

   	@isTest
    static void test_generateLabel_noLabels() {
        Test.startTest();
        Account acc = createPersonAccount();
        Case c = createCase(acc, 'Hermes'); // valid brand
    
        FedExBulkLabelProcessor.CaseInput ci = new FedExBulkLabelProcessor.CaseInput();
        ci.caseId = c.Id;
    
        List<FedExBulkLabelProcessor.CaseInput> inputs = new List<FedExBulkLabelProcessor.CaseInput>{ ci };
    
        List<FedExBulkLabelProcessor.BulkLabelResult> results =
            FedExBulkLabelProcessor.generateLabel(inputs);
        Test.stopTest();
    }
    
    @isTest
    static void test_parseShipmentResponse_variousScenarios() {
        // Create supporting records
        Account acc = createPersonAccount();
        Case c = createCase(acc, 'Chanel');
        Label__c lbl = createLabel(c, acc, false);
    
        // Use real Label__c Id instead of fake
        Id realLabelId = lbl.Id;
    
        // Case 1: valid minimal response
        String validResponse = '{"output":{"transactionShipments":[{"masterTrackingNumber":"T123","pieceResponses":[{"packageDocuments":[{"encodedLabel":"' 
            + EncodingUtil.base64Encode(Blob.valueOf('pdfdata')) + '"}]}]}]}}';
        FedExBulkLabelProcessor.LabelProcessingData data =
            FedExBulkLabelProcessor.parseShipmentResponse(realLabelId, validResponse, 'LBL1');
        System.assertNotEquals(null, data, 'Should parse valid response');
        System.assertEquals('T123', data.trackingNumber);
    
        // Case 2: missing output
        String noOutput = '{}';
        System.assertEquals(null, FedExBulkLabelProcessor.parseShipmentResponse(realLabelId, noOutput, 'LBL2'));
    
        // Case 3: no tracking number
        String noTracking = '{"output":{"transactionShipments":[{"masterTrackingNumber":""}]}}';
        System.assertEquals(null, FedExBulkLabelProcessor.parseShipmentResponse(realLabelId, noTracking, 'LBL3'));
    
        // Case 4: invalid JSON
        String badJson = '{notvalidjson';
        System.assertEquals(null, FedExBulkLabelProcessor.parseShipmentResponse(realLabelId, badJson, 'LBL4'));
    }


    @isTest
    static void test_processBatchDMLOperations_fullFlow() {
        Account acc = createPersonAccount();
        Case c = createCase(acc, 'Chanel');
        Label__c lbl = createLabel(c, acc, false);
    
        // Fake processing data
        FedExBulkLabelProcessor.LabelProcessingData proc = new FedExBulkLabelProcessor.LabelProcessingData();
        proc.labelId = lbl.Id;
        proc.trackingNumber = 'TRK999';
        proc.base64Label = EncodingUtil.base64Encode(Blob.valueOf('pdfdata'));
        proc.labelName = 'LBLPROC';
    
        Test.startTest();
        List<String> cvIds = FedExBulkLabelProcessor.processBatchDMLOperations(new List<FedExBulkLabelProcessor.LabelProcessingData>{ proc });
        Test.stopTest();
    
        System.assert(!cvIds.isEmpty(), 'ContentVersion should be created');
        Label__c updatedLbl = [SELECT Master_Tracking_Number__c FROM Label__c WHERE Id = :lbl.Id];
        System.assertEquals('TRK999', updatedLbl.Master_Tracking_Number__c, 'Label should be updated with tracking');
    
        // Validate ContentDocumentLink created
        List<ContentDocumentLink> links = [SELECT Id, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId = :c.Id];
        System.assert(!links.isEmpty(), 'ContentDocumentLink should be created');
    }

    @isTest
    static void test_processBatchDMLOperations_emptyList() {
        Test.startTest();
        List<String> cvIds = FedExBulkLabelProcessor.processBatchDMLOperations(new List<FedExBulkLabelProcessor.LabelProcessingData>());
        Test.stopTest();
        System.assertEquals(0, cvIds.size(), 'No ContentVersions should be created for empty list');
    }

 	@isTest
    static void test_generateLabel_labelsWithTracking() {
        Test.startTest();
        Account acc = createPersonAccount();
        Case c = createCase(acc, 'Chanel');
        Label__c lbl = createLabel(c, acc, true); // already has tracking
    
        FedExBulkLabelProcessor.CaseInput ci = new FedExBulkLabelProcessor.CaseInput();
        ci.caseId = c.Id;
    
        List<FedExBulkLabelProcessor.CaseInput> inputs = new List<FedExBulkLabelProcessor.CaseInput>{ ci };
    
        List<FedExBulkLabelProcessor.BulkLabelResult> results =
            FedExBulkLabelProcessor.generateLabel(inputs);
        Test.stopTest();
    }
    
    private class FedExMultiCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            // Check which endpoint is being called
            if (req.getEndpoint().contains('/oauth/token')) {
                // Auth request
                res.setBody('{"access_token":"testToken123","token_type":"Bearer","expires_in":3600}');
            } else if (req.getEndpoint().contains('/ship/v1/shipments')) {
                // Shipment request
                res.setBody('{' +
                    '"output": {' +
                        '"transactionShipments": [{' +
                            '"masterTrackingNumber": "TRACK12345",' +
                            '"pieceResponses": [{' +
                                '"packageDocuments": [{' +
                                    '"encodedLabel": "' + EncodingUtil.base64Encode(Blob.valueOf('Fake PDF Data')) + '"' +
                                '}]' +
                            '}]' +
                        '}]' +
                    '}' +
                '}');
            }
            return res;
        }
    }
    
    // Fake HTTP response for FedEx
    private class FedExErrorHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            // Minimal valid FedEx JSON response
            res.setBody('{' +
                '"transactionId":"fbe1f6de-1dc0-4565-8c28-d4ba2999a2b7",' +
                '"errors":[' +
                    '{' +
                        '"code":"SELECTED.DESTINATION.SERVICETYPE.INVALID",' +
                        '"message":"This service type is not available for the destination. Please update and try again."' +
                    '}' +
                ']' +
            '}');
            return res;
        }
    }
}