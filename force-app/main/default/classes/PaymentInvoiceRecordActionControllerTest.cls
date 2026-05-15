@IsTest
private class PaymentInvoiceRecordActionControllerTest {
    private class StripeInvoiceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            String endpoint = request.getEndpoint();

            if (endpoint.contains('/customers')) {
                response.setBody('{"id":"cus_invoice_action","object":"customer"}');
            } else if (endpoint.contains('/invoiceitems')) {
                response.setBody('{"id":"ii_invoice_action","object":"invoiceitem"}');
            } else if (endpoint.contains('/finalize')) {
                response.setBody('{"id":"in_invoice_action","object":"invoice","status":"open","hosted_invoice_url":"https://pay.stripe.com/invoice/action"}');
            } else if (endpoint.contains('/invoices')) {
                response.setBody('{"id":"in_invoice_action","object":"invoice","status":"draft"}');
            } else {
                response.setBody('{}');
            }

            return response;
        }
    }

    @IsTest
    static void panelShowsStripeWhenActiveAndMapped() {
        Order orderRecord = createOrderWithAmount();
        PaymentInvoiceRecordActionController.testMappingRows = buildMappingRows(false);

        Test.startTest();
        PaymentInvoiceRecordActionController.PanelData data =
            PaymentInvoiceRecordActionController.getPanelData(orderRecord.Id, 'Order');
        Test.stopTest();

        System.assertEquals(1, data.paymentOptions.size(), 'Stripe should be available for a mapped source object.');
        System.assertEquals('stripe', data.selectedGateway);
    }

    @IsTest
    static void createInvoiceCreatesMappedRecordAndQrFileWithoutEmail() {
        Order orderRecord = createOrderWithAmount();
        PaymentInvoiceRecordActionController.testMappingRows = buildMappingRows(false);
        Test.setMock(HttpCalloutMock.class, new StripeInvoiceMock());

        Test.startTest();
        PaymentInvoiceRecordActionController.CreateInvoiceResult result =
            PaymentInvoiceRecordActionController.createInvoice(orderRecord.Id, 'Order', 'stripe');
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(false, result.emailSent, 'No email should be sent when the email field is not mapped.');
        System.assertNotEquals(null, result.invoiceRecordId, 'A mapped invoice record should be created.');
        System.assertEquals('https://pay.stripe.com/invoice/action', result.hostedInvoiceUrl);

        Invoice__c invoiceRecord = [
            SELECT Order__c, Amount__c, Stripe_Invoice_Link__c, Reference_number__c, Status__c,
                Invoice_Date__c, Payment_QR_Code__c
            FROM Invoice__c
            WHERE Id = :result.invoiceRecordId
            LIMIT 1
        ];
        System.assertEquals(orderRecord.Id, invoiceRecord.Order__c);
        System.assertEquals(orderRecord.Id, invoiceRecord.Reference_number__c);
        System.assertEquals('Open', invoiceRecord.Status__c);
        System.assertEquals(Date.today(), invoiceRecord.Invoice_Date__c);
        System.assertEquals('https://pay.stripe.com/invoice/action', invoiceRecord.Stripe_Invoice_Link__c);
        System.assert(invoiceRecord.Amount__c > 0, 'Mapped invoice amount should be populated.');
        System.assert(invoiceRecord.Payment_QR_Code__c.contains('quickchart.io'), 'QR image HTML should be populated.');

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :result.invoiceRecordId
        ];
        System.assertEquals(1, links.size(), 'A QR file should be attached to the invoice record.');
    }

    @IsTest
    static void createInvoiceMarksEmailSentWhenMappedEmailHasValue() {
        Order orderRecord = createOrderWithAmount();
        PaymentInvoiceRecordActionController.testMappingRows = buildMappingRows(true);
        Test.setMock(HttpCalloutMock.class, new StripeInvoiceMock());

        Test.startTest();
        PaymentInvoiceRecordActionController.CreateInvoiceResult result =
            PaymentInvoiceRecordActionController.createInvoice(orderRecord.Id, 'Order', 'stripe');
        Test.stopTest();

        System.assertEquals(true, result.success, result.message);
        System.assertEquals(true, result.emailSent, 'Email should be marked sent when the mapped email field has a value.');
        System.assertNotEquals(null, result.invoiceRecordId);
    }

    private static Order createOrderWithAmount() {
        Account accountRecord = new Account(Name = 'Invoice Action Customer');
        insert accountRecord;
        Contact contactRecord = new Contact(
            LastName = 'Invoice Recipient',
            Email = 'invoice.recipient@example.com',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Id standardPricebookId = Test.getStandardPricebookId();
        Product2 productRecord = new Product2(Name = 'Invoice Action Product', IsActive = true);
        insert productRecord;
        PricebookEntry pricebookEntry = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 25,
            IsActive = true
        );
        insert pricebookEntry;

        Order orderRecord = new Order(
            AccountId = accountRecord.Id,
            BillToContactId = contactRecord.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        );
        insert orderRecord;

        insert new OrderItem(
            OrderId = orderRecord.Id,
            PricebookEntryId = pricebookEntry.Id,
            Quantity = 2,
            UnitPrice = 25
        );

        return [
            SELECT Id, AccountId, TotalAmount
            FROM Order
            WHERE Id = :orderRecord.Id
            LIMIT 1
        ];
    }

    private static List<Field_Mapping__mdt> buildMappingRows(Boolean includeEmail) {
        List<Field_Mapping__mdt> rows = new List<Field_Mapping__mdt>();
        rows.add(baseRow('PI_Stripe_Source_Setup', 'Source', '__setup__', '__setup__', 'Order', 'Order', null, 'AccountId', includeEmail ? 'BillToContact.Email' : null));
        rows.add(baseRow('PI_Stripe_Invoice_Setup', 'Invoice', '__setup__', '__setup__', 'Order', 'Invoice__c', 'Order__c', null, null));
        rows.add(baseRow('PI_Stripe_Transaction_Setup', 'Transaction', '__setup__', '__setup__', 'Order', 'Portal_Payment_Transaction__c', 'Order__c', null, null));

        rows.add(baseRow('PI_Stripe_Source_001', 'Source', 'TotalAmount', 'amount', 'Order', 'Order', null, null, null));
        rows.add(baseRow('PI_Stripe_Invoice_001', 'Invoice', 'amount', 'Amount__c', 'Order', 'Invoice__c', null, null, null));
        rows.add(baseRow('PI_Stripe_Invoice_002', 'Invoice', 'hostedInvoiceUrl', 'Stripe_Invoice_Link__c', 'Order', 'Invoice__c', null, null, null));
        rows.add(baseRow('PI_Stripe_Invoice_003', 'Invoice', 'referenceNumber', 'Reference_number__c', 'Order', 'Invoice__c', null, null, null));
        rows.add(baseRow('PI_Stripe_Invoice_004', 'Invoice', 'status', 'Status__c', 'Order', 'Invoice__c', null, null, null));
        rows.add(baseRow('PI_Stripe_Invoice_005', 'Invoice', 'invoiceDate', 'Invoice_Date__c', 'Order', 'Invoice__c', null, null, null));

        rows.add(baseRow('PI_Stripe_Txn_001', 'Transaction', 'gatewayEventId', 'Gateway_Event_Id__c', 'Order', 'Portal_Payment_Transaction__c', null, null, null));
        rows.add(baseRow('PI_Stripe_Txn_002', 'Transaction', 'gatewayEventType', 'Gateway_Event_Type__c', 'Order', 'Portal_Payment_Transaction__c', null, null, null));
        rows.add(baseRow('PI_Stripe_Txn_003', 'Transaction', 'gatewayAmount', 'Gateway_Amount__c', 'Order', 'Portal_Payment_Transaction__c', null, null, null));
        rows.add(baseRow('PI_Stripe_Txn_004', 'Transaction', 'gatewayReferenceNumber', 'Gateway_Reference_Number__c', 'Order', 'Portal_Payment_Transaction__c', null, null, null));
        rows.add(baseRow('PI_Stripe_Txn_005', 'Transaction', 'gatewayTransactionId', 'Gateway_Transaction_Id__c', 'Order', 'Portal_Payment_Transaction__c', null, null, null));
        return rows;
    }

    private static Field_Mapping__mdt baseRow(
        String developerName,
        String step,
        String sourceField,
        String targetField,
        String sourceObject,
        String targetObject,
        String sourceLookupOnTarget,
        String customerLookupField,
        String emailField
    ) {
        Field_Mapping__mdt row = new Field_Mapping__mdt();
        row.DeveloperName = developerName;
        row.MasterLabel = developerName;
        row.Integration__c = 'stripe';
        row.Action__c = 'createInvoice';
        row.Mapping_Context__c = 'PaymentInvoice';
        row.Mapping_Step__c = step;
        row.SF_Object__c = sourceObject;
        row.SF_Field__c = sourceField;
        row.External_Field__c = targetField;
        row.Target_Object_API_Name__c = targetObject;
        row.Target_Field_API_Name__c = targetField;
        row.Source_Lookup_On_Target_Field__c = sourceLookupOnTarget;
        row.Source_Customer_Lookup_Field__c = customerLookupField;
        row.Source_Customer_Target_Object__c = customerLookupField == null ? null : 'Account';
        row.Source_Email_Field_API_Name__c = emailField;
        row.Is_Active__c = true;
        return row;
    }
}