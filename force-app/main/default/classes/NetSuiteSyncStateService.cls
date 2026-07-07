public with sharing class NetSuiteSyncStateService {
  public class FilterResult {
    public List<SObject> records = new List<SObject>();
    public Integer conflictCount = 0;
  }

  private static final Set<String> ALLOWED_OBJECTS = new Set<String>{
    'Account',
    'Product2',
    'Order',
    'Invoice__c',
    'Portal_Payment_Transaction__c',
    'Carrier_Shipment__c'
  };

  public static Datetime effectiveSince(Datetime requestedSince, NetSuiteConfigService.Config config) {
    return requestedSince == null && config != null ? config.lastSuccessfulSyncAt : requestedSince;
  }

  public static Datetime latestLastModified(List<Map<String, Object>> rows) {
    Datetime latest;
    if (rows == null) {
      return latest;
    }
    for (Map<String, Object> row : rows) {
      Datetime rowValue = parseNetSuiteDatetime(row == null ? null : row.get('lastmodifieddate'));
      if (rowValue != null && (latest == null || rowValue > latest)) {
        latest = rowValue;
      }
    }
    return latest;
  }

  public static void advanceWatermarkIfClean(List<Map<String, Object>> rows, Integer recordsFailed) {
    if (recordsFailed != null && recordsFailed > 0) {
      return;
    }
    Datetime latest = latestLastModified(rows);
    if (latest != null) {
      NetSuiteConfigService.markSuccessfulSync(latest);
    }
  }

  public static FilterResult filterInboundConflicts(
    String objectApiName,
    String externalFieldName,
    List<SObject> candidateRecords,
    Map<String, Map<String, Object>> sourceRowsByExternalId,
    Datetime lastSuccessfulSyncAt,
    String classMethodName
  ) {
    FilterResult result = new FilterResult();
    if (
      String.isBlank(objectApiName) ||
      String.isBlank(externalFieldName) ||
      candidateRecords == null ||
      candidateRecords.isEmpty() ||
      lastSuccessfulSyncAt == null
    ) {
      result.records.addAll(candidateRecords == null ? new List<SObject>() : candidateRecords);
      return result;
    }
    if (!ALLOWED_OBJECTS.contains(objectApiName)) {
      throw new NetSuiteSyncStateException('Unsupported NetSuite conflict object: ' + objectApiName);
    }

    Set<String> externalKeys = new Set<String>();
    for (SObject candidate : candidateRecords) {
      String externalKey = stringValue(candidate == null ? null : candidate.get(externalFieldName));
      if (String.isNotBlank(externalKey)) {
        externalKeys.add(externalKey);
      }
    }
    Map<String, SObject> existingByExternalId = existingRecords(objectApiName, externalFieldName, externalKeys);
    for (SObject candidate : candidateRecords) {
      String externalKey = stringValue(candidate == null ? null : candidate.get(externalFieldName));
      SObject existing = String.isBlank(externalKey) ? null : existingByExternalId.get(externalKey);
      Map<String, Object> sourceRow = sourceRowsByExternalId == null ? null : sourceRowsByExternalId.get(externalKey);
      if (isConflict(existing, sourceRow, lastSuccessfulSyncAt)) {
        result.conflictCount++;
        logConflict(objectApiName, externalKey, classMethodName);
      } else {
        result.records.add(candidate);
      }
    }
    return result;
  }

  private static Boolean isConflict(SObject existing, Map<String, Object> sourceRow, Datetime lastSuccessfulSyncAt) {
    if (existing == null || sourceRow == null || lastSuccessfulSyncAt == null) {
      return false;
    }
    Datetime salesforceModifiedAt = (Datetime) existing.get('LastModifiedDate');
    Datetime netSuiteModifiedAt = parseNetSuiteDatetime(sourceRow.get('lastmodifieddate'));
    return salesforceModifiedAt != null &&
      netSuiteModifiedAt != null &&
      salesforceModifiedAt > lastSuccessfulSyncAt &&
      netSuiteModifiedAt > lastSuccessfulSyncAt;
  }

  private static Map<String, SObject> existingRecords(String objectApiName, String externalFieldName, Set<String> externalKeys) {
    Map<String, SObject> rowsByExternalId = new Map<String, SObject>();
    if (externalKeys == null || externalKeys.isEmpty()) {
      return rowsByExternalId;
    }
    String query = 'SELECT Id, LastModifiedDate, ' + externalFieldName +
      ' FROM ' + objectApiName +
      ' WHERE ' + externalFieldName + ' IN :externalKeys';
    for (SObject row : Database.query(query)) {
      String externalKey = stringValue(row.get(externalFieldName));
      if (String.isNotBlank(externalKey) && !rowsByExternalId.containsKey(externalKey)) {
        rowsByExternalId.put(externalKey, row);
      }
    }
    return rowsByExternalId;
  }

  private static void logConflict(String objectApiName, String externalKey, String classMethodName) {
    ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
    context.gatewayName = 'NetSuite';
    context.classMethodName = classMethodName;
    context.errorCategory = 'Needs Review';
    context.sourceObjectApiName = objectApiName;
    context.externalReference = externalKey;
    context.errorMessage = 'NetSuite inbound sync detected changes in Salesforce and NetSuite after the last successful sync.';
    ErrorLogUtility.logError(context);
  }

  private static Datetime parseNetSuiteDatetime(Object value) {
    if (value == null) {
      return null;
    }
    String raw = String.valueOf(value);
    if (String.isBlank(raw)) {
      return null;
    }
    try {
      return (Datetime) JSON.deserialize('"' + raw + '"', Datetime.class);
    } catch (Exception ignored) {
      try {
        return Datetime.valueOf(raw);
      } catch (Exception ignoredAgain) {
        return null;
      }
    }
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  public class NetSuiteSyncStateException extends Exception {}
}
