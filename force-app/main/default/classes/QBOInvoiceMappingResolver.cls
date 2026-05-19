public with sharing class QBOInvoiceMappingResolver {
  public class ResolverResult {
    @AuraEnabled
    public String invoiceSourceObject;
    @AuraEnabled
    public String qboIdField;
    @AuraEnabled
    public String displayNameField;
    @AuraEnabled
    public Map<String, String> headerMappings;
    @AuraEnabled
    public String lineChildRelationship;
    @AuraEnabled
    public String lineSourceObject;
    @AuraEnabled
    public Map<String, String> lineMappings;
  }

  public class ResolverException extends Exception {
  }

  private static final String INTEGRATION = 'qbonline';
  private static final String EXTERNAL_ENTITY = 'Invoice';

  public static ResolverResult resolve() {
    List<Field_Mapping__mdt> allRows = [
      SELECT
        SF_Object__c,
        SF_Field__c,
        External_Field__c,
        Sync_Direction__c,
        Is_Active__c
      FROM Field_Mapping__mdt
      WHERE Integration__c = :INTEGRATION AND Is_Active__c = TRUE
    ];

    // Group rows by SF_Object__c
    Map<String, List<Field_Mapping__mdt>> byObject = new Map<String, List<Field_Mapping__mdt>>();
    for (Field_Mapping__mdt row : allRows) {
      if (String.isBlank(row.SF_Object__c))
        continue;
      if (!byObject.containsKey(row.SF_Object__c)) {
        byObject.put(row.SF_Object__c, new List<Field_Mapping__mdt>());
      }
      byObject.get(row.SF_Object__c).add(row);
    }

    // Keep only objects that resolve to QBO Invoice
    List<String> invoiceObjects = new List<String>();
    for (String sfObject : byObject.keySet()) {
      String resolved = IntegrationEntityRegistry.resolveExternalEntity(
        INTEGRATION,
        sfObject,
        null,
        null
      );
      if (EXTERNAL_ENTITY.equalsIgnoreCase(resolved)) {
        invoiceObjects.add(sfObject);
      }
    }

    if (invoiceObjects.isEmpty()) {
      throw new ResolverException(
        'No active Field_Mapping__mdt records map a Salesforce object to QBO Invoice. ' +
        'Configure an active qbonline mapping for an object that resolves to Invoice.'
      );
    }
    if (invoiceObjects.size() > 1) {
      throw new ResolverException(
        'Multiple Salesforce objects are mapped to QBO Invoice: ' +
          String.join(invoiceObjects, ', ') +
          '. ' +
          'Only one active invoice source object is supported.'
      );
    }

    String sourceObject = invoiceObjects[0];
    List<Field_Mapping__mdt> rows = byObject.get(sourceObject);

    ResolverResult result = new ResolverResult();
    result.invoiceSourceObject = sourceObject;
    result.headerMappings = new Map<String, String>();
    result.lineMappings = new Map<String, String>();

    // Resolve QBO id field from mappings
    result.qboIdField = resolveQboIdField(rows, sourceObject);

    // Resolve display name field (prefer Name, fall back to first text SF field found)
    result.displayNameField = resolveDisplayNameField(sourceObject);

    // Header mappings: rows on the source object itself (SF→QBO or Two-Way)
    for (Field_Mapping__mdt row : rows) {
      if (
        String.isBlank(row.SF_Field__c) || String.isBlank(row.External_Field__c)
      )
        continue;
      String dir = row.Sync_Direction__c;
      if (dir == 'SF to QBO' || dir == 'Two-Way') {
        result.headerMappings.put(row.SF_Field__c, row.External_Field__c);
      }
    }

    // Resolve line child object and relationship
    String lineObject = resolveLineObject(sourceObject, allRows);
    if (String.isNotBlank(lineObject)) {
      result.lineSourceObject = lineObject;
      result.lineChildRelationship = resolveChildRelationshipName(
        sourceObject,
        lineObject
      );
      List<Field_Mapping__mdt> lineRows = byObject.get(lineObject);
      if (lineRows != null) {
        for (Field_Mapping__mdt row : lineRows) {
          if (
            String.isBlank(row.SF_Field__c) ||
            String.isBlank(row.External_Field__c)
          )
            continue;
          String dir = row.Sync_Direction__c;
          if (dir == 'SF to QBO' || dir == 'Two-Way') {
            result.lineMappings.put(row.SF_Field__c, row.External_Field__c);
          }
        }
      }
    }

    return result;
  }

  // Resolves which SF field stores the QBO Invoice Id returned from QBO.
  // Priority order:
  //   1. Mapping row External_Field__c='Id', direction QBO to SF or Two-Way (explicit inbound id mapping)
  //   2. Mapping row External_Field__c='ExternalId', direction QBO to SF or Two-Way
  //   3. Mapping row External_Field__c='Id', any direction (covers SF to QBO rows that also carry the id back)
  //   4. Well-known field names on the object: QuickbookID__c, then External_Id__c (with/without namespace)
  private static String resolveQboIdField(
    List<Field_Mapping__mdt> rows,
    String sourceObject
  ) {
    String fallbackExternalId = null;
    String anyDirectionIdField = null;

    for (Field_Mapping__mdt row : rows) {
      if (
        String.isBlank(row.SF_Field__c) || String.isBlank(row.External_Field__c)
      )
        continue;
      String dir = row.Sync_Direction__c;
      Boolean inbound = (dir == 'QBO to SF' || dir == 'Two-Way');

      if (row.External_Field__c == 'Id') {
        if (inbound)
          return row.SF_Field__c; // priority 1
        if (anyDirectionIdField == null)
          anyDirectionIdField = row.SF_Field__c; // priority 3 candidate
      }
      if (
        row.External_Field__c == 'ExternalId' &&
        inbound &&
        fallbackExternalId == null
      ) {
        fallbackExternalId = row.SF_Field__c; // priority 2 candidate
      }
    }

    if (String.isNotBlank(fallbackExternalId))
      return fallbackExternalId;
    if (String.isNotBlank(anyDirectionIdField))
      return anyDirectionIdField;

    // Priority 4: well-known field names on the object
    Schema.SObjectType sot = getSObjectType(sourceObject);
    if (sot != null) {
      Map<String, Schema.SObjectField> fields = sot.getDescribe()
        .fields.getMap();
      String nsPrefix = getNamespacePrefix();
      // QuickbookID__c is the field QBO sync batches write the returned Invoice Id into
      if (fields.containsKey('quickbookid__c'))
        return 'QuickbookID__c';
      if (
        String.isNotBlank(nsPrefix) &&
        fields.containsKey((nsPrefix + 'QuickbookID__c').toLowerCase())
      ) {
        return nsPrefix + 'QuickbookID__c';
      }
      if (fields.containsKey('external_id__c'))
        return 'External_Id__c';
      if (
        String.isNotBlank(nsPrefix) &&
        fields.containsKey((nsPrefix + 'External_Id__c').toLowerCase())
      ) {
        return nsPrefix + 'External_Id__c';
      }
    }
    return null;
  }

  // Returns 'Name' if the object has a Name field, otherwise null.
  private static String resolveDisplayNameField(String sourceObject) {
    Schema.SObjectType sot = getSObjectType(sourceObject);
    if (sot == null)
      return null;
    Map<String, Schema.SObjectField> fields = sot.getDescribe().fields.getMap();
    if (fields.containsKey('name'))
      return 'Name';
    return null;
  }

  // Finds a line/child object that also has active qbonline mappings and is a child of sourceObject.
  private static String resolveLineObject(
    String sourceObject,
    List<Field_Mapping__mdt> allRows
  ) {
    Set<String> candidateObjects = new Set<String>();
    for (Field_Mapping__mdt row : allRows) {
      if (String.isBlank(row.SF_Object__c) || row.SF_Object__c == sourceObject)
        continue;
      candidateObjects.add(row.SF_Object__c);
    }

    Schema.SObjectType sot = getSObjectType(sourceObject);
    if (sot == null)
      return null;

    List<Schema.ChildRelationship> children = sot.getDescribe()
      .getChildRelationships();
    for (Schema.ChildRelationship cr : children) {
      String childObjectName = cr.getChildSObject().getDescribe().getName();
      for (String candidate : candidateObjects) {
        if (
          normalizeObjectName(candidate) == normalizeObjectName(childObjectName)
        ) {
          return candidate;
        }
      }
    }
    return null;
  }

  // Finds the child relationship name on sourceObject that points to lineObject.
  private static String resolveChildRelationshipName(
    String sourceObject,
    String lineObject
  ) {
    Schema.SObjectType sot = getSObjectType(sourceObject);
    if (sot == null)
      return null;
    List<Schema.ChildRelationship> children = sot.getDescribe()
      .getChildRelationships();
    for (Schema.ChildRelationship cr : children) {
      String childObjectName = cr.getChildSObject().getDescribe().getName();
      if (
        normalizeObjectName(childObjectName) == normalizeObjectName(lineObject)
      ) {
        return cr.getRelationshipName();
      }
    }
    return null;
  }

  // Strips namespace prefix from object names for comparison.
  private static String normalizeObjectName(String name) {
    if (String.isBlank(name))
      return '';
    if (name.endsWith('__c') && name.indexOf('__') != name.lastIndexOf('__')) {
      return name.substringAfter('__').toLowerCase();
    }
    return name.toLowerCase();
  }

  private static String getNamespacePrefix() {
    String className = QBOInvoiceMappingResolver.class.getName();
    if (className.contains('.')) {
      return className.substringBefore('.') + '__';
    }
    return '';
  }

  @TestVisible
  private static Schema.SObjectType getSObjectType(String objApiName) {
    Schema.SObjectType sot = Schema.getGlobalDescribe().get(objApiName);
    if (
      sot == null &&
      String.isNotBlank(objApiName) &&
      objApiName.endsWith('__c')
    ) {
      String nsPrefix = getNamespacePrefix();
      if (String.isNotBlank(nsPrefix) && !objApiName.startsWith(nsPrefix)) {
        sot = Schema.getGlobalDescribe().get(nsPrefix + objApiName);
      }
    }
    return sot;
  }
}
