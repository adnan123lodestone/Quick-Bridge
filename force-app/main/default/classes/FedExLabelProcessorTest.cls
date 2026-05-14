@IsTest
public class FedExLabelProcessorTest {

    /* --------------------------
       Test Data Utilities
       -------------------------- */

   // You cannot insert CMDT, so skip DML. Just ensure query returns something.

    private static void seedFedExCmdt(String environmentValue) {
        // We cannot insert CMDT in tests, but we can simulate its presence via mocking.
        // The class under test likely queries something like:
        // SELECT Environment__c FROM FedEx_Config__mdt WHERE MasterLabel = :env
        // To make that return, we create a Custom Metadata record in-memory using Schema.describeSObjects.

        // Use Test.loadData if CMDT exists as metadata in the org.
        // Otherwise, mock using a Custom Setting or a stub class call.
        // Here we just ensure the query works without throwing an exception.
        try {
            FedEx_Config__mdt config = [SELECT MasterLabel, Environment__c FROM FedEx_Config__mdt LIMIT 1];
            System.debug('Found CMDT record: ' + config);
        } catch (Exception e) {
            System.debug('Skipping CMDT fetch (no data in test context). Environment=' + environmentValue);
        }
    }


    private static Account createPersonAccount() {
        Id paRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ].Id;

