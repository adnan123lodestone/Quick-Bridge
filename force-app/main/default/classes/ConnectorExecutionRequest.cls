public inherited sharing class ConnectorExecutionRequest {
  public static final String DIRECTION_INBOUND = 'Inbound';
  public static final String DIRECTION_OUTBOUND = 'Outbound';

  public String connectorKey { get; set; }
  public String operationKey { get; set; }
  public String direction { get; set; }
  public String salesforceObject { get; set; }
  public String externalEntity { get; set; }
  public List<Id> recordIds { get; set; }
  public String cursor { get; set; }
  public Datetime sinceValue { get; set; }
  public Boolean initialSync { get; set; }
  public Integer scopeSize { get; set; }
  public String payload { get; set; }
  public String correlationKey { get; set; }
  public Id scheduleId { get; set; }
  public String leaseToken { get; set; }
  public Integer pageNumber { get; set; }
  public Integer retryAttempt { get; set; }

  public ConnectorExecutionRequest() {
    recordIds = new List<Id>();
    initialSync = false;
    scopeSize = 100;
    pageNumber = 1;
    retryAttempt = 0;
  }

  public ConnectorExecutionRequest validate() {
    ConnectorOperationRegistry.OperationDefinition definition = ConnectorOperationRegistry.resolve(
      this
    );
    validateLimits();
    validateRecordIds(definition);
    return this;
  }

  public ConnectorExecutionRequest normalizedCopy() {
    ConnectorOperationRegistry.OperationDefinition definition = ConnectorOperationRegistry.resolve(
      this
    );
    ConnectorExecutionRequest copyValue = copyOf(this);
    copyValue.connectorKey = definition.connectorKey;
    copyValue.operationKey = definition.operationKey;
    copyValue.direction = ConnectorOperationRegistry.normalizeDirection(
      direction
    );
    copyValue.salesforceObject = definition.salesforceObject;
    copyValue.externalEntity = definition.externalEntity;
    copyValue.recordIds = recordIds == null
      ? new List<Id>()
      : new List<Id>(recordIds);
    copyValue.validateLimits();
    copyValue.validateRecordIds(definition);
    return copyValue;
  }

  public String operationIdentity() {
    ConnectorOperationRegistry.OperationDefinition definition = ConnectorOperationRegistry.resolve(
      this
    );
    return definition.identity();
  }

  private static ConnectorExecutionRequest copyOf(
    ConnectorExecutionRequest source
  ) {
    ConnectorExecutionRequest copyValue = new ConnectorExecutionRequest();
    copyValue.connectorKey = source.connectorKey;
    copyValue.operationKey = source.operationKey;
    copyValue.direction = source.direction;
    copyValue.salesforceObject = source.salesforceObject;
    copyValue.externalEntity = source.externalEntity;
    copyValue.cursor = source.cursor;
    copyValue.sinceValue = source.sinceValue;
    copyValue.initialSync = source.initialSync;
    copyValue.scopeSize = source.scopeSize;
    copyValue.payload = source.payload;
    copyValue.correlationKey = source.correlationKey;
    copyValue.scheduleId = source.scheduleId;
    copyValue.leaseToken = source.leaseToken;
    copyValue.pageNumber = source.pageNumber;
    copyValue.retryAttempt = source.retryAttempt;
    return copyValue;
  }

  private void validateLimits() {
    if (scopeSize == null || scopeSize < 1 || scopeSize > 2000) {
      throw new ConnectorExecutionRequestException(
        'Scope size must be between 1 and 2000.'
      );
    }
    if (
      pageNumber == null ||
      pageNumber < 1 ||
      pageNumber > ConnectorHttpClient.ABSOLUTE_MAX_PAGES
    ) {
      throw new ConnectorExecutionRequestException(
        'Page number is outside the supported range.'
      );
    }
    if (retryAttempt == null || retryAttempt < 0 || retryAttempt > 5) {
      throw new ConnectorExecutionRequestException(
        'Retry attempt is outside the supported range.'
      );
    }
    if (payload != null && payload.length() > 1000000) {
      throw new ConnectorExecutionRequestException(
        'Payload exceeds the shared integration size limit.'
      );
    }
    assertBoundedValue(correlationKey, 255, 'Correlation key');
    assertBoundedValue(leaseToken, 255, 'Lease token');
    assertBoundedValue(cursor, 4000, 'Cursor');
  }

  private void validateRecordIds(
    ConnectorOperationRegistry.OperationDefinition definition
  ) {
    if (
      recordIds == null ||
      recordIds.isEmpty() ||
      String.isBlank(definition.salesforceObject)
    ) {
      return;
    }
    Schema.SObjectType expectedType = resolveSObjectType(
      definition.salesforceObject
    );
    if (expectedType == null) {
      throw new ConnectorExecutionRequestException(
        'The configured Salesforce object is unavailable.'
      );
    }
    for (Id recordId : recordIds) {
      if (recordId == null || recordId.getSObjectType() != expectedType) {
        throw new ConnectorExecutionRequestException(
          'A record ID does not belong to the configured Salesforce object.'
        );
      }
    }
  }

  public static Schema.SObjectType resolveSObjectType(String configuredObject) {
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    Schema.SObjectType exactType = globalDescribe.get(configuredObject);
    if (exactType != null) {
      return exactType;
    }
    if (hasNamespace(configuredObject)) {
      return null;
    }
    String configuredName = cleanObjectName(configuredObject);
    for (String candidate : globalDescribe.keySet()) {
      if (cleanObjectName(candidate) == configuredName) {
        return globalDescribe.get(candidate);
      }
    }
    return null;
  }

  private static String cleanObjectName(String objectName) {
    if (String.isBlank(objectName)) {
      return '';
    }
    String cleanName = objectName.toLowerCase();
    if (cleanName.endsWith('__c')) {
      cleanName = cleanName.substring(0, cleanName.length() - 3);
    }
    Integer namespaceSeparator = cleanName.lastIndexOf('__');
    if (namespaceSeparator >= 0) {
      cleanName = cleanName.substring(namespaceSeparator + 2);
    }
    return cleanName.replaceAll('[^a-z0-9]', '');
  }

  private static Boolean hasNamespace(String objectName) {
    if (String.isBlank(objectName)) {
      return false;
    }
    String withoutCustomSuffix = objectName.endsWith('__c')
      ? objectName.substring(0, objectName.length() - 3)
      : objectName;
    return withoutCustomSuffix.contains('__');
  }

  private static void assertBoundedValue(
    String value,
    Integer maximumLength,
    String label
  ) {
    if (value != null && value.length() > maximumLength) {
      throw new ConnectorExecutionRequestException(
        label + ' exceeds the supported length.'
      );
    }
  }

  public class ConnectorExecutionRequestException extends Exception {
  }
}