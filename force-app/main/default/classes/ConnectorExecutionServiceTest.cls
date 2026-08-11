@IsTest
private class ConnectorExecutionServiceTest {
  private class RecordingExecutor implements ConnectorExecutionService.OperationExecutor {
    public ConnectorExecutionResult executeInboundPage(
      ConnectorExecutionRequest request
    ) {
      ConnectorExecutionResult result = ConnectorExecutionResult.success();
      result.processedCount = 2;
      result.successfulCount = 2;
      result.nextCursor = request.cursor == null ? 'page-2' : null;
      return result;
    }

    public ConnectorExecutionResult executeOutboundScope(
      ConnectorExecutionRequest request,
      List<SObject> scope
    ) {
      ConnectorExecutionResult result = ConnectorExecutionResult.success();
      result.processedCount = scope.size();
      result.successfulCount = scope.size();
      return result;
    }

    public ConnectorExecutionResult executeSingle(
      ConnectorExecutionRequest request
    ) {
      ConnectorExecutionResult result = ConnectorExecutionResult.success();
      result.processedCount = 1;
      result.successfulCount = 1;
      return result;
    }
  }

  private class NullExecutor implements ConnectorExecutionService.OperationExecutor {
    public ConnectorExecutionResult executeInboundPage(
      ConnectorExecutionRequest request
    ) {
      return null;
    }

    public ConnectorExecutionResult executeOutboundScope(
      ConnectorExecutionRequest request,
      List<SObject> scope
    ) {
      return null;
    }

    public ConnectorExecutionResult executeSingle(
      ConnectorExecutionRequest request
    ) {
      return null;
    }
  }

  private class DirtyResultExecutor implements ConnectorExecutionService.OperationExecutor {
    public ConnectorExecutionResult executeInboundPage(
      ConnectorExecutionRequest request
    ) {
      return dirtyResult();
    }

    public ConnectorExecutionResult executeOutboundScope(
      ConnectorExecutionRequest request,
      List<SObject> scope
    ) {
      return dirtyResult();
    }

    public ConnectorExecutionResult executeSingle(
      ConnectorExecutionRequest request
    ) {
      return dirtyResult();
    }

    private ConnectorExecutionResult dirtyResult() {
      ConnectorExecutionResult result = new ConnectorExecutionResult();
      result.processedCount = -1;
      result.successfulCount = 2;
      result.failedCount = 1;
      result.retryDelaySeconds = 90000;
      result.errorSummary = 'password="hidden"\r\n' + 'x'.repeat(2100);
      return result;
    }
  }

  @IsTest
  static void dispatchesAllSharedExecutionShapes() {
    registerOperation();
    ConnectorExecutionRequest inbound = requestFor('Inbound');
    ConnectorExecutionService.registerTestExecutor(
      inbound,
      new RecordingExecutor()
    );

    ConnectorExecutionResult inboundResult = ConnectorExecutionService.executeInboundPage(
      inbound
    );
    System.assertEquals(2, inboundResult.successfulCount);
    System.assertEquals('page-2', inboundResult.nextCursor);

    ConnectorExecutionRequest outbound = requestFor('Outbound');
    outbound.recordIds.add((Id) '001000000000001AAA');
    ConnectorExecutionResult outboundResult = ConnectorExecutionService.executeOutboundScope(
      outbound,
      new List<SObject>{ new Account(Id = (Id) '001000000000001AAA') }
    );
    System.assertEquals(1, outboundResult.successfulCount);

    ConnectorExecutionResult singleResult = ConnectorExecutionService.executeSingle(
      outbound
    );
    System.assertEquals(1, singleResult.processedCount);
  }

  @IsTest
  static void buildsOnlySchemaValidatedQueries() {
    registerOperation();
    ConnectorExecutionRequest request = requestFor('Outbound');
    request.recordIds.add((Id) '001000000000001AAA');

    String queryValue = ConnectorExecutionService.buildValidatedSourceQuery(
      request,
      new Set<String>{ 'Name', 'Industry' }
    );

    System.assert(queryValue.startsWith('SELECT '));
    System.assert(queryValue.contains(' FROM Account WHERE Id IN ('));
    System.assert(queryValue.contains('Industry'));
    System.assert(queryValue.contains('Name'));
    System.assert(queryValue.endsWith(' ORDER BY Id'));

    try {
      ConnectorExecutionService.buildValidatedSourceQuery(
        request,
        new Set<String>{ 'Name FROM Contact' }
      );
      System.assert(false, 'SOQL injection must be rejected.');
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('field'));
    }

