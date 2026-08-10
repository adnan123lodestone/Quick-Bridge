@isTest
private class QBOrderSummaryTriggerHandlerTest {

    @isTest
    static void testHandlerMethodsWhenOrderSummaryNotPresentOrNull() {
        Test.startTest();
        QBOrderSummaryTriggerHandler.handleOrderSummaryTrigger(null, null, false);
        QBOrderSummaryTriggerHandler.handleOrderItemSummaryTrigger(null);
        QBOrderSummaryTriggerHandler.syncOrderSummariesAsync(null);
        QBOrderSummaryTriggerHandler.syncOrderSummariesAsync(new Set<Id>());
        Test.stopTest();

        System.assertEquals(false, QBOrderSummaryTriggerHandler.isProcessing);
    }

    @isTest
    static void testHandlerWithMockRecords() {
        Account acc = new Account(Name = 'Test Trigger Account');
        insert acc;

        QBOrderSummaryTriggerHandler.isProcessing = false;

        Test.startTest();
        QBOrderSummaryTriggerHandler.handleOrderSummaryTrigger(new List<SObject>{ acc }, new Map<Id, SObject>{ acc.Id => acc }, true);
        QBOrderSummaryTriggerHandler.handleOrderItemSummaryTrigger(new List<SObject>{ acc });
        QBOrderSummaryTriggerHandler.syncOrderSummariesAsync(new Set<Id>{ acc.Id });
        Test.stopTest();

        System.assertEquals(false, QBOrderSummaryTriggerHandler.isProcessing);
    }

    @isTest
    static void testHandlerRecursionFlagPreventer() {
        QBOrderSummaryTriggerHandler.isProcessing = true;

        Test.startTest();
        QBOrderSummaryTriggerHandler.handleOrderSummaryTrigger(new List<SObject>(), null, true);
        QBOrderSummaryTriggerHandler.handleOrderItemSummaryTrigger(new List<SObject>());
        Test.stopTest();

        QBOrderSummaryTriggerHandler.isProcessing = false;
        System.assertEquals(false, QBOrderSummaryTriggerHandler.isProcessing);
    }
}