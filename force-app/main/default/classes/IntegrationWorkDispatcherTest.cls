@IsTest
private class IntegrationWorkDispatcherTest {
    @IsTest
    static void dispatcherClaimsOneItemPerLockKey() {
        IntegrationWorkService.enqueue(IntegrationWorkTestFactory.request('Test', 'Noop', 'Account', 'A', 'Same:A'));
        IntegrationWorkService.enqueue(IntegrationWorkTestFactory.request('Test', 'Noop', 'Account', 'B', 'Same:A'));
        IntegrationWorkService.enqueue(IntegrationWorkTestFactory.request('Test', 'Noop', 'Account', 'C', 'Different:C'));

        IntegrationWorkDispatcher.dispatchDueWork();

        System.assertEquals(2, [
            SELECT Count()
            FROM Integration_Work_Item__c
            WHERE Status__c = 'Processing'
        ]);
        System.assertEquals(2, [
            SELECT Count()
            FROM Integration_Work_Lock__c
            WHERE Status__c = 'Locked'
        ]);
    }

    @IsTest
    static void dispatcherDoesNotClaimActiveLease() {
        Integration_Work_Item__c item = IntegrationWorkTestFactory.workItem('Pending', 'Account:ActiveLease');
        insert new Integration_Work_Lock__c(
            Name = 'Account:ActiveLease',
            Lock_Key__c = 'Account:ActiveLease',
            Work_Item__c = item.Id,
            Status__c = 'Locked',
            Processor_Token__c = 'token',
            Lease_Expires_At__c = System.now().addMinutes(10)
        );

        IntegrationWorkDispatcher.dispatchDueWork();

        Integration_Work_Item__c afterDispatch = [
            SELECT Status__c
            FROM Integration_Work_Item__c
            WHERE Id = :item.Id
        ];
        System.assertEquals('Pending', afterDispatch.Status__c);
    }

    @IsTest
    static void dispatcherReclaimsExpiredLease() {
        Integration_Work_Item__c item = IntegrationWorkTestFactory.workItem('Pending', 'Account:ExpiredLease');
        insert new Integration_Work_Lock__c(
            Name = 'Account:ExpiredLease',
            Lock_Key__c = 'Account:ExpiredLease',
            Work_Item__c = item.Id,
            Status__c = 'Locked',
            Processor_Token__c = 'old-token',
            Lease_Expires_At__c = System.now().addMinutes(-10)
        );

        IntegrationWorkDispatcher.dispatchDueWork();

        Integration_Work_Item__c afterDispatch = [
            SELECT Status__c, Processor_Token__c
            FROM Integration_Work_Item__c
            WHERE Id = :item.Id
        ];
        System.assertEquals('Processing', afterDispatch.Status__c);
        System.assertNotEquals('old-token', afterDispatch.Processor_Token__c);
    }
}