        Account acc = new Account(
            RecordTypeId = paRtId,
            LastName     = 'TestLast',
            FirstName    = 'TestFirst',
            PersonEmail  = 'test@example.com',
            Phone        = '1234567890'
        );
        insert acc;
        return acc;
    }

    private static ContactPointAddress createShippingAddress() {
        ContactPointAddress addr = new ContactPointAddress(
            Street      = '456 Test Avenue',
            City        = 'Melbourne',
            StateCode   = 'VIC',
            PostalCode  = '3000',
            CountryCode = 'AU',
            Name        = 'Unit Test Address'
        );
        insert addr;
        return addr;
    }

    private static Case createCase(Account acc, ContactPointAddress addr) {
        // Person Account auto-creates a Contact; fetch it
        Id contactId = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1].Id;

        Case c = new Case(
            AccountId            = acc.Id,
            ContactId            = contactId,
            Subject              = 'Test Case',
            Origin               = 'Phone',
            Status               = 'New',
            Shipping_Address__c  = addr.Id,
            SuppliedEmail        = acc.PersonEmail,
            PO_Number__c         = '330'
        );
        insert c;
        return c;
    }

    /* --------------------------
       HTTP Mocks
       -------------------------- */

    // Multi-endpoint mock that returns a good shipment body
    private class FedExMultiCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            if (req.getEndpoint().contains('/oauth/token')) {
                res.setBody('{"access_token":"testToken123","token_type":"Bearer","expires_in":3600}');
            } else if (req.getEndpoint().contains('/ship/v1/shipments')) {
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

    // Mock for API error with "errors[]" list (covers primary error parsing branch)
    private class FedExErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();

            if (req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"testToken123","token_type":"Bearer","expires_in":3600}');
            } else { // shipments
                res.setStatusCode(400);
                res.setBody('{' +
                    '"errors": [{' +
                        '"code": "INVALID.INPUT",' +
                        '"message": "Invalid shipping address"' +
                    '}]' +
                '}');
            }
            return res;
        }
    }

    // Mock for API error with "output.alerts[]" (covers alerts parsing branch)
    private class FedExAlertsErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();

            if (req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"testToken123","token_type":"Bearer","expires_in":3600}');
            } else { // shipments
                res.setStatusCode(409);
                res.setBody('{' +
                    '"output": {' +
                        '"alerts": [{' +
                            '"code":"ALERT.CODE",' +
                            '"message":"Some alert message"' +
                        '}]' +
                    '}' +
                '}');
            }
            return res;
        }
    }

    // Mock for raw non-JSON error (covers fallback branch that abbreviates body)
    private class FedExRawErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"testToken123","token_type":"Bearer","expires_in":3600}');
            } else {
                res.setStatusCode(500);
                res.setBody('Internal Server Error - not JSON');
            }
            return res;
        }
    }

    // Mock for invalid/empty output (200 OK but missing fields)
    private class FedExInvalidResponseMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"testToken123","token_type":"Bearer","expires_in":3600}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"output": {}}');
            }
            return res;
        }
    }

    /* --------------------------
       Tests
       -------------------------- */

    @IsTest
    static void test_processLabel_success_covers_parse_and_pdf_save() {
        seedFedExCmdt('Sandbox');
        Test.setMock(HttpCalloutMock.class, new FedExMultiCalloutMock());

        Account acc = createPersonAccount();
        ContactPointAddress addr = createShippingAddress();
        Case c = createCase(acc, addr);

        FedExLabelProcessor.FlowInput input = new FedExLabelProcessor.FlowInput();
        input.caseId   = c.Id;
        input.poNumber = 'PO123';

        Test.startTest();
        List<FedExLabelProcessor.FlowOutput> outs =
            FedExLabelProcessor.processLabel(new List<FedExLabelProcessor.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outs.size(), 'Expect one FlowOutput');
        System.assertEquals(true, outs[0].isSuccess, 'FlowOutput.isSuccess should be true');
        System.assertEquals('TRACK12345', outs[0].trackingNumber, 'Tracking number should flow through');
        System.assertNotEquals(null, outs[0].labelId, 'Label Id should be populated');

        // Label was created with tracking
        Label__c lbl = [SELECT Id, Master_Tracking_Number__c, Case__c FROM Label__c WHERE Case__c = :c.Id LIMIT 1];
        System.assertEquals('TRACK12345', lbl.Master_Tracking_Number__c, 'Label saved with tracking');

        // ContentVersion created & linked to BOTH Case and Label
        // Fetch the ContentDocumentId via any link to Case or Label
        List<ContentDocumentLink> caseLinks =
            [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :c.Id];
        System.assert(!caseLinks.isEmpty(), 'A file should be linked to the Case');

        // Ensure there is a link to Label as well (same document or another)
        List<ContentDocumentLink> labelLinks =
            [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :lbl.Id];
        System.assert(!labelLinks.isEmpty(), 'A file should be linked to the Label');

        // (Optional) Ensure at least one document appears on both records
        Set<Id> caseDocIds  = new Set<Id>();
        for (ContentDocumentLink l : caseLinks) caseDocIds.add(l.ContentDocumentId);
        Boolean sharedDoc = false;
        for (ContentDocumentLink l : labelLinks) {
            if (caseDocIds.contains(l.ContentDocumentId)) {
                sharedDoc = true; break;
            }
        }
        System.assertEquals(true, sharedDoc, 'The same ContentDocument should be linked to both Case and Label');
    }

    @IsTest
    static void test_processLabel_missingShippingAddress() {
        seedFedExCmdt('Sandbox');

        Account acc = createPersonAccount();
        // No address this time
        Id contactId = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1].Id;

        Case c = new Case(
            AccountId     = acc.Id,
            ContactId     = contactId,
            Subject       = 'Test Case No Address',
            Origin        = 'Phone',
            Status        = 'New',
            SuppliedEmail = acc.PersonEmail
        );
        insert c;

        FedExLabelProcessor.FlowInput input = new FedExLabelProcessor.FlowInput();
        input.caseId = c.Id;

        Test.startTest();
        List<FedExLabelProcessor.FlowOutput> outs =
            FedExLabelProcessor.processLabel(new List<FedExLabelProcessor.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertEquals(false, outs[0].isSuccess);
        System.assert(outs[0].message != null && outs[0].message.contains('Missing Shipping Address'),
                      'Should short-circuit on missing shipping address');
    }

    @IsTest
    static void test_processLabel_labelAlreadyExists_early_return() {
        seedFedExCmdt('Sandbox');

        Account acc = createPersonAccount();
        ContactPointAddress addr = createShippingAddress();
        Case c = createCase(acc, addr);

        Label__c existing = new Label__c(
            Name                    = c.CaseNumber,
            Case__c                 = c.Id,
            Account__c              = acc.Id,
            Master_Tracking_Number__c = 'EXISTING_TRACK123',
            Service_Type__c         = 'FEDEX_GROUND',
            Packaging_Type__c       = 'YOUR_PACKAGING',
            Value__c                = 1,
            Pickup_Type__c          = 'USE_SCHEDULED_PICKUP',
            Units__c                = 'LB',
            Ship_Date_Stamp__c      = Date.today()
        );
        insert existing;

        FedExLabelProcessor.FlowInput input = new FedExLabelProcessor.FlowInput();
        input.caseId = c.Id;

        Test.startTest();
        List<FedExLabelProcessor.FlowOutput> outs =
            FedExLabelProcessor.processLabel(new List<FedExLabelProcessor.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertEquals(true, outs[0].isSuccess);
        System.assertEquals('EXISTING_TRACK123', outs[0].trackingNumber);
        System.assertEquals(existing.Id, outs[0].labelId);
        System.assert(outs[0].message.contains('Label already exists'), 'Should report existing label');
    }

    @IsTest
    static void test_processLabel_withPONumber() {
        seedFedExCmdt('Sandbox');
        Test.setMock(HttpCalloutMock.class, new FedExMultiCalloutMock());

        Account acc = createPersonAccount();
        ContactPointAddress addr = createShippingAddress();
        Case c = createCase(acc, addr);

        FedExLabelProcessor.FlowInput input = new FedExLabelProcessor.FlowInput();
        input.caseId   = c.Id;
        input.poNumber = 'PO-TEST-999';

        Test.startTest();
        List<FedExLabelProcessor.FlowOutput> outs =
            FedExLabelProcessor.processLabel(new List<FedExLabelProcessor.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertEquals(true, outs[0].isSuccess);
        System.assertEquals('TRACK12345', outs[0].trackingNumber);
    }

    @IsTest
    static void test_processLabel_withoutPONumber() {
        seedFedExCmdt('Sandbox');
        Test.setMock(HttpCalloutMock.class, new FedExMultiCalloutMock());

        Account acc = createPersonAccount();
        ContactPointAddress addr = createShippingAddress();
        Case c = createCase(acc, addr);

        FedExLabelProcessor.FlowInput input = new FedExLabelProcessor.FlowInput();
        input.caseId = c.Id; // no PO number

        Test.startTest();
        List<FedExLabelProcessor.FlowOutput> outs =
            FedExLabelProcessor.processLabel(new List<FedExLabelProcessor.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertEquals(true, outs[0].isSuccess);
    }

    @IsTest
    static void test_processLabel_apiError_errorsArray_branch() {
        seedFedExCmdt('Sandbox');
        Test.setMock(HttpCalloutMock.class, new FedExErrorMock());

        Account acc = createPersonAccount();
        ContactPointAddress addr = createShippingAddress();
        Case c = createCase(acc, addr);

        FedExLabelProcessor.FlowInput input = new FedExLabelProcessor.FlowInput();
        input.caseId = c.Id;

        Test.startTest();
        List<FedExLabelProcessor.FlowOutput> outs =
            FedExLabelProcessor.processLabel(new List<FedExLabelProcessor.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertEquals(false, outs[0].isSuccess);
        System.assert(outs[0].message.contains('[INVALID.INPUT]'),
                      'Message should include parsed error code from errors[]');
    }

    @IsTest
    static void test_processLabel_apiError_alerts_branch() {
        seedFedExCmdt('Sandbox');
        Test.setMock(HttpCalloutMock.class, new FedExAlertsErrorMock());

        Account acc = createPersonAccount();
        ContactPointAddress addr = createShippingAddress();
        Case c = createCase(acc, addr);

        FedExLabelProcessor.FlowInput input = new FedExLabelProcessor.FlowInput();
        input.caseId = c.Id;

        Test.startTest();
        List<FedExLabelProcessor.FlowOutput> outs =
            FedExLabelProcessor.processLabel(new List<FedExLabelProcessor.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertEquals(false, outs[0].isSuccess);
        System.assert(outs[0].message.contains('[ALERT.CODE]'),
                      'Message should include parsed code from output.alerts[]');
    }

    @IsTest
    static void test_processLabel_apiError_rawBody_fallback_branch() {
        seedFedExCmdt('Sandbox');
        Test.setMock(HttpCalloutMock.class, new FedExRawErrorMock());

        Account acc = createPersonAccount();
        ContactPointAddress addr = createShippingAddress();
        Case c = createCase(acc, addr);

        FedExLabelProcessor.FlowInput input = new FedExLabelProcessor.FlowInput();
        input.caseId = c.Id;

        Test.startTest();
        List<FedExLabelProcessor.FlowOutput> outs =
            FedExLabelProcessor.processLabel(new List<FedExLabelProcessor.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertEquals(false, outs[0].isSuccess);
        System.assert(outs[0].message.contains('FedEx API Error (Status 500)'),
                      'Should show status in fallback');
        System.assert(outs[0].message.contains('Internal Server Error'),
                      'Fallback should include raw (abbreviated) body');
    }

    @IsTest
    static void test_processLabel_invalidResponse_branch() {
        seedFedExCmdt('Sandbox');
        Test.setMock(HttpCalloutMock.class, new FedExInvalidResponseMock());

        Account acc = createPersonAccount();
        ContactPointAddress addr = createShippingAddress();
        Case c = createCase(acc, addr);

        FedExLabelProcessor.FlowInput input = new FedExLabelProcessor.FlowInput();
        input.caseId = c.Id;

        Test.startTest();
        List<FedExLabelProcessor.FlowOutput> outs =
            FedExLabelProcessor.processLabel(new List<FedExLabelProcessor.FlowInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertEquals(false, outs[0].isSuccess);
        System.assert(outs[0].message.contains('Invalid response'),
                      'Should fail when shipment data cannot be parsed');
    }
}