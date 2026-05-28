@IsTest
private class IntegrationRetryPolicyTest {
    @IsTest
    static void statusCodesClassifyRetryabilityWithoutMessageParsing() {
        Set<Integer> permanentCodes = new Set<Integer>{ 400, 401, 403, 404, 409, 422 };
        for (Integer statusCode : permanentCodes) {
            IntegrationRetryPolicy.RetryDecision decision = IntegrationRetryPolicy.classify(statusCode);
            System.assertEquals(false, decision.retryable, 'HTTP ' + statusCode + ' should be permanent.');
            System.assertEquals(statusCode, decision.httpStatusCode);
        }

        Set<Integer> retryableCodes = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };
        for (Integer statusCode : retryableCodes) {
            IntegrationRetryPolicy.RetryDecision decision = IntegrationRetryPolicy.classify(statusCode);
            System.assertEquals(true, decision.retryable, 'HTTP ' + statusCode + ' should be retryable.');
            System.assertEquals(statusCode, decision.httpStatusCode);
        }
    }

    @IsTest
    static void arbitraryTimeoutTextIsNotRetryableWithoutStatusOrLockSignal() {
        String validationMessage = 'Validation failed: timeout value is required on this record.';

        System.assertEquals(false, IntegrationRetryPolicy.isRetryableMessage(validationMessage));
        System.assertEquals(false, IntegrationRetryPolicy.classify(new AuraHandledException(validationMessage)).retryable);
    }

    @IsTest
    static void lockSignalsRemainRetryableForDmlPaths() {
        String lockMessage = 'UNABLE_TO_LOCK_ROW: unable to obtain exclusive access to this record';

        System.assertEquals(true, IntegrationRetryPolicy.isRetryableMessage(lockMessage));
        System.assertEquals(true, IntegrationRetryPolicy.classify(new DmlException(lockMessage)).retryable);
    }
}
