public with sharing class NetSuiteTransactionUtil {
  public static final String RECORD_PATH = '/services/rest/record/v1/';

  public static String internalIdFromExternalId(String externalId) {
    if (String.isBlank(externalId) || !externalId.startsWith('netsuite:')) {
      return null;
    }
    return externalId.substringAfter('netsuite:');
  }

  public static String writeRecord(String recordType, String externalId, Map<String, Object> payload) {
    if (String.isBlank(recordType)) {
      throw new NetSuiteTransactionException('NetSuite record type is required.');
    }
    NetSuiteApiClient client = NetSuiteApiClient.configured();
    String internalId = internalIdFromExternalId(externalId);
    NetSuiteApiResponse response;
    if (String.isBlank(internalId)) {
      response = client.post(RECORD_PATH + recordType, payload == null ? new Map<String, Object>() : payload);
    } else {
      response = client.patch(RECORD_PATH + recordType + '/' + EncodingUtil.urlEncode(internalId, 'UTF-8'), payload == null ? new Map<String, Object>() : payload);
    }
    return extractId(response);
  }

  public static String extractId(NetSuiteApiResponse response) {
    if (response == null || response.body == null) {
      return null;
    }
    if (response.body.containsKey('id')) {
      return String.valueOf(response.body.get('id'));
    }
    if (response.body.containsKey('internalId')) {
      return String.valueOf(response.body.get('internalId'));
    }
    return null;
  }

  public static void putReference(Map<String, Object> payload, String key, String idValue) {
    if (payload == null || String.isBlank(key) || String.isBlank(idValue)) {
      return;
    }
    payload.put(key, new Map<String, Object>{ 'id' => idValue });
  }

  public static void updateExternalId(SObject record, String fieldName, String internalId) {
    if (record == null || record.Id == null || String.isBlank(fieldName) || String.isBlank(internalId)) {
      return;
    }
    SObject updateRecord = record.getSObjectType().newSObject(record.Id);
    updateRecord.put(fieldName, 'netsuite:' + internalId);
    update updateRecord;
  }

  public class NetSuiteTransactionException extends Exception {}
}