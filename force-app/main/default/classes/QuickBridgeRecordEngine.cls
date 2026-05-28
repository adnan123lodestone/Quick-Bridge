public with sharing class QuickBridgeRecordEngine {
  @TestVisible
  private static List<Invoice_Field_Mapping__mdt> testActiveMappings;
  @TestVisible
  private static List<String> testInvoicePipelineTargetObjects;
  @TestVisible
  private static String testCanonicalInvoicePipelineTargetObject;
  @TestVisible
  private static Boolean forcePipelineFailureForTest = false;
  private static Map<String, Schema.SObjectType> objectTypeByApiName = new Map<String, Schema.SObjectType>();
  private class PipelineException extends Exception {
  }

  private class PipelineResult {
    Id canonicalInvoiceId;
    String canonicalInvoiceObjectApiName;
  }

  private class PipelineTarget {
    String objectApiName;
    Map<String, String> sourceToTargetFields = new Map<String, String>();
    Map<String, Object> defaultValues = new Map<String, Object>();
    String methodName;
    Boolean canonical = false;
    Integer sequence = 0;
  }

  public static void processIncomingInvoice(Map<String, Object> incomingData) {
    try {
      if (Test.isRunningTest() && forcePipelineFailureForTest) {
        throw new PipelineException(
          'Forced invoice pipeline failure for logging coverage.'
        );
      }
      PipelineResult result = runInvoicePipeline(
        incomingData == null ? new Map<String, Object>() : incomingData
      );
      checkAndCreateClientMappedRecord(
        incomingData,
        result.canonicalInvoiceId,
        result.canonicalInvoiceObjectApiName
      );
    } catch (Exception e) {
      System.debug('QuickBridge Engine Error: ' + e.getMessage());
      Id orderId = getIdValue(incomingData, 'Order__c');
      Id accountId = getIdValue(incomingData, 'Related_Account__c');
      if (orderId != null) {
        ErrorLogUtility.logException(
          'Payment',
          'QuickBridgeRecordEngine.processIncomingInvoice',
          e,
          'Order',
          orderId
        );
      } else if (accountId != null) {
        ErrorLogUtility.logException(
          'Payment',
          'QuickBridgeRecordEngine.processIncomingInvoice',
          e,
          'Account',
          accountId
        );
      } else {
        ErrorLogUtility.logException(
          'Payment',
          'QuickBridgeRecordEngine.processIncomingInvoice',
          e,
          null,
          null
        );
      }
    }
  }

  private static PipelineResult runInvoicePipeline(
    Map<String, Object> incomingData
  ) {
    PipelineResult result = new PipelineResult();
    List<PipelineTarget> targets = defaultInvoiceTargets();
    PipelineTarget canonicalTarget = resolveCanonicalTarget(targets);
    for (PipelineTarget target : targets) {
      SObject record = buildRecord(target, incomingData);
      insert record;
      if (target == canonicalTarget) {
        result.canonicalInvoiceId = (Id) record.get('Id');
        result.canonicalInvoiceObjectApiName = target.objectApiName;
        System.debug(
          'QuickBridge Invoice Created: ' + result.canonicalInvoiceId
        );
      }
    }
    return result;
  }

  private static List<PipelineTarget> defaultInvoiceTargets() {
    List<String> targetObjects = new List<String>();
    if (Test.isRunningTest() && testInvoicePipelineTargetObjects != null) {
      targetObjects.addAll(testInvoicePipelineTargetObjects);
    } else {
      try {
        QBOInvoiceMappingResolver.ResolverResult res = QBOInvoiceMappingResolver.resolve();
        if (String.isNotBlank(res.invoiceSourceObject)) {
          targetObjects.add(res.invoiceSourceObject);
        }
      } catch (Exception ignored) {
      }
    }

    List<PipelineTarget> targets = new List<PipelineTarget>();
    for (String targetObject : targetObjects) {
      if (String.isBlank(targetObject)) {
        continue;
      }
      PipelineTarget invoiceTarget = new PipelineTarget();
      invoiceTarget.objectApiName = targetObject;
      invoiceTarget.methodName = 'QuickBridgeRecordEngine.processIncomingInvoice';
      invoiceTarget.sequence = targets.size() + 1;
      invoiceTarget.canonical =
        Test.isRunningTest() &&
        testInvoicePipelineTargetObjects != null &&
        String.isNotBlank(testCanonicalInvoicePipelineTargetObject)
          ? targetObject == testCanonicalInvoicePipelineTargetObject
          : targets.isEmpty();
      invoiceTarget.sourceToTargetFields.put('Amount__c', 'Amount__c');
      invoiceTarget.sourceToTargetFields.put('Order__c', 'Order__c');
      invoiceTarget.sourceToTargetFields.put(
        'Related_Account__c',
        'Related_Account__c'
      );
      invoiceTarget.sourceToTargetFields.put(
        'Reference_number__c',
        'Reference_number__c'
      );
      invoiceTarget.defaultValues.put('Status__c', 'Paid');
      invoiceTarget.defaultValues.put('Invoice_Date__c', Date.today());
      targets.add(invoiceTarget);
    }
    return targets;
  }

  private static PipelineTarget resolveCanonicalTarget(List<PipelineTarget> targets) {
    if (targets == null || targets.isEmpty()) {
      throw new PipelineException(
        'No active invoice pipeline target is configured. Configure at least one active invoice target and mark exactly one as canonical.'
      );
    }
    PipelineTarget canonicalTarget;
    Integer canonicalCount = 0;
    for (PipelineTarget target : targets) {
      if (target.canonical == true) {
        canonicalTarget = target;
        canonicalCount++;
      }
    }
    if (canonicalCount != 1) {
      throw new PipelineException(
        'Exactly one active canonical invoice pipeline target is required; found ' +
          canonicalCount +
          '.'
      );
    }
    return canonicalTarget;
  }

  private static SObject buildRecord(
    PipelineTarget target,
    Map<String, Object> incomingData
  ) {
    Schema.SObjectType objectType = objectTypeFor(target.objectApiName);
    if (objectType == null) {
      throw new AuraHandledException(
        'Unsupported invoice pipeline target: ' + target.objectApiName
      );
    }

    SObject record = objectType.newSObject();
    Map<String, Schema.SObjectField> fields = objectType.getDescribe()
      .fields.getMap();
    for (String fieldName : target.defaultValues.keySet()) {
      putIfFieldExists(
        record,
        fields,
        fieldName,
        target.defaultValues.get(fieldName)
      );
    }
    for (String sourceField : target.sourceToTargetFields.keySet()) {
      if (incomingData.containsKey(sourceField)) {
        String targetField = target.sourceToTargetFields.get(sourceField);
        putIfFieldExists(
          record,
          fields,
          targetField,
          incomingData.get(sourceField)
        );
      }
    }
    return record;
  }

  private static void checkAndCreateClientMappedRecord(
    Map<String, Object> incomingData,
    Id standardInvoiceId,
    String standardInvoiceObjectApiName
  ) {
    List<Invoice_Field_Mapping__mdt> activeMappings = Test.isRunningTest() &&
      testActiveMappings != null
      ? testActiveMappings
      : [
          SELECT
            Target_Object_API_Name__c,
            Source_Field_API_Name__c,
            Target_Field_API_Name__c
          FROM Invoice_Field_Mapping__mdt
          WHERE Is_Active__c = TRUE
        ];

    Map<String, List<Invoice_Field_Mapping__mdt>> mappingsByTarget = new Map<String, List<Invoice_Field_Mapping__mdt>>();
    for (Invoice_Field_Mapping__mdt mapping : activeMappings) {
      if (String.isBlank(mapping.Target_Object_API_Name__c)) {
        continue;
      }
      if (!mappingsByTarget.containsKey(mapping.Target_Object_API_Name__c)) {
        mappingsByTarget.put(
          mapping.Target_Object_API_Name__c,
          new List<Invoice_Field_Mapping__mdt>()
        );
      }
      mappingsByTarget.get(mapping.Target_Object_API_Name__c).add(mapping);
    }

    for (String targetObjName : mappingsByTarget.keySet()) {
      Schema.SObjectType customObjType = objectTypeFor(targetObjName);
      if (customObjType == null) {
        continue;
      }

      SObject clientRecord = customObjType.newSObject();
      Map<String, Schema.SObjectField> fields = customObjType.getDescribe()
        .fields.getMap();
      for (Invoice_Field_Mapping__mdt m : mappingsByTarget.get(targetObjName)) {
        if (incomingData.containsKey(m.Source_Field_API_Name__c)) {
          putIfFieldExists(
            clientRecord,
            fields,
            m.Target_Field_API_Name__c,
            incomingData.get(m.Source_Field_API_Name__c)
          );
        }
      }
      try {
        insert clientRecord;
        System.debug('Client Specific Record Created: ' + clientRecord.Id);
      } catch (Exception e) {
        ErrorLogUtility.logDmlFailure(
          'Payment',
          'QuickBridgeRecordEngine.checkAndCreateClientMappedRecord',
          'insert',
          targetObjName,
          null,
          e.getTypeName() + ': ' + e.getMessage(),
          standardInvoiceObjectApiName,
          standardInvoiceId
        );
      }
    }
  }

  private static Schema.SObjectType objectTypeFor(String objectApiName) {
    if (String.isBlank(objectApiName)) {
      return null;
    }
    if (objectTypeByApiName.containsKey(objectApiName)) {
      return objectTypeByApiName.get(objectApiName);
    }
    try {
      List<Schema.DescribeSObjectResult> describes = Schema.describeSObjects(
        new List<String>{ objectApiName }
      );
      if (!describes.isEmpty()) {
        Schema.SObjectType objectType = describes[0].getSObjectType();
        objectTypeByApiName.put(objectApiName, objectType);
        return objectType;
      }
    } catch (Exception e) {
      objectTypeByApiName.put(objectApiName, null);
    }
    return null;
  }

  private static void putIfFieldExists(
    SObject record,
    Map<String, Schema.SObjectField> fields,
    String fieldName,
    Object value
  ) {
    if (
      record == null ||
      fields == null ||
      String.isBlank(fieldName) ||
      value == null ||
      !fields.containsKey(fieldName)
    ) {
      return;
    }
    Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName)
      .getDescribe();
    record.put(fieldName, coerceValue(value, fieldDescribe.getType()));
  }

  private static Object coerceValue(
    Object value,
    Schema.DisplayType displayType
  ) {
    if (value == null) {
      return null;
    }
    if (
      displayType == Schema.DisplayType.Currency ||
      displayType == Schema.DisplayType.Double ||
      displayType == Schema.DisplayType.Percent
    ) {
      return value instanceof Decimal
        ? value
        : Decimal.valueOf(String.valueOf(value));
    }
    if (displayType == Schema.DisplayType.Integer) {
      return value instanceof Integer
        ? value
        : Integer.valueOf(String.valueOf(value));
    }
    if (displayType == Schema.DisplayType.Boolean) {
      return value instanceof Boolean
        ? value
        : String.valueOf(value).toLowerCase() == 'true';
    }
    if (displayType == Schema.DisplayType.Date) {
      return value instanceof Date
        ? value
        : Date.valueOf(String.valueOf(value));
    }
    if (displayType == Schema.DisplayType.DateTime) {
      return value instanceof Datetime
        ? value
        : Datetime.valueOf(String.valueOf(value));
    }
    return value;
  }

  private static Id getIdValue(Map<String, Object> incomingData, String key) {
    if (
      incomingData == null ||
      String.isBlank(key) ||
      !incomingData.containsKey(key) ||
      incomingData.get(key) == null
    ) {
      return null;
    }
    try {
      return (Id) incomingData.get(key);
    } catch (Exception e) {
      try {
        return (Id) String.valueOf(incomingData.get(key));
      } catch (Exception ignored) {
        return null;
      }
    }
  }
}