    ConnectorExecutionRequest unbounded = requestFor('Outbound');
    try {
      ConnectorExecutionService.buildValidatedSourceQuery(
        unbounded,
        new Set<String>{ 'Name' }
      );
      System.assert(
        false,
        'Unbounded outbound query must require explicit initial sync.'
      );
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('record IDs'));
    }
    unbounded.initialSync = true;
    System.assert(
      ConnectorExecutionService.buildValidatedSourceQuery(
          unbounded,
          new Set<String>{ 'Name' }
        )
        .contains(' FROM Account ORDER BY Id')
    );
  }

  @IsTest
  static void rejectsWrongDirectionScopeAndMissingExecutor() {
    registerOperation();
    ConnectorExecutionRequest inbound = requestFor('Inbound');
    try {
      ConnectorExecutionService.executeOutboundScope(
        inbound,
        new List<SObject>()
      );
      System.assert(false, 'Wrong runtime direction must be rejected.');
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('direction'));
    }

    ConnectorExecutionRequest outbound = requestFor('Outbound');
    outbound.recordIds.add((Id) '001000000000001AAA');
    ConnectorExecutionService.registerTestExecutor(
      outbound,
      new RecordingExecutor()
    );
    try {
      ConnectorExecutionService.executeOutboundScope(
        outbound,
        new List<SObject>{ new Contact() }
      );
      System.assert(false, 'Mixed object scope must be rejected.');
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('wrong Salesforce object'));
    }

    ConnectorExecutionService.clearTestExecutors();
    try {
      ConnectorExecutionService.executeSingle(outbound);
      System.assert(false, 'An unregistered shared executor must fail closed.');
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('No shared executor'));
    }
  }

  @IsTest
  static void normalizesExecutorResultsAndRejectsNullInputs() {
    registerOperation();
    ConnectorExecutionRequest inbound = requestFor('Inbound');
    ConnectorExecutionService.registerTestExecutor(
      inbound,
      new DirtyResultExecutor()
    );

    ConnectorExecutionResult result = ConnectorExecutionService.executeInboundPage(
      inbound
    );
    System.assertEquals(3, result.processedCount);
    System.assertEquals(86400, result.retryDelaySeconds);
    System.assertEquals(2000, result.errorSummary.length());
    System.assert(!result.errorSummary.contains('hidden'));

    ConnectorExecutionService.clearTestExecutors();
    ConnectorExecutionService.registerTestExecutor(inbound, new NullExecutor());
    try {
      ConnectorExecutionService.executeInboundPage(inbound);
      System.assert(false, 'Null executor results must fail closed.');
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('no result'));
    }

    try {
      ConnectorExecutionService.executeSingle(null);
      System.assert(false, 'Null single-record requests must be rejected.');
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('request is required'));
    }
    try {
      ConnectorExecutionService.executeInboundPage(null);
      System.assert(false, 'Null inbound requests must be rejected.');
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('request is required'));
    }
  }

  @IsTest
  static void validatesEmptyAndUnavailableFieldSelections() {
    registerOperation();
    ConnectorExecutionRequest request = requestFor('Outbound');
    request.initialSync = true;
    System.assertEquals(
      'SELECT Id FROM Account ORDER BY Id',
      ConnectorExecutionService.buildValidatedSourceQuery(request, null)
    );
    try {
      ConnectorExecutionService.buildValidatedSourceQuery(
        request,
        new Set<String>{ 'Definitely_Not_A_Field__c' }
      );
      System.assert(false, 'Unavailable fields must be rejected.');
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('unavailable'));
    }

    ConnectorExecutionService.buildQueryLocator(
      request,
      new Set<String>{ 'Name' }
    );

    request.initialSync = false;
    request.recordIds = new List<Id>{ (Id) '001000000000001AAA' };
    ConnectorExecutionService.buildQueryLocator(
      request,
      new Set<String>{ 'Name' }
    );
  }

  @IsTest
  static void prefixFreeFieldsResolveOnlyToOneNamespace() {
    System.assertEquals(
      'packageone__External_Id__c',
      ConnectorExecutionService.uniqueEquivalentFieldName(
        'External_Id__c',
        new Set<String>{ 'packageone__External_Id__c', 'Name' }
      )
    );
    System.assertEquals(
      null,
      ConnectorExecutionService.uniqueEquivalentFieldName(
        'packageone__External_Id__c',
        new Set<String>{ 'packagetwo__External_Id__c' }
      ),
      'An explicitly namespaced field must not suffix-match another namespace.'
    );
    try {
      ConnectorExecutionService.uniqueEquivalentFieldName(
        'External_Id__c',
        new Set<String>{
          'packageone__External_Id__c',
          'packagetwo__External_Id__c'
        }
      );
      System.assert(false, 'Ambiguous prefix-free fields must be rejected.');
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('ambiguous'));
    }
  }

  @IsTest
  static void supportsNullScopesAndRejectsNullExecutorRegistration() {
    registerOperation();
    ConnectorExecutionRequest outbound = requestFor('Outbound');
    ConnectorExecutionService.registerTestExecutor(
      outbound,
      new RecordingExecutor()
    );
    ConnectorExecutionResult result = ConnectorExecutionService.executeOutboundScope(
      outbound,
      null
    );
    System.assertEquals(0, result.processedCount);

    try {
      ConnectorExecutionService.registerTestExecutor(outbound, null);
      System.assert(false, 'Null executors must be rejected.');
    } catch (ConnectorExecutionService.ConnectorExecutionException expected) {
      System.assert(expected.getMessage().contains('test executor'));
    }
  }

  private static void registerOperation() {
    ConnectorOperationRegistry.OperationDefinition definition = new ConnectorOperationRegistry.OperationDefinition();
    definition.connectorKey = 'qbo';
    definition.operationKey = 'AccountUpsert';
    definition.direction = 'Bidirectional';
    definition.salesforceObject = 'Account';
    definition.externalEntity = 'Customer';
    ConnectorOperationRegistry.registerTestOperation(definition);
  }

  private static ConnectorExecutionRequest requestFor(String direction) {
    ConnectorExecutionRequest request = new ConnectorExecutionRequest();
    request.connectorKey = 'quickbooks';
    request.operationKey = 'AccountUpsert';
    request.direction = direction;
    request.salesforceObject = 'Account';
    request.externalEntity = 'Customers';
    return request;
  }
}
