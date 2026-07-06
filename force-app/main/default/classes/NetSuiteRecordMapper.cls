public with sharing class NetSuiteRecordMapper {
  public static Map<String, Object> toNetSuitePayload(SObject sourceRecord, String salesforceObject, String externalObject) {
    if (sourceRecord == null) {
      throw new NetSuiteRecordMapperException('Salesforce source record is required.');
    }
    List<NetSuiteMappingService.MappingRule> rules = NetSuiteMappingService.activeRules(
      salesforceObject,
      externalObject,
      NetSuiteMappingService.DIRECTION_OUTBOUND
    );
    if (rules.isEmpty()) {
      rules = fallbackRules(salesforceObject, externalObject, NetSuiteMappingService.DIRECTION_OUTBOUND);
    }
    Map<String, Object> payload = new Map<String, Object>();
    for (NetSuiteMappingService.MappingRule rule : rules) {
      Object value = safeGet(sourceRecord, rule.salesforceField);
      if (value != null) {
        payload.put(rule.externalField, value);
      }
    }
    return payload;
  }

  public static SObject toSalesforceRecord(String salesforceObject, String externalObject, Map<String, Object> sourceRow) {
    if (String.isBlank(salesforceObject)) {
      throw new NetSuiteRecordMapperException('Salesforce object is required.');
    }
    Schema.SObjectType targetType = resolveSObjectType(salesforceObject);
    if (targetType == null) {
      throw new NetSuiteRecordMapperException('Unsupported Salesforce object for NetSuite mapping: ' + salesforceObject);
    }
    SObject targetRecord = targetType.newSObject();
    Map<String, Schema.SObjectField> fields = targetType.getDescribe().fields.getMap();
    Object internalId = sourceRow == null ? null : sourceRow.get('id');
    String externalIdFieldName = resolveFieldName(fields, 'External_Id__c');
    if (internalId != null && putKnownExternalId(targetRecord, salesforceObject, internalId)) {
    } else if (internalId != null && externalIdFieldName != null) {
      targetRecord.put(fields.get(externalIdFieldName), 'netsuite:' + String.valueOf(internalId));
    }

    List<NetSuiteMappingService.MappingRule> rules = NetSuiteMappingService.activeRules(
      salesforceObject,
      externalObject,
      NetSuiteMappingService.DIRECTION_INBOUND
    );
    if (rules.isEmpty()) {
      rules = fallbackRules(salesforceObject, externalObject, NetSuiteMappingService.DIRECTION_INBOUND);
    }
    for (NetSuiteMappingService.MappingRule rule : rules) {
      String fieldName = resolveFieldName(fields, rule.salesforceField);
      if (sourceRow == null || !sourceRow.containsKey(rule.externalField)) {
        continue;
      }
      if (fieldName == null) {
        putKnownField(targetRecord, salesforceObject, rule.salesforceField, sourceRow.get(rule.externalField));
        continue;
      }
      Object coercedValue = coerceValue(sourceRow.get(rule.externalField), fields.get(fieldName).getDescribe());
      if (!putKnownField(targetRecord, salesforceObject, rule.salesforceField, coercedValue)) {
        targetRecord.put(fields.get(fieldName), coercedValue);
      }
    }
    return targetRecord;
  }

  private static Object safeGet(SObject record, String fieldName) {
    try {
      return String.isBlank(fieldName) ? null : record.get(fieldName);
    } catch (Exception ignored) {
      return null;
    }
  }

  private static Schema.SObjectType resolveSObjectType(String salesforceObject) {
    Schema.SObjectType knownType = knownCustomObjectType(salesforceObject);
    if (knownType != null) {
      return knownType;
    }
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    if (globalDescribe.containsKey(salesforceObject)) {
      return globalDescribe.get(salesforceObject);
    }
    if (!String.isBlank(salesforceObject) && salesforceObject.endsWith('__c')) {
      String namespacedSuffix = '__' + salesforceObject;
      for (String objectName : globalDescribe.keySet()) {
        if (objectName.endsWith(namespacedSuffix)) {
          return globalDescribe.get(objectName);
        }
      }
    }
    return null;
  }

  private static Schema.SObjectType knownCustomObjectType(String salesforceObject) {
    if (salesforceObject == 'Invoice__c') {
      return Invoice__c.SObjectType;
    }
    if (salesforceObject == 'Invoice_Line__c') {
      return Invoice_Line__c.SObjectType;
    }
    if (salesforceObject == 'Portal_Payment_Transaction__c') {
      return Portal_Payment_Transaction__c.SObjectType;
    }
    if (salesforceObject == 'Carrier_Shipment__c') {
      return Carrier_Shipment__c.SObjectType;
    }
    return null;
  }

  private static Boolean putKnownExternalId(SObject targetRecord, String salesforceObject, Object internalId) {
    if (internalId == null) {
      return false;
    }
    String externalId = 'netsuite:' + String.valueOf(internalId);
    if (salesforceObject == 'Account') {
      ((Account) targetRecord).External_Id__c = externalId;
      return true;
    }
    if (salesforceObject == 'Contact') {
      ((Contact) targetRecord).External_Id__c = externalId;
      return true;
    }
    if (salesforceObject == 'Product2') {
      ((Product2) targetRecord).External_Id__c = externalId;
      return true;
    }
    if (salesforceObject == 'Order') {
      ((Order) targetRecord).External_Id__c = externalId;
      return true;
    }
    if (salesforceObject == 'Invoice__c') {
      ((Invoice__c) targetRecord).External_Id__c = externalId;
      return true;
    }
    if (salesforceObject == 'Invoice_Line__c') {
      ((Invoice_Line__c) targetRecord).External_Id__c = externalId;
      return true;
    }
    return false;
  }

  private static Boolean putKnownField(SObject targetRecord, String salesforceObject, String fieldName, Object value) {
    if (salesforceObject == 'Invoice__c') {
      Invoice__c invoiceRecord = (Invoice__c) targetRecord;
      if (fieldName == 'Reference_number__c') {
        invoiceRecord.Reference_number__c = (String) value;
        return true;
      }
      if (fieldName == 'Amount__c') {
        invoiceRecord.Amount__c = (Decimal) value;
        return true;
      }
      if (fieldName == 'Status__c') {
        invoiceRecord.Status__c = (String) value;
        return true;
      }
    }
    return false;
  }

  private static String resolveFieldName(Map<String, Schema.SObjectField> fields, String fieldName) {
    if (fields == null || String.isBlank(fieldName)) {
      return null;
    }
    if (fields.containsKey(fieldName)) {
      return fieldName;
    }
    if (fieldName.endsWith('__c')) {
      String namespacedSuffix = '__' + fieldName;
      for (String describedFieldName : fields.keySet()) {
        if (describedFieldName.endsWith(namespacedSuffix)) {
          return describedFieldName;
        }
      }
    }
    return null;
  }

  private static Object coerceValue(Object value, Schema.DescribeFieldResult fieldDescribe) {
    if (value == null || fieldDescribe == null) {
      return value;
    }
    Schema.DisplayType fieldType = fieldDescribe.getType();
    if (fieldType == Schema.DisplayType.Currency || fieldType == Schema.DisplayType.Double || fieldType == Schema.DisplayType.Percent) {
      return Decimal.valueOf(String.valueOf(value));
    }
    if (fieldType == Schema.DisplayType.Integer) {
      return Integer.valueOf(String.valueOf(value));
    }
    if (fieldType == Schema.DisplayType.Boolean) {
      String text = String.valueOf(value);
      return text == 'T' || text.equalsIgnoreCase('true');
    }
    if (fieldType == Schema.DisplayType.Date) {
      return Date.valueOf(String.valueOf(value).left(10));
    }
    if (fieldType == Schema.DisplayType.DateTime) {
      return (Datetime) JSON.deserialize('"' + String.valueOf(value) + '"', Datetime.class);
    }
    return String.valueOf(value);
  }

  private static List<NetSuiteMappingService.MappingRule> fallbackRules(String salesforceObject, String externalObject, String direction) {
    List<NetSuiteMappingService.MappingRule> rules = new List<NetSuiteMappingService.MappingRule>();
    if (salesforceObject == 'Account' && externalObject == 'Customer') {
      rules.add(rule(salesforceObject, externalObject, 'Name', 'companyname', direction));
      rules.add(rule(salesforceObject, externalObject, 'Phone', 'phone', direction));
      rules.add(rule(salesforceObject, externalObject, 'BillingCity', 'billcity', direction));
    } else if (salesforceObject == 'Product2' && externalObject == 'Item') {
      rules.add(rule(salesforceObject, externalObject, 'ProductCode', 'itemid', direction));
      rules.add(rule(salesforceObject, externalObject, 'Name', 'displayname', direction));
      rules.add(rule(salesforceObject, externalObject, 'Description', 'salesdescription', direction));
      rules.add(rule(salesforceObject, externalObject, 'IsActive', 'isinactive', direction));
    } else if (salesforceObject == 'Order' && externalObject == 'SalesOrder') {
      rules.add(rule(salesforceObject, externalObject, 'OrderReferenceNumber', 'tranid', direction));
      rules.add(rule(salesforceObject, externalObject, 'EffectiveDate', 'trandate', direction));
      rules.add(rule(salesforceObject, externalObject, 'Status', 'status', direction));
    } else if (salesforceObject == 'Invoice__c' && externalObject == 'Invoice') {
      rules.add(rule(salesforceObject, externalObject, 'Reference_number__c', 'tranid', direction));
      rules.add(rule(salesforceObject, externalObject, 'Amount__c', 'total', direction));
      rules.add(rule(salesforceObject, externalObject, 'Status__c', 'status', direction));
    }
    return rules;
  }

  private static NetSuiteMappingService.MappingRule rule(String sfObject, String extObject, String sfField, String extField, String direction) {
    return new NetSuiteMappingService.MappingRule(sfObject, extObject, sfField, extField, direction);
  }

  public class NetSuiteRecordMapperException extends Exception {}
}
