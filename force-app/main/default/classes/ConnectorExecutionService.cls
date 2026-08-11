public inherited sharing class ConnectorExecutionService {
  public interface OperationExecutor {
    ConnectorExecutionResult executeInboundPage(
      ConnectorExecutionRequest request
    );
    ConnectorExecutionResult executeOutboundScope(
      ConnectorExecutionRequest request,
      List<SObject> scope
    );
    ConnectorExecutionResult executeSingle(ConnectorExecutionRequest request);
  }

  @TestVisible
  private static Map<String, OperationExecutor> testExecutors = new Map<String, OperationExecutor>();

  public static ConnectorExecutionResult executeInboundPage(
    ConnectorExecutionRequest request
  ) {
    ConnectorExecutionRequest normalizedRequest = normalizeForDirection(
      request,
      ConnectorExecutionRequest.DIRECTION_INBOUND
    );
    OperationExecutor executor = executorFor(normalizedRequest);
    return normalizeResult(executor.executeInboundPage(normalizedRequest));
  }

  public static ConnectorExecutionResult executeOutboundScope(
    ConnectorExecutionRequest request,
    List<SObject> scope
  ) {
    ConnectorExecutionRequest normalizedRequest = normalizeForDirection(
      request,
      ConnectorExecutionRequest.DIRECTION_OUTBOUND
    );
    List<SObject> safeScope = scope == null ? new List<SObject>() : scope;
    validateScope(normalizedRequest, safeScope);
    return normalizeResult(
      executorFor(normalizedRequest)
        .executeOutboundScope(normalizedRequest, safeScope)
    );
  }

  public static ConnectorExecutionResult executeSingle(
    ConnectorExecutionRequest request
  ) {
    ConnectorExecutionRequest normalizedRequest = request == null
      ? null
      : request.normalizedCopy();
    if (normalizedRequest == null) {
      throw new ConnectorExecutionException(
        'Connector execution request is required.'
      );
    }
    return normalizeResult(
      executorFor(normalizedRequest).executeSingle(normalizedRequest)
    );
  }

  public static String buildValidatedSourceQuery(
    ConnectorExecutionRequest request,
    Set<String> requestedFields
  ) {
    ConnectorExecutionRequest normalizedRequest = normalizeForDirection(
      request,
      ConnectorExecutionRequest.DIRECTION_OUTBOUND
    );
    Schema.SObjectType objectType = Schema.getGlobalDescribe()
      .get(normalizedRequest.salesforceObject);
    if (objectType == null) {
      throw new ConnectorExecutionException(
        'Configured Salesforce object is unavailable.'
      );
    }

    Map<String, Schema.SObjectField> availableFields = objectType.getDescribe()
      .fields.getMap();
    Set<String> canonicalFields = new Set<String>{ 'Id' };
    for (
      String requestedField : requestedFields == null
        ? new Set<String>()
        : requestedFields
    ) {
      canonicalFields.add(canonicalFieldName(availableFields, requestedField));
    }
    List<String> selectedFields = new List<String>(canonicalFields);
    selectedFields.sort();

    String queryValue =
      'SELECT ' +
      String.join(selectedFields, ', ') +
      ' FROM ' +
      normalizedRequest.salesforceObject;
    if (
      normalizedRequest.recordIds != null &&
      !normalizedRequest.recordIds.isEmpty()
    ) {
      List<String> idLiterals = new List<String>();
      for (Id recordId : normalizedRequest.recordIds) {
        idLiterals.add(
          '\'' + String.escapeSingleQuotes(String.valueOf(recordId)) + '\''
        );
      }
      queryValue += ' WHERE Id IN (' + String.join(idLiterals, ',') + ')';
    } else if (normalizedRequest.initialSync != true) {
      throw new ConnectorExecutionException(
        'Outbound execution requires record IDs unless initial sync is explicitly enabled.'
      );
    }
    return queryValue + ' ORDER BY Id';
  }

  public static Database.QueryLocator buildQueryLocator(
    ConnectorExecutionRequest request,
    Set<String> requestedFields
  ) {
    ConnectorExecutionRequest normalizedRequest = normalizeForDirection(
      request,
      ConnectorExecutionRequest.DIRECTION_OUTBOUND
    );
    if (
      normalizedRequest.recordIds == null ||
      normalizedRequest.recordIds.isEmpty()
    ) {
      return Database.getQueryLocator(
        buildValidatedSourceQuery(normalizedRequest, requestedFields)
      );
    }

    String literalQuery = buildValidatedSourceQuery(
      normalizedRequest,
      requestedFields
    );
    Integer whereStart = literalQuery.indexOf(' WHERE Id IN (');
    if (whereStart < 0) {
      throw new ConnectorExecutionException(
        'The validated outbound query is missing its record boundary.'
      );
    }
    String boundQuery =
      literalQuery.substring(0, whereStart) +
      ' WHERE Id IN :recordIds ORDER BY Id';
    return Database.getQueryLocatorWithBinds(
      boundQuery,
      new Map<String, Object>{ 'recordIds' => normalizedRequest.recordIds },
      AccessLevel.SYSTEM_MODE
    );
  }

  @TestVisible
  private static void registerTestExecutor(
    ConnectorExecutionRequest request,
    OperationExecutor executor
  ) {
    if (!Test.isRunningTest() || executor == null) {
      throw new ConnectorExecutionException('A test executor is required.');
    }
    ConnectorExecutionRequest normalizedRequest = request.normalizedCopy();
    testExecutors.put(normalizedRequest.operationIdentity(), executor);
  }

  @TestVisible
  private static void clearTestExecutors() {
    testExecutors.clear();
  }

  private static ConnectorExecutionRequest normalizeForDirection(
    ConnectorExecutionRequest request,
    String requiredDirection
  ) {
    if (request == null) {
      throw new ConnectorExecutionException(
        'Connector execution request is required.'
      );
    }
    ConnectorExecutionRequest normalizedRequest = request.normalizedCopy();
    if (normalizedRequest.direction != requiredDirection) {
      throw new ConnectorExecutionException(
        'Connector execution direction does not match the requested runtime path.'
      );
    }
    return normalizedRequest;
  }

  private static OperationExecutor executorFor(
    ConnectorExecutionRequest request
  ) {
    String identity = request.operationIdentity();
    if (Test.isRunningTest() && testExecutors.containsKey(identity)) {
      return testExecutors.get(identity);
    }

    ConnectorOperationRegistry.OperationDefinition definition = ConnectorOperationRegistry.resolve(
      request
    );
    if (String.isBlank(definition.executorClassName)) {
      throw new ConnectorExecutionException(
        'No shared executor is registered for this connector operation.'
      );
    }
    ConnectorAdapterAllowlist.assertAllowed(definition.executorClassName);
    Type executorType = Type.forName(definition.executorClassName);
    if (executorType == null) {
      executorType = Type.forName(
        'QuickBridgeTLG',
        definition.executorClassName
      );
    }
    if (executorType == null) {
      throw new ConnectorExecutionException(
        'Configured connector executor is unavailable.'
      );
    }
    try {
      return (OperationExecutor) executorType.newInstance();
    } catch (Exception exceptionValue) {
      throw new ConnectorExecutionException(
        'Configured connector executor does not implement the shared execution contract.'
      );
    }
  }

  private static void validateScope(
    ConnectorExecutionRequest request,
    List<SObject> scope
  ) {
    Schema.SObjectType expectedType = ConnectorExecutionRequest.resolveSObjectType(
      request.salesforceObject
    );
    for (SObject recordValue : scope) {
      if (recordValue == null || recordValue.getSObjectType() != expectedType) {
        throw new ConnectorExecutionException(
          'Outbound scope contains a record from the wrong Salesforce object.'
        );
      }
    }
  }

  private static String canonicalFieldName(
    Map<String, Schema.SObjectField> availableFields,
    String requestedField
  ) {
    if (
      String.isBlank(requestedField) ||
      !Pattern.matches('^[A-Za-z][A-Za-z0-9_]{0,79}$', requestedField)
    ) {
      throw new ConnectorExecutionException(
        'A requested Salesforce field is invalid.'
      );
    }
    if (availableFields.containsKey(requestedField)) {
      return availableFields.get(requestedField).getDescribe().getName();
    }
    String equivalentField = uniqueEquivalentFieldName(
      requestedField,
      availableFields.keySet()
    );
    if (equivalentField != null) {
      return availableFields.get(equivalentField).getDescribe().getName();
    }
    throw new ConnectorExecutionException(
      'A requested Salesforce field is unavailable.'
    );
  }

  @TestVisible
  private static String uniqueEquivalentFieldName(
    String requestedField,
    Set<String> candidates
  ) {
    if (String.isBlank(requestedField)) {
      return null;
    }
    String normalizedRequest = normalize(requestedField);
    Boolean explicitlyNamespaced = hasFieldNamespace(requestedField);
    String resolvedCandidate;
    for (
      String candidate : candidates == null ? new Set<String>() : candidates
    ) {
      String normalizedCandidate = normalize(candidate);
      Boolean matchesExactly = normalizedCandidate == normalizedRequest;
      Boolean matchesUniquePrefixFreeField =
        !explicitlyNamespaced &&
        hasFieldNamespace(candidate) &&
        normalizedCandidate.endsWith(normalizedRequest);
      if (!matchesExactly && !matchesUniquePrefixFreeField) {
        continue;
      }
      if (resolvedCandidate != null && resolvedCandidate != candidate) {
        throw new ConnectorExecutionException(
          'A requested Salesforce field is ambiguous across installed namespaces.'
        );
      }
      resolvedCandidate = candidate;
    }
    return resolvedCandidate;
  }

  private static Boolean hasFieldNamespace(String fieldName) {
    if (String.isBlank(fieldName) || !fieldName.endsWith('__c')) {
      return false;
    }
    return fieldName.substring(0, fieldName.length() - 3).contains('__');
  }

  private static ConnectorExecutionResult normalizeResult(
    ConnectorExecutionResult result
  ) {
    if (result == null) {
      throw new ConnectorExecutionException(
        'Connector executor returned no result.'
      );
    }
    result.processedCount = safeCount(result.processedCount);
    result.successfulCount = safeCount(result.successfulCount);
    result.failedCount = safeCount(result.failedCount);
    Integer accounted = result.successfulCount + result.failedCount;
    if (result.processedCount < accounted) {
      result.processedCount = accounted;
    }
    result.retryable = result.retryable == true;
    if (result.retryDelaySeconds != null) {
      result.retryDelaySeconds = Math.max(
        0,
        Math.min(86400, result.retryDelaySeconds)
      );
    }
    if (result.errorSummary != null) {
      String safeError = ConnectorExecutionResult.sanitizeError(
        result.errorSummary
      );
      result.errorSummary = String.isBlank(safeError)
        ? null
        : (safeError.length() <= 2000
            ? safeError
            : safeError.substring(0, 1997) + '...');
    }
    return result;
  }

  private static Integer safeCount(Integer value) {
    return value == null || value < 0 ? 0 : value;
  }

  private static String normalize(String value) {
    return String.isBlank(value)
      ? ''
      : value.toLowerCase().replaceAll('[^a-z0-9]', '');
  }

  public class ConnectorExecutionException extends Exception {
  }
}
