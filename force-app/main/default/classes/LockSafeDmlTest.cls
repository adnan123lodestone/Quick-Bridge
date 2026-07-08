@IsTest
private class LockSafeDmlTest {
  private class GenericRetryTestException extends Exception {
  }

  private static HttpResponse responseWithStatus(Integer statusCode) {
    HttpResponse response = new HttpResponse();
    response.setStatusCode(statusCode);
    return response;
  }

  private static void assertDecision(
    Integer statusCode,
    Boolean retryable,
    String reasonCode
  ) {
    IntegrationRetryPolicy.RetryDecision decision = IntegrationRetryPolicy.classify(
      responseWithStatus(statusCode)
    );
    System.assertEquals(retryable, decision.retryable);
    System.assertEquals(reasonCode, decision.reasonCode);
    System.assertEquals(statusCode, decision.httpStatusCode);
  }

  @IsTest
  static void permanentFailureIsReported() {
    List<SObject> records = new List<SObject>{ new Account() };

    LockSafeDml.Result result = LockSafeDml.insertRecords(records);

    System.assertEquals(true, result.hasPermanentFailure);
    System.assertEquals(false, result.hasLockFailure);
    System.assert(result.summarizeErrors().contains('REQUIRED_FIELD_MISSING'));
  }

  @IsTest
  static void retryPolicyDetectsLockMessages() {
    System.assertEquals(
      true,
      IntegrationRetryPolicy.isRetryableMessage(
        'UNABLE_TO_LOCK_ROW: row locked'
      )
    );
    System.assertEquals(
      false,
      IntegrationRetryPolicy.isRetryableMessage('Read timed out')
    );
    System.assertEquals(
      false,
      IntegrationRetryPolicy.isRetryableMessage('Required field missing')
    );
    System.assertEquals(true, IntegrationRetryPolicy.isRetryable(429));
    System.assertEquals(true, IntegrationRetryPolicy.isRetryable(503));
    System.assertEquals(true, IntegrationRetryPolicy.isRetryable(500));
    System.assertEquals(true, IntegrationRetryPolicy.isPermanentFailure(400));
    System.assertEquals(true, IntegrationRetryPolicy.isPermanentFailure(422));
    System.assertEquals(false, IntegrationRetryPolicy.isRetryable(404));
    System.assertEquals(false, IntegrationRetryPolicy.isRetryable(401));
    System.assertEquals(false, IntegrationRetryPolicy.isRetryable(422));
    System.assertEquals(
      true,
      IntegrationRetryPolicy.isRetryable(
        IntegrationRetryPolicy.exceptionForStatus(503, 'QBO unavailable')
      )
    );
    System.assertEquals(
      false,
      IntegrationRetryPolicy.isRetryable(
        IntegrationRetryPolicy.exceptionForStatus(422, 'Validation failed')
      )
    );
    Exception unstructuredTimeout = new GenericRetryTestException(
      'Read timed out'
    );
    IntegrationRetryPolicy.RetryDecision unstructuredDecision = IntegrationRetryPolicy.classify(
      unstructuredTimeout
    );
    System.assertEquals(
      false,
      IntegrationRetryPolicy.isRetryable(unstructuredTimeout)
    );
    System.assertEquals(false, unstructuredDecision.retryable);
    System.assertEquals(
      'UNSTRUCTURED_EXCEPTION',
      unstructuredDecision.reasonCode
    );
    System.assertEquals(
      503,
      IntegrationRetryPolicy.httpStatusCodeFromMessage(
        'Callout failed with HTTP 503: unavailable'
      )
    );
    System.assert(IntegrationRetryPolicy.nextAttemptAt(1) > System.now());
  }

  @IsTest
  static void retryPolicyClassifiesHttpResponses() {
    IntegrationRetryPolicy.RetryDecision nullResponseDecision = IntegrationRetryPolicy.classify(
      (HttpResponse) null
    );
    System.assertEquals(false, nullResponseDecision.retryable);
    System.assertEquals('NULL_RESPONSE', nullResponseDecision.reasonCode);

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

    System.assertEquals(
      false,
      IntegrationRetryPolicy.classify((Integer) null).retryable
    );
    System.assertEquals(true, IntegrationRetryPolicy.isRateLimited(429));
    System.assertEquals(
      false,
      IntegrationRetryPolicy.isRetryable((HttpResponse) null)
    );
    System.assertEquals(
      null,
      IntegrationRetryPolicy.httpStatusCodeFromMessage(
        'Status code: not numeric'
      )
    );
  }

  @IsTest
  static void successPathsReportSucceededIds() {
    Account accountRecord = new Account(Name = 'Lock Safe Success');
    LockSafeDml.Result insertResult = LockSafeDml.insertRecords(
      new List<SObject>{ accountRecord }
    );
    System.assertEquals(false, insertResult.hasFailures());
    System.assertEquals(1, insertResult.succeededIds.size());

    accountRecord.Name = 'Lock Safe Updated';
    LockSafeDml.Result updateResult = LockSafeDml.updateRecords(
      new List<SObject>{ accountRecord }
    );
    System.assertEquals(false, updateResult.hasFailures());

    accountRecord.Name = 'Lock Safe Upserted';
    LockSafeDml.Result upsertResult = LockSafeDml.upsertRecords(
      new List<SObject>{ accountRecord }
    );
    System.assertEquals(false, upsertResult.hasFailures());
  }
}
