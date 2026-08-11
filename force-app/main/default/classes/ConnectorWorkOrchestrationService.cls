/**
 * Shared orchestration for connector work that is already executed by
 * IntegrationWorkProcessor. Provider workers remain responsible for protocol,
 * mapping, signing, and domain behavior.
 */
public inherited sharing class ConnectorWorkOrchestrationService {
  private static final String SCHEDULE_CONTEXT_KEY = '_connectorSchedule';
  private static final String SCHEDULE_ID_KEY = 'scheduleId';
  private static final String LEASE_TOKEN_KEY = 'leaseToken';

  public class ScheduleContext {
    public Id scheduleId { get; private set; }
    public String leaseToken { get; private set; }

    private ScheduleContext(Id scheduleId, String leaseToken) {
      this.scheduleId = scheduleId;
      this.leaseToken = leaseToken;
    }
  }

  public static IntegrationWorkRequest scheduledRequest(
    Scheduled_Integration_Job__c job,
    String leaseToken,
    String integration,
    String operation,
    String sourceObject,
    String sourceRecordId,
    String lockKey,
    Map<String, Object> providerContext
  ) {
    if (String.isBlank(integration) || String.isBlank(operation)) {
      throw new ConnectorWorkOrchestrationException(
        'Scheduled connector work requires an integration and operation.'
      );
    }

    Map<String, Object> payload = providerContext == null
      ? new Map<String, Object>()
      : new Map<String, Object>(providerContext);
    payload.put('scheduled', true);
    payload.put('operation', operation);
    if (job != null && job.Id != null && String.isNotBlank(leaseToken)) {
      payload.put(
        SCHEDULE_CONTEXT_KEY,
        new Map<String, Object>{
          SCHEDULE_ID_KEY => String.valueOf(job.Id),
          LEASE_TOKEN_KEY => leaseToken
        }
      );
    }

    IntegrationWorkRequest request = new IntegrationWorkRequest();
    request.integration = integration;
    request.operation = operation;
    request.sourceObject = String.isBlank(sourceObject)
      ? operation
      : sourceObject;
    String resolvedSourceRecordId = String.isBlank(sourceRecordId)
      ? integration + ':' + operation
      : sourceRecordId;
    if (job != null && job.Id != null && String.isNotBlank(leaseToken)) {
      String runToken = EncodingUtil.convertToHex(
          Crypto.generateDigest('SHA-256', Blob.valueOf(leaseToken))
        )
        .left(16);
      resolvedSourceRecordId += ':' + String.valueOf(job.Id) + ':' + runToken;
    }
    request.sourceRecordId = resolvedSourceRecordId;
    request.lockKey = String.isBlank(lockKey)
      ? integration + ':' + operation
      : lockKey;
    request.payloadJson = JSON.serialize(payload);
    return request;
  }

  public static ConnectorScheduleDispatchResult dispatchScheduled(
    Scheduled_Integration_Job__c job,
    String leaseToken,
    IntegrationWorkRequest request
  ) {
    if (job == null || job.Id == null || String.isBlank(leaseToken)) {
      return ConnectorScheduleDispatchResult.failed(
        'Scheduled connector work requires a persisted schedule and lease token.'
      );
    }
    try {
      Id workItemId = IntegrationWorkService.enqueue(request);
      if (workItemId == null) {
        return ConnectorScheduleDispatchResult.failed(
          'Scheduled connector work did not create a work item.'
        );
      }
      Id dispatcherJobId = System.enqueueJob(new IntegrationWorkDispatcher());
      return ConnectorScheduleDispatchResult.deferred(dispatcherJobId);
    } catch (Exception exceptionValue) {
      return ConnectorScheduleDispatchResult.failed(
        exceptionValue.getMessage()
      );
    }
  }

  public static ScheduleContext scheduleContext(Integration_Work_Item__c item) {
    if (item == null || String.isBlank(item.Payload__c)) {
      return null;
    }
    try {
      Object parsedPayload = JSON.deserializeUntyped(item.Payload__c);
      if (!(parsedPayload instanceof Map<String, Object>)) {
        return null;
      }
      Object contextValue = ((Map<String, Object>) parsedPayload)
        .get(SCHEDULE_CONTEXT_KEY);
      if (!(contextValue instanceof Map<String, Object>)) {
        return null;
      }
      Map<String, Object> rawContext = (Map<String, Object>) contextValue;
      String scheduleIdValue = stringValue(rawContext.get(SCHEDULE_ID_KEY));
      String leaseToken = stringValue(rawContext.get(LEASE_TOKEN_KEY));
      if (
        String.isBlank(scheduleIdValue) ||
        String.isBlank(leaseToken) ||
        leaseToken.length() > 255
      ) {
        return null;
      }
      Id scheduleId = Id.valueOf(scheduleIdValue);
      if (
        scheduleId.getSObjectType() != Scheduled_Integration_Job__c.SObjectType
      ) {
        return null;
      }
      return new ScheduleContext(scheduleId, leaseToken);
    } catch (Exception ignored) {
      return null;
    }
  }

  public static void completeSuccess(Integration_Work_Item__c item) {
    ScheduleContext contextValue = scheduleContext(item);
    if (contextValue == null) {
      return;
    }
    try {
      ConnectorScheduleService.completeSuccess(
        contextValue.scheduleId,
        contextValue.leaseToken
      );
    } catch (Exception exceptionValue) {
      System.debug(
        LoggingLevel.ERROR,
        'Unable to complete the connector work schedule: ' +
        exceptionValue.getMessage()
      );
    }
  }

  public static void completeFailure(
    Integration_Work_Item__c item,
    String errorMessage
  ) {
    ScheduleContext contextValue = scheduleContext(item);
    if (contextValue == null) {
      return;
    }
    try {
      ConnectorScheduleService.completeFailure(
        contextValue.scheduleId,
        contextValue.leaseToken,
        errorMessage
      );
    } catch (Exception exceptionValue) {
      System.debug(
        LoggingLevel.ERROR,
        'Unable to fail the connector work schedule: ' +
        exceptionValue.getMessage()
      );
    }
  }

  public static void renew(Integration_Work_Item__c item) {
    ScheduleContext contextValue = scheduleContext(item);
    if (contextValue == null) {
      return;
    }
    try {
      ConnectorScheduleService.markRunning(
        contextValue.scheduleId,
        contextValue.leaseToken,
        null,
        3600
      );
    } catch (Exception exceptionValue) {
      System.debug(
        LoggingLevel.ERROR,
        'Unable to renew the connector work schedule: ' +
        exceptionValue.getMessage()
      );
    }
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  public class ConnectorWorkOrchestrationException extends Exception {
  }
}
