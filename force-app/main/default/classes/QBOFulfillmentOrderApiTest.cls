@IsTest
private class QBOFulfillmentOrderApiTest {
    @IsTest
    static void returnsASafeFailureForMissingDynamicInputs() {
        QBOFulfillmentOrderApi.InvoiceLinkResult result =
            QBOFulfillmentOrderApi.syncRecordAndGetPaymentLink(null, 'OrderSummary');

        System.assertEquals(false, result.success);
        System.assertEquals(null, result.recordId);
        System.assertEquals(null, result.orderSummaryId);
        System.assertEquals('QuickBooks Invoice sync failed.', result.message);
    }
}
