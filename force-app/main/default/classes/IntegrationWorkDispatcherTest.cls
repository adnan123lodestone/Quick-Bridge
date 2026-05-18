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

    @IsTest
    static void dispatcherRequiresAllAdditionalLocksToBeFree() {
        IntegrationWorkRequest request = IntegrationWorkTestFactory.request('Test', 'Noop', 'Account', 'MULTI', 'Account:MULTI');
        request.additionalLockKeys = new List<String>{ 'Order:BUSY', 'Account:MULTI' };
        Id itemId = IntegrationWorkService.enqueue(request);

        insert new Integration_Work_Lock__c(
            Name = 'Order:BUSY',
            Lock_Key__c = 'Order:BUSY',
            Status__c = 'Locked',
            Processor_Token__c = 'busy-token',
            Lease_Expires_At__c = System.now().addMinutes(10)
        );

        IntegrationWorkDispatcher.dispatchDueWork();

        Integration_Work_Item__c item = [
            SELECT Status__c
            FROM Integration_Work_Item__c
            WHERE Id = :itemId
        ];
        System.assertEquals('Pending', item.Status__c, 'A busy additional lock should prevent dispatch.');
    }

    @IsTest
    static void dispatcherLocksPrimaryAndAdditionalKeysTogether() {
        IntegrationWorkRequest request = IntegrationWorkTestFactory.request('Test', 'Noop', 'Account', 'LOCKS', 'Account:LOCKS');
        request.additionalLockKeys = new List<String>{ 'Order:LOCKS', 'Product:LOCKS' };
        Id itemId = IntegrationWorkService.enqueue(request);

        IntegrationWorkDispatcher.dispatchDueWork();

        Integration_Work_Item__c item = [
            SELECT Status__c
            FROM Integration_Work_Item__c
            WHERE Id = :itemId
        ];
        System.assertEquals('Processing', item.Status__c);
        System.assertEquals(3, [
            SELECT Count()
            FROM Integration_Work_Lock__c
            WHERE Work_Item__c = :itemId
            AND Status__c = 'Locked'
        ]);
    }

    @IsTest
    static void dispatcherFailsMalformedAdditionalLockJson() {
        Integration_Work_Item__c item = new Integration_Work_Item__c(
            Unique_Key__c = 'Bad|Locks|JSON',
            Status__c = IntegrationWorkService.STATUS_PENDING,
            Integration__c = 'Test',
            Operation__c = 'Noop',
            Source_Object__c = 'Account',
            Source_Record_Id__c = 'BAD',
            Lock_Key__c = 'Account:BAD',
            Additional_Lock_Keys__c = '{"bad":true}',
            Attempt_Count__c = 0,
            Max_Attempts__c = 2
        );
        insert item;

        IntegrationWorkDispatcher.dispatchDueWork();

        Integration_Work_Item__c afterDispatch = [
            SELECT Status__c, Last_Error__c
            FROM Integration_Work_Item__c
            WHERE Id = :item.Id
        ];
        System.assertEquals(IntegrationWorkService.STATUS_FAILED, afterDispatch.Status__c);
        System.assert(afterDispatch.Last_Error__c.contains('Additional_Lock_Keys__c'));
    }
}
