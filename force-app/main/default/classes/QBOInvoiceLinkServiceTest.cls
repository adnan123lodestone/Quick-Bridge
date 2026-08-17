@IsTest
private class QBOInvoiceLinkServiceTest {
    private class InvoiceLinkFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(503);
            response.setBody('{"Fault":{"Error":[{"Message":"Unavailable"}]}}');
            return response;
        }
    }

    @IsTest
    static void extractsOnlyValidHttpsInvoiceLinks() {
        System.assertEquals(
            'https://pay.example.test/invoice/123',
            QBOInvoiceLinkService.extractInvoiceLink(
                '{"Invoice":{"InvoiceLink":"https://pay.example.test/invoice/123"}}'
            )
        );
        System.assertEquals(
            'https://pay.example.test/invoice/456',
            QBOInvoiceLinkService.extractInvoiceLink(
                '{"Invoice":{"InvoiceLink":{"Link":"https://pay.example.test/invoice/456"}}}'
            )
        );
        System.assertEquals(
            null,
            QBOInvoiceLinkService.extractInvoiceLink(
                '{"Invoice":{"InvoiceLink":"http://pay.example.test/invoice/123"}}'
            )
        );
        System.assertEquals(null, QBOInvoiceLinkService.extractInvoiceLink('{"Invoice":{}}'));
    }

    @IsTest
    static void rejectsMalformedAndNonHttpsUrls() {
        System.assertEquals(false, QBOInvoiceLinkService.isHttpsUrl(null));
        System.assertEquals(false, QBOInvoiceLinkService.isHttpsUrl('not-a-url'));
        System.assertEquals(false, QBOInvoiceLinkService.isHttpsUrl('ftp://pay.example.test/invoice/123'));
        System.assertEquals(true, QBOInvoiceLinkService.isHttpsUrl('https://pay.example.test/invoice/123'));
    }

    @IsTest
    static void treatsPaymentLinkRetrievalFailureAsNonDestructive() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        Test.setMock(HttpCalloutMock.class, new InvoiceLinkFailureMock());
        QBOInvoiceLinkService.testFieldMappings = new List<Field_Mapping__mdt>{
            new Field_Mapping__mdt(
                Integration__c = 'qbonline', SF_Object__c = 'User', SF_Field__c = 'Alias',
                External_Field__c = 'Id', Sync_Direction__c = 'QBO to SF',
                Target_Object_API_Name__c = 'Invoice', Is_Active__c = true
            ),
            new Field_Mapping__mdt(
                Integration__c = 'qbonline', SF_Object__c = 'User', SF_Field__c = 'Alias',
                External_Field__c = 'InvoiceLink', Sync_Direction__c = 'QBO to SF',
                Target_Object_API_Name__c = 'Invoice', Is_Active__c = true
            )
        };

        Test.startTest();
        QBOInvoiceLinkService.InvoiceLinkResult result =
            QBOInvoiceLinkService.retrieveAndPersist(UserInfo.getUserId(), 'User', '123');
        Test.stopTest();

        System.assertEquals(false, result.retrieved);
        System.assertNotEquals(null, result.paymentLink, 'A failed follow-up GET must retain the existing mapped link value.');
        System.assertEquals('QuickBooks invoice synced, but the payment link could not be retrieved.', result.message);
        QBOInvoiceLinkService.testFieldMappings = null;
    }
}
