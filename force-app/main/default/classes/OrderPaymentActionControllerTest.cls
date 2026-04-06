@IsTest
private class OrderPaymentActionControllerTest {
    @IsTest
    static void getOrderPaymentContext_returnsOrderTotal() {
        Account accountRecord = new Account(Name = 'Order Payment Action Account');
        insert accountRecord;

        Order orderRecord = new Order(
            AccountId = accountRecord.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert orderRecord;

        Test.startTest();
        OrderPaymentActionController.OrderPaymentContext context =
            OrderPaymentActionController.getOrderPaymentContext(orderRecord.Id);
        Test.stopTest();

        System.assertEquals(orderRecord.Id, context.orderId);
        System.assertEquals(0, context.totalAmount);
    }

    @IsTest
    static void getOrderPaymentContext_requiresOrderId() {
        Test.startTest();
        try {
            OrderPaymentActionController.getOrderPaymentContext(null);
            System.assert(false, 'Expected AuraHandledException to be thrown.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Script-thrown exception') || e.getMessage().contains('Order Id is required.'));
        }
        Test.stopTest();
    }
}