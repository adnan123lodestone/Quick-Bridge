@IsTest
private class QBOrderBatchTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'QB Order Batch Acc');
        insert acc;

        Contract con = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today(),
            ContractTerm = 12
        );
        insert con;
        con.Status = 'Activated';
        update con;

        Order ord = new Order(
            AccountId = acc.Id,
            ContractId = con.Id,
            Status = 'Draft',
            EffectiveDate = Date.today()
        );
        insert ord;
    }

    @IsTest
    static void testBatchRunsSuccessfully() {
        List<Order> orders = [SELECT Id FROM Order];
        
        Test.startTest();
        QBOrderBatch batchInstance = new QBOrderBatch(orders, true);
        Id batchJobId = Database.executeBatch(batchInstance, 1);
        Test.stopTest();

        System.assertNotEquals(null, batchJobId);
        
        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :batchJobId];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
    }
    
    @IsTest
    static void testExecuteException() {
        List<Order> orders = [SELECT Id FROM Order];
        QBOrderBatch batchInstance = new QBOrderBatch(orders, true);
        
        // Force the exception
        QBOrderBatch.forceExceptionForTest = true;
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            // Call execute directly to hit the catch block
            batchInstance.execute(null, orders);
        } catch (Exception e) {
            exceptionThrown = true;
            System.assertEquals('Forced Exception For Coverage', e.getMessage());
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Exception should have been thrown and caught.');
    }
}