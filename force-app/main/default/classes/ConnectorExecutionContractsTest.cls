@IsTest
private class ConnectorExecutionContractsTest {
  @IsTest
  static void requestNormalizesRegisteredAliasAndPreservesContext() {
    registerAccountOperation('AccountUpsert', 'Bidirectional');
    ConnectorExecutionRequest request = accountRequest(
      'QuickBooks Online',
      'AccountUpsert',
      'out',
      'Customers'
    );
    request.recordIds.add((Id) '001000000000001AAA');
    request.cursor = 'next-page';
    request.sinceValue = Datetime.newInstance(2026, 1, 2, 3, 4, 5);
    request.initialSync = true;
    request.scopeSize = 50;
    request.payload = '{"safe":true}';
    request.correlationKey = 'correlation-1';
    request.leaseToken = 'lease-1';
    request.pageNumber = 2;
    request.retryAttempt = 1;

    ConnectorExecutionRequest normalized = request.normalizedCopy();

    System.assertEquals('qbo', normalized.connectorKey);
    System.assertEquals('Outbound', normalized.direction);
    System.assertEquals('Account', normalized.salesforceObject);
    System.assertEquals('Customer', normalized.externalEntity);
    System.assertEquals(1, normalized.recordIds.size());
    System.assertEquals('next-page', normalized.cursor);
    System.assertEquals(request.sinceValue, normalized.sinceValue);
    System.assertEquals(50, normalized.scopeSize);
    System.assertEquals('correlation-1', normalized.correlationKey);
    System.assertEquals('lease-1', normalized.leaseToken);
    System.assertEquals(2, normalized.pageNumber);
    System.assertEquals(1, normalized.retryAttempt);
  }

  @IsTest
  static void requestRejectsUnsupportedAndUnsafeValues() {
    registerAccountOperation('AccountUpsert', 'Bidirectional');

    assertRegistryFailure(
      accountRequest('qbo', 'DeleteEverything', 'Inbound', 'Customer')
    );
    assertRegistryFailure(
      accountRequest('qbo', 'AccountUpsert', 'Sideways', 'Customer')
    );

    ConnectorExecutionRequest injectedObject = accountRequest(
      'qbo',
      'AccountUpsert',
      'Inbound',
      'Customer'
    );
    injectedObject.salesforceObject = 'Account WHERE Name != null';
    assertRegistryFailure(injectedObject);

    ConnectorExecutionRequest injectedEntity = accountRequest(
      'qbo',
      'AccountUpsert',
      'Inbound',
      'Customer'
    );
    injectedEntity.externalEntity = 'Customer; DROP';
    assertRegistryFailure(injectedEntity);

    ConnectorExecutionRequest wrongIdType = accountRequest(
      'qbo',
      'AccountUpsert',
      'Outbound',
      'Customer'
    );
    wrongIdType.recordIds.add((Id) '003000000000001AAA');
    try {
      wrongIdType.validate();
      System.assert(false, 'Expected a mismatched record ID to be rejected.');
    } catch (ConnectorExecutionRequest.ConnectorExecutionRequestException expected) {
      System.assert(expected.getMessage().contains('record ID'));
    }
  }

  @IsTest
  static void resultBoundsErrorsAndMergesRetryState() {
    ConnectorExecutionResult first = ConnectorExecutionResult.failed(
      'Authorization: Bearer secret-value client_secret=hidden',
      true,
      90000
    );
    first.retryRecordIds.add((Id) '001000000000001AAA');
    ConnectorExecutionResult second = new ConnectorExecutionResult();
    second.processedCount = 2;
    second.successfulCount = 2;
    second.retryRecordIds.add((Id) '001000000000001AAA');
    second.retryRecordIds.add((Id) '001000000000002AAA');

    first.mergeFrom(second);

    System.assertEquals(3, first.processedCount);
    System.assertEquals(2, first.successfulCount);
    System.assertEquals(1, first.failedCount);
    System.assertEquals(86400, first.retryDelaySeconds);
    System.assertEquals(2, first.retryRecordIds.size());
    System.assert(!first.errorSummary.contains('secret-value'));
    System.assert(!first.errorSummary.contains('hidden'));
    System.assert(first.errorSummary.contains('[REDACTED]'));

    first.addError('x'.repeat(3000));
    System.assertEquals(2000, first.errorSummary.length());
  }

  @IsTest
  static void resolvesRepositoryMappingsAndCompatibilityOperations() {
    ConnectorOperationRegistry.clearTestOperations();
    ConnectorExecutionRequest qboRequest = accountRequest(
      'qbo',
      'CustomerSync',
      'from salesforce',
      'Customers'
    );
    ConnectorOperationRegistry.OperationDefinition qboDefinition = ConnectorOperationRegistry.resolve(
      qboRequest
    );
    System.assertEquals('qbo', qboDefinition.connectorKey);
    System.assertEquals('Account', qboDefinition.salesforceObject);

    System.assertEquals(
      'Inbound',
      ConnectorOperationRegistry.normalizeDirection('to salesforce')
    );

    ConnectorExecutionRequest klaviyoRequest = new ConnectorExecutionRequest();
    klaviyoRequest.connectorKey = 'klaviyo';
    klaviyoRequest.operationKey = 'Profiles';
    klaviyoRequest.direction = 'to salesforce';
    klaviyoRequest.salesforceObject = 'Account';
    klaviyoRequest.externalEntity = 'Profiles';
    ConnectorOperationRegistry.OperationDefinition klaviyoDefinition = ConnectorOperationRegistry.resolve(
      klaviyoRequest
    );
    System.assertEquals('Profile', klaviyoDefinition.externalEntity);
  }

  @IsTest
  static void registryFailsClosedForInvalidDefinitionsAndConnectors() {
    try {
      ConnectorOperationRegistry.resolve(null);
      System.assert(false, 'Null requests must be rejected.');
    } catch (ConnectorOperationRegistry.ConnectorOperationRegistryException expected) {
      System.assert(expected.getMessage().contains('required'));
    }

    ConnectorExecutionRequest unknown = accountRequest(
      'unknown connector',
      'AccountUpsert',
      'Inbound',
      'Customer'
    );
    assertRegistryFailure(unknown);

    ConnectorOperationRegistry.OperationDefinition invalid = new ConnectorOperationRegistry.OperationDefinition();
    invalid.connectorKey = 'qbo';
    invalid.operationKey = 'AccountUpsert';
    invalid.direction = 'Inbound';
    invalid.salesforceObject = 'Account';
    invalid.externalEntity = 'Customer';
    invalid.maximumPages = 201;
    try {
      ConnectorOperationRegistry.registerTestOperation(invalid);
      System.assert(false, 'Unsafe page limits must be rejected.');
    } catch (ConnectorOperationRegistry.ConnectorOperationRegistryException expected) {
      System.assert(expected.getMessage().contains('Maximum pages'));
    }
  }

  @IsTest
  static void registryDoesNotConfuseDifferentObjectNamespaces() {
    System.assert(
      ConnectorOperationRegistry.equivalentObject(
        'Purchase_Order__c',
        'QuickBridgeTLG__Purchase_Order__c'
      ),
      'A prefix-free package definition must match its namespaced object.'
    );
    System.assert(
      !ConnectorOperationRegistry.equivalentObject(
        'FirstPackage__Purchase_Order__c',
        'SecondPackage__Purchase_Order__c'
      ),
      'Objects from different explicit namespaces must never be interchangeable.'
    );
    try {
      ConnectorOperationRegistry.uniqueEquivalentObjectName(
        'Purchase_Order__c',
        new Set<String>{
          'FirstPackage__Purchase_Order__c',
          'SecondPackage__Purchase_Order__c'
        }
      );
      System.assert(
        false,
        'Ambiguous prefix-free object names must fail closed.'
      );
    } catch (ConnectorOperationRegistry.ConnectorOperationRegistryException expected) {
      System.assert(expected.getMessage().contains('ambiguous'));
    }
  }

  @IsTest
  static void requestAndResultEdgeContractsFailSafely() {
    registerAccountOperation('AccountUpsert', 'Bidirectional');
    ConnectorExecutionRequest valid = accountRequest(
      'qbo',
      'AccountUpsert',
      'Inbound',
      'Customer'
    );
    System.assertEquals(valid, valid.validate());
    System.assert(String.isNotBlank(valid.operationIdentity()));

    for (Integer invalidScope : new List<Integer>{ 0, 2001 }) {
      ConnectorExecutionRequest invalid = accountRequest(
        'qbo',
        'AccountUpsert',
        'Inbound',
        'Customer'
      );
      invalid.scopeSize = invalidScope;
      assertRequestFailure(invalid);
    }
    ConnectorExecutionRequest invalidRetry = accountRequest(
      'qbo',
      'AccountUpsert',
      'Inbound',
      'Customer'
    );
    invalidRetry.retryAttempt = 6;
    assertRequestFailure(invalidRetry);
    ConnectorExecutionRequest longCorrelation = accountRequest(
      'qbo',
      'AccountUpsert',
      'Inbound',
      'Customer'
    );
    longCorrelation.correlationKey = 'x'.repeat(256);
    assertRequestFailure(longCorrelation);

    ConnectorExecutionResult result = ConnectorExecutionResult.success();
    System.assertEquals(false, result.hasFailures());
    System.assertEquals(result, result.mergeFrom(null));
    System.assertEquals(result, result.addError(null));
    ConnectorExecutionResult other = new ConnectorExecutionResult();
    other.nextCursor = 'next';
    other.asyncJobId = (Id) '707000000000001AAA';
    other.retryDelaySeconds = 10;
    other.retryable = true;
    result.mergeFrom(other);
    System.assertEquals('next', result.nextCursor);
    System.assertEquals(other.asyncJobId, result.asyncJobId);
    System.assertEquals(10, result.retryDelaySeconds);
  }

  private static void registerAccountOperation(
    String operation,
    String direction
  ) {
    ConnectorOperationRegistry.OperationDefinition definition = new ConnectorOperationRegistry.OperationDefinition();
    definition.connectorKey = 'qbo';
    definition.operationKey = operation;
    definition.direction = direction;
    definition.salesforceObject = 'Account';
    definition.externalEntity = 'Customer';
    ConnectorOperationRegistry.registerTestOperation(definition);
  }

  private static ConnectorExecutionRequest accountRequest(
    String connector,
    String operation,
    String direction,
    String externalEntity
  ) {
    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = connector;
    request.operationKey = operation;
    request.direction = direction;
    request.salesforceObject = 'Account';
    request.externalEntity = externalEntity;
    return request;
  }

  private static void assertRegistryFailure(ConnectorExecutionRequest request) {
    try {
      request.validate();
      System.assert(false, 'Expected connector request validation to fail.');
    } catch (ConnectorOperationRegistry.ConnectorOperationRegistryException expected) {
      System.assert(String.isNotBlank(expected.getMessage()));
    }
  }

  private static void assertRequestFailure(ConnectorExecutionRequest request) {
    try {
      request.validate();
      System.assert(false, 'Expected connector request limits to fail.');
    } catch (ConnectorExecutionRequest.ConnectorExecutionRequestException expected) {
      System.assert(String.isNotBlank(expected.getMessage()));
    }
  }
}
