@IsTest
private class IntegrationWorkServiceTest {
    @IsTest
    static void duplicateEnqueueCoalescesPendingItem() {
        IntegrationWorkRequest request = IntegrationWorkTestFactory.request('QuickBooks', 'AccountUpsert', 'Account', '001000000000001AAA', 'Account:001000000000001AAA');

        Id firstId = IntegrationWorkService.enqueue(request);
        Id secondId = IntegrationWorkService.enqueue(request);

        System.assertEquals(firstId, secondId, 'Duplicate enqueue should return the same work item.');
        Integration_Work_Item__c item = [
            SELECT Status__c, Coalesced_Count__c, Needs_Reprocess__c
            FROM Integration_Work_Item__c
            WHERE Id = :firstId
        ];
        System.assertEquals('Pending', item.Status__c);
        System.assertEquals(1, item.Coalesced_Count__c);
        System.assertEquals(false, item.Needs_Reprocess__c);
    }

    @IsTest
    static void duplicateEnqueueMarksProcessingForReprocess() {
        IntegrationWorkRequest request = IntegrationWorkTestFactory.request('QuickBooks', 'ProductUpsert', 'Product2', '01t000000000001AAA', 'Product2:01t000000000001AAA');
        Id itemId = IntegrationWorkService.enqueue(request);
        update new Integration_Work_Item__c(Id = itemId, Status__c = 'Processing');

        Id secondId = IntegrationWorkService.enqueue(request);

        System.assertEquals(itemId, secondId);
        Integration_Work_Item__c item = [
            SELECT Status__c, Needs_Reprocess__c, Coalesced_Count__c
            FROM Integration_Work_Item__c
            WHERE Id = :itemId
        ];
        System.assertEquals('Processing', item.Status__c);
        System.assertEquals(true, item.Needs_Reprocess__c);
        System.assertEquals(1, item.Coalesced_Count__c);
    }

    @IsTest
    static void completedItemCanBeRequeued() {
        IntegrationWorkRequest request = IntegrationWorkTestFactory.request('QuickBooks', 'AccountUpsert', 'Account', '001000000000002AAA', 'Account:001000000000002AAA');
        Id itemId = IntegrationWorkService.enqueue(request);
        update new Integration_Work_Item__c(Id = itemId, Status__c = 'Completed', Completed_At__c = System.now());

        IntegrationWorkService.enqueue(request);

        Integration_Work_Item__c item = [
            SELECT Status__c, Attempt_Count__c, Completed_At__c
            FROM Integration_Work_Item__c
            WHERE Id = :itemId
        ];
        System.assertEquals('Pending', item.Status__c);
        System.assertEquals(0, item.Attempt_Count__c);
        System.assertEquals(null, item.Completed_At__c);
    }
}
