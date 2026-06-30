@isTest
private class PaymentMethodAdminDeployCallbackTest {
    
    @isTest
    static void testHandleResultWithNullResult() {
        Test.startTest();
        PaymentMethodAdminDeployCallback callbackHandler = new PaymentMethodAdminDeployCallback();
        // Trigger the null result path
        callbackHandler.handleResult(null, null);
        Test.stopTest();

        // Verify that an error log was created via ErrorLogUtility
        List<Error_Log__c> errorLogs = [SELECT Id, Error_Message__c, Error_Category__c FROM Error_Log__c];
        System.assertEquals(1, errorLogs.size(), 'One error log should be created for a null result.');
        System.assertEquals('Deployment Failure', errorLogs[0].Error_Category__c, 'Error category should match.');
        System.assert(errorLogs[0].Error_Message__c.contains('no result'), 'Error message should indicate no result was returned.');
    }

    @isTest
    static void testHandleResultSuccess() {
        // Create a mock successful deployment result
        Metadata.DeployResult mockResult = new Metadata.DeployResult();
        mockResult.status = Metadata.DeployStatus.Succeeded;
        mockResult.id = '0Af000000000000';
        mockResult.details = new Metadata.DeployDetails(); 
        // componentFailures remains null/empty

        Test.startTest();
        PaymentMethodAdminDeployCallback callbackHandler = new PaymentMethodAdminDeployCallback();
        // Trigger the success path
        callbackHandler.handleResult(mockResult, null);
        Test.stopTest();

        // Verify that NO error logs were created
        Integer logCount = [SELECT COUNT() FROM Error_Log__c];
        System.assertEquals(0, logCount, 'No error logs should be created for a successful deployment.');
    }

    @isTest
    static void testHandleResultWithComponentFailures() {
        // Create a mock failed deployment result with details
        Metadata.DeployResult mockResult = new Metadata.DeployResult();
        mockResult.status = Metadata.DeployStatus.Failed;
        mockResult.id = '0Af000000000000';
        
        Metadata.DeployDetails mockDetails = new Metadata.DeployDetails();
        Metadata.DeployMessage mockFailure = new Metadata.DeployMessage();
        mockFailure.fullName = 'TestPaymentMethod';
        mockFailure.problem = 'Syntax Error or Missing Dependency';
        
        mockDetails.componentFailures = new List<Metadata.DeployMessage>{ mockFailure };
        mockResult.details = mockDetails;

        Test.startTest();
        PaymentMethodAdminDeployCallback callbackHandler = new PaymentMethodAdminDeployCallback();
        // Trigger the component failure path
        callbackHandler.handleResult(mockResult, null);
        Test.stopTest();

        // Verify that an error log was created for the specific component failure
        List<Error_Log__c> errorLogs = [SELECT Id, Error_Message__c, External_Reference__c FROM Error_Log__c];
        System.assertEquals(1, errorLogs.size(), 'One error log should be created for the component failure.');
        System.assertEquals('TestPaymentMethod', errorLogs[0].External_Reference__c, 'The external reference should be the component fullName.');
        System.assert(errorLogs[0].Error_Message__c.contains('Syntax Error or Missing Dependency'), 'The error message should contain the exact problem.');
    }
}