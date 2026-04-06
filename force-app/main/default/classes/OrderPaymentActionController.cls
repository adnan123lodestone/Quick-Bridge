public with sharing class OrderPaymentActionController {
    public class OrderPaymentContext {
        @AuraEnabled public Id orderId { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static OrderPaymentContext getOrderPaymentContext(Id orderId) {
        if (orderId == null) {
            throw new AuraHandledException('Order Id is required.');
        }

        Order orderRecord = [
            SELECT Id, TotalAmount
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];

        OrderPaymentContext context = new OrderPaymentContext();
        context.orderId = orderRecord.Id;
        context.totalAmount = orderRecord.TotalAmount;
        return context;
    }
}