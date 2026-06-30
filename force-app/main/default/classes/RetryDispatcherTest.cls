@isTest
private class RetryDispatcherTest {

    // ============================================================
    // HTTP Mock for QuickBooks API
    // ============================================================
    private class QBOMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public QBOMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(responseBody);
            return res;
        }
    }

    // ============================================================
    // Helper Methods: Test Data Creation
    // ============================================================
    private static Error_Log__c createErrorLog(Id sourceRecordId, String gatewayName, Boolean isRetryable, Integer retryCount) {
        Error_Log__c log = new Error_Log__c(
            Gateway_Name__c = gatewayName,
            Source_Object__c = 'Account',
            Source_Record_Id__c = sourceRecordId,
            Class_Method_Name__c = 'SomeClass.someMethod',
            Error_Message__c = 'Test error message',
            Is_Retryable__c = isRetryable,
            Retry_Count__c = retryCount,
            Retry_Status__c = 'Pending',
            Retry_History_Notes__c = null
        );
        return log;
    }

    // ============================================================
    // Tests for handlerFor()
    // ============================================================
    @isTest
    static void handlerResolvesThroughConnectorCapabilityMetadata() {
        System.assert(
            RetryDispatcher.handlerFor('QuickBooks') instanceof QBORetryHandler,
            'QuickBooks retry should resolve through retry.handler metadata.'
        );
    }

    @isTest
    static void handlerRejectsUnknownConnector() {
        System.assertEquals(null, RetryDispatcher.handlerFor('Unknown Gateway'));
    }

    // ============================================================
    // Tests for retryError()
    // ============================================================

    @isTest
    static void testRetryError_Success() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, '{}'));

        Error_Log__c log = createErrorLog(acc.Id, 'QuickBooks', true, 0);
        log.Class_Method_Name__c = 'QuickBooksInvoiceBatch.execute'; 
        insert log;

        Test.startTest();
        String result = RetryDispatcher.retryError(log.Id);
        Test.stopTest();

        System.assertEquals('Invoice sync batch enqueued.', result);

        Error_Log__c updatedLog = [SELECT Id, Retry_Status__c, Retry_Count__c, Retry_History_Notes__c FROM Error_Log__c WHERE Id = :log.Id];
        System.assertEquals('Success', updatedLog.Retry_Status__c);
        System.assertEquals(0, updatedLog.Retry_Count__c);
        System.assert(updatedLog.Retry_History_Notes__c.contains('Retry succeeded'));
    }

    @isTest
    static void testRetryError_NotRetryable_ThrowsException() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Error_Log__c log = createErrorLog(acc.Id, 'QuickBooks', false, 0);
        log.Class_Method_Name__c = 'QuickBooksInvoiceBatch.execute';
        insert log;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            RetryDispatcher.retryError(log.Id);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected an exception for a non-retryable log.');
    }

    @isTest
    static void testRetryError_MaxRetryLimitReached_ThrowsException() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Error_Log__c log = createErrorLog(acc.Id, 'QuickBooks', true, 3);
        log.Class_Method_Name__c = 'QuickBooksInvoiceBatch.execute';
        insert log;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            RetryDispatcher.retryError(log.Id);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected an exception when max retry limit is reached.');
    }

    @isTest
    static void testRetryError_UnsupportedGateway_ThrowsException() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Error_Log__c log = createErrorLog(acc.Id, 'UnsupportedGateway', true, 0);
        log.Class_Method_Name__c = 'QuickBooksInvoiceBatch.execute';
        insert log;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            RetryDispatcher.retryError(log.Id);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected an exception for an unsupported gateway.');
    }

    @isTest
    static void testRetryError_HandlerThrowsUnsupportedOperation_UpdatesLog() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Error_Log__c log = createErrorLog(acc.Id, 'QuickBooks', true, 0);
        insert log; // Class_Method_Name__c = 'SomeClass.someMethod' (Unsupported logic)

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            RetryDispatcher.retryError(log.Id);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected an exception due to unsupported operation.');

        Error_Log__c updatedLog = [SELECT Id, Retry_Count__c, Retry_Status__c FROM Error_Log__c WHERE Id = :log.Id];
        System.assertEquals(1, updatedLog.Retry_Count__c);
        System.assertEquals('Pending', updatedLog.Retry_Status__c);
    }

    @isTest
    static void testRetryError_HandlerThrowsToMaxRetry_FailsPermanently() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Error_Log__c log = createErrorLog(acc.Id, 'QuickBooks', true, 2); // Already retried 2 times
        insert log;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            RetryDispatcher.retryError(log.Id);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected an exception on failure.');

        Error_Log__c updatedLog = [SELECT Id, Retry_Count__c, Retry_Status__c FROM Error_Log__c WHERE Id = :log.Id];
        System.assertEquals(3, updatedLog.Retry_Count__c);
        System.assertEquals('Failed', updatedLog.Retry_Status__c);
    }

    @isTest
    static void testRetryError_HandlerThrowsWithNullSourceRecordId() {
        Error_Log__c log = createErrorLog(null, 'QuickBooks', true, 0);
        log.Class_Method_Name__c = 'QuickBooksInvoiceBatch.execute';
        insert log;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            RetryDispatcher.retryError(log.Id);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Expected an exception due to missing Source Record ID.');
    }

    // ============================================================
    // Tests for appendNote()
    // ============================================================
    
    @isTest
    static void testAppendNote_WithEmptyExisting() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, '{}'));

        Error_Log__c log = createErrorLog(acc.Id, 'QuickBooks', true, 0);
        log.Class_Method_Name__c = 'QuickBooksInvoiceBatch.execute';
        insert log;

        Test.startTest();
        RetryDispatcher.retryError(log.Id);
        Test.stopTest();

        Error_Log__c updatedLog = [SELECT Id, Retry_History_Notes__c FROM Error_Log__c WHERE Id = :log.Id];
        System.assert(updatedLog.Retry_History_Notes__c != null);
        System.assert(updatedLog.Retry_History_Notes__c.contains('Retry succeeded'));
    }

    @isTest
    static void testAppendNote_WithExistingNote() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Test.setMock(HttpCalloutMock.class, new QBOMock(200, '{}'));

        Error_Log__c log = createErrorLog(acc.Id, 'QuickBooks', true, 0);
        log.Retry_History_Notes__c = '[2025-01-01 00:00:00] Old note';
        log.Class_Method_Name__c = 'QuickBooksInvoiceBatch.execute';
        insert log;

        Test.startTest();
        RetryDispatcher.retryError(log.Id);
        Test.stopTest();

        Error_Log__c updatedLog = [SELECT Id, Retry_History_Notes__c FROM Error_Log__c WHERE Id = :log.Id];
        System.assert(updatedLog.Retry_History_Notes__c.contains('Old note'));
        System.assert(updatedLog.Retry_History_Notes__c.contains('Retry succeeded'));
    }

    @isTest
    static void testAppendNote_OnFailure() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Error_Log__c log = createErrorLog(acc.Id, 'QuickBooks', true, 0);
        insert log; 

        Test.startTest();
        try {
            RetryDispatcher.retryError(log.Id);
        } catch (Exception e) {
            // Expected
        }
        Test.stopTest();

        Error_Log__c updatedLog = [SELECT Id, Retry_History_Notes__c FROM Error_Log__c WHERE Id = :log.Id];
        System.assert(updatedLog.Retry_History_Notes__c.contains('Retry failed'));
    }

    @isTest
    static void testAppendNote_OnFailureWithExistingNote() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Error_Log__c log = createErrorLog(acc.Id, 'QuickBooks', true, 0);
        log.Retry_History_Notes__c = '[2025-01-01 00:00:00] Previous attempt failed';
        insert log; 

        Test.startTest();
        try {
            RetryDispatcher.retryError(log.Id);
        } catch (Exception e) {
            // Expected
        }
        Test.stopTest();

        Error_Log__c updatedLog = [SELECT Id, Retry_History_Notes__c FROM Error_Log__c WHERE Id = :log.Id];
        System.assert(updatedLog.Retry_History_Notes__c.contains('Previous attempt failed'));
        System.assert(updatedLog.Retry_History_Notes__c.contains('Retry failed'));
    }
}