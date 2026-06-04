@IsTest
private class LockSafeDmlTest {
    private class GenericRetryTestException extends Exception {}

    private static HttpResponse responseWithStatus(Integer statusCode) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        return response;
    }

    private static void assertDecision(Integer statusCode, Boolean retryable, String reasonCode) {
        IntegrationRetryPolicy.RetryDecision decision = IntegrationRetryPolicy.classify(responseWithStatus(statusCode));
        System.assertEquals(retryable, decision.retryable, 'HTTP ' + statusCode + ' retryable flag should be ' + retryable);
        System.assertEquals(reasonCode, decision.reasonCode, 'HTTP ' + statusCode + ' reason code should be ' + reasonCode);
        System.assertEquals(statusCode, decision.httpStatusCode, 'HTTP status code should be preserved in the retry decision');
    }

    @IsTest
    static void permanentFailureIsReported() {
        List<SObject> records = new List<SObject>{ new Account() };

        LockSafeDml.Result result = LockSafeDml.insertRecords(records);

        System.assertEquals(true, result.hasPermanentFailure, 'Missing required field should be a permanent failure');
        System.assertEquals(false, result.hasLockFailure, 'Missing required field should not be a lock failure');
        System.assert(result.summarizeErrors().contains('REQUIRED_FIELD_MISSING'), 'Error summary should contain REQUIRED_FIELD_MISSING');
    }

    @IsTest
    static void retryPolicyDetectsLockMessages() {
        System.assertEquals(true, IntegrationRetryPolicy.isRetryableMessage('UNABLE_TO_LOCK_ROW: row locked'), 'Row lock message should be retryable');
        System.assertEquals(true, IntegrationRetryPolicy.isRetryableMessage('Read timed out'), 'Timeout message should be retryable');
        System.assertEquals(false, IntegrationRetryPolicy.isRetryableMessage('Required field missing'), 'Required field message should not be retryable');
        System.assertEquals(true, IntegrationRetryPolicy.isRetryable(429), 'HTTP 429 should be retryable');
        System.assertEquals(true, IntegrationRetryPolicy.isRetryable(503), 'HTTP 503 should be retryable');
        System.assertEquals(true, IntegrationRetryPolicy.isRetryable(500), 'HTTP 500 should be retryable');
        System.assertEquals(true, IntegrationRetryPolicy.isPermanentFailure(400), 'HTTP 400 should be a permanent failure');
        System.assertEquals(true, IntegrationRetryPolicy.isPermanentFailure(422), 'HTTP 422 should be a permanent failure');
        System.assertEquals(false, IntegrationRetryPolicy.isRetryable(404), 'HTTP 404 should not be retryable');
        System.assertEquals(false, IntegrationRetryPolicy.isRetryable(401), 'HTTP 401 should not be retryable');
        System.assertEquals(false, IntegrationRetryPolicy.isRetryable(422), 'HTTP 422 should not be retryable');
        System.assertEquals(true, IntegrationRetryPolicy.isRetryable(IntegrationRetryPolicy.exceptionForStatus(503, 'QBO unavailable')), 'StatusCodeException 503 should be retryable');
        System.assertEquals(false, IntegrationRetryPolicy.isRetryable(IntegrationRetryPolicy.exceptionForStatus(422, 'Validation failed')), 'StatusCodeException 422 should not be retryable');
        Exception unstructuredTimeout = new GenericRetryTestException('Read timed out');
        IntegrationRetryPolicy.RetryDecision unstructuredDecision = IntegrationRetryPolicy.classify(unstructuredTimeout);
        System.assertEquals(false, IntegrationRetryPolicy.isRetryable(unstructuredTimeout), 'Unstructured exception should not be retryable via isRetryable()');
        System.assertEquals(false, unstructuredDecision.retryable, 'Classify should return retryable=false for unstructured exception');
        System.assertEquals('UNSTRUCTURED_EXCEPTION', unstructuredDecision.reasonCode, 'Classify should return UNSTRUCTURED_EXCEPTION for unstructured exception');
        System.assertEquals(503, IntegrationRetryPolicy.httpStatusCodeFromMessage('Callout failed with HTTP 503: unavailable'), 'HTTP status code should be parsed from message');
        System.assert(IntegrationRetryPolicy.nextAttemptAt(1) > System.now(), 'Next attempt should be scheduled in the future');
    }

    @IsTest
    static void retryPolicyClassifiesHttpResponses() {
        IntegrationRetryPolicy.RetryDecision nullResponseDecision = IntegrationRetryPolicy.classify((HttpResponse) null);
        System.assertEquals(false, nullResponseDecision.retryable, 'Null response should not be retryable');
        System.assertEquals('NULL_RESPONSE', nullResponseDecision.reasonCode, 'Null response reason code should be NULL_RESPONSE');

        assertDecision(408, true, 'REQUEST_TIMEOUT');
        assertDecision(429, true, 'RATE_LIMITED');
        assertDecision(503, true, 'SERVICE_UNAVAILABLE');
        assertDecision(502, true, 'SERVER_ERROR');
        assertDecision(400, false, 'BAD_REQUEST');
        assertDecision(401, false, 'UNAUTHORIZED');
        assertDecision(403, false, 'FORBIDDEN');
        assertDecision(404, false, 'NOT_FOUND');
        assertDecision(409, false, 'CONFLICT');
        assertDecision(422, false, 'VALIDATION_ERROR');
        assertDecision(204, false, 'SUCCESS');
        assertDecision(418, false, 'UNCLASSIFIED');

        System.assertEquals(false, IntegrationRetryPolicy.classify((Integer) null).retryable, 'Null integer status should not be retryable');
        System.assertEquals(true, IntegrationRetryPolicy.isRateLimited(429), '429 should be rate-limited');
        System.assertEquals(false, IntegrationRetryPolicy.isRetryable((HttpResponse) null), 'Null response should not be retryable');
        System.assertEquals(null, IntegrationRetryPolicy.httpStatusCodeFromMessage('Status code: not numeric'), 'Non-numeric status should return null');
    }

    @IsTest
    static void successPathsReportSucceededIds() {
        Account accountRecord = new Account(Name = 'Lock Safe Success');
        LockSafeDml.Result insertResult = LockSafeDml.insertRecords(new List<SObject>{ accountRecord });
        System.assertEquals(false, insertResult.hasFailures(), 'Insert should succeed without failures');
        System.assertEquals(1, insertResult.succeededIds.size(), 'One record should be in succeededIds after insert');

        accountRecord.Name = 'Lock Safe Updated';
        LockSafeDml.Result updateResult = LockSafeDml.updateRecords(new List<SObject>{ accountRecord });
        System.assertEquals(false, updateResult.hasFailures(), 'Update should succeed without failures');

        accountRecord.Name = 'Lock Safe Upserted';
        LockSafeDml.Result upsertResult = LockSafeDml.upsertRecords(new List<SObject>{ accountRecord });
        System.assertEquals(false, upsertResult.hasFailures(), 'Upsert should succeed without failures');
    }
}