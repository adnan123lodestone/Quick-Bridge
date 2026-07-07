public with sharing class NetSuiteMappingService {
  public static final String DIRECTION_INBOUND = 'NetSuite to SF';
  public static final String DIRECTION_OUTBOUND = 'SF to NetSuite';
  private static final String DIRECTION_TWO_WAY = 'Two-Way';

  @TestVisible
  private static List<Field_Mapping__mdt> testMappings;

  public class MappingRule {
    public String salesforceObject;
    public String externalObject;
    public String salesforceField;
    public String externalField;
    public String syncDirection;

    private MappingRule(Field_Mapping__mdt row) {
      salesforceObject = row.SF_Object__c;
      externalObject = row.Target_Object_API_Name__c;
      salesforceField = row.SF_Field__c;
      externalField = row.External_Field__c;
      syncDirection = row.Sync_Direction__c;
    }

    public MappingRule(String sfObject, String extObject, String sfField, String extField, String direction) {
      salesforceObject = sfObject;
      externalObject = extObject;
      salesforceField = sfField;
      externalField = extField;
      syncDirection = direction;
    }
  }

  public static List<MappingRule> activeRules(String salesforceObject, String externalObject, String direction) {
    List<MappingRule> rules = new List<MappingRule>();
    if (String.isBlank(salesforceObject) || String.isBlank(externalObject)) {
      return rules;
    }
    for (Field_Mapping__mdt row : activeRows(salesforceObject, externalObject)) {
      if (String.isNotBlank(row.Target_Object_API_Name__c) && row.Target_Object_API_Name__c != externalObject) {
        continue;
      }
      if (String.isBlank(row.SF_Field__c) || String.isBlank(row.External_Field__c)) {
        continue;
      }
      if (touchesDirection(row.Sync_Direction__c, direction)) {
        rules.add(new MappingRule(row));
      }
    }
    return rules;
  }

  public static Set<String> salesforceFields(String salesforceObject, String externalObject, String direction) {
    Set<String> fields = new Set<String>();
    for (MappingRule rule : activeRules(salesforceObject, externalObject, direction)) {
      fields.add(rule.salesforceField);
    }
    return fields;
  }

  private static List<Field_Mapping__mdt> activeRows(String salesforceObject, String externalObject) {
    if (Test.isRunningTest() && testMappings != null) {
      List<Field_Mapping__mdt> rows = new List<Field_Mapping__mdt>();
      for (Field_Mapping__mdt row : testMappings) {
        if (
          row != null &&
          row.Integration__c == NetSuiteConfigService.CONNECTOR_KEY &&
          row.SF_Object__c == salesforceObject &&
          row.Is_Active__c == true &&
          (String.isBlank(row.Target_Object_API_Name__c) || row.Target_Object_API_Name__c == externalObject)
        ) {
          rows.add(row);
        }
      }
      return rows;
    }

    return [
      SELECT SF_Object__c, Target_Object_API_Name__c, SF_Field__c, External_Field__c, Sync_Direction__c, Is_Active__c
      FROM Field_Mapping__mdt
      WHERE Integration__c = :NetSuiteConfigService.CONNECTOR_KEY
      AND SF_Object__c = :salesforceObject
      AND Is_Active__c = TRUE
      ORDER BY DeveloperName ASC
    ];
  }

  private static Boolean touchesDirection(String configuredDirection, String requestedDirection) {
    String direction = String.isBlank(configuredDirection) ? DIRECTION_TWO_WAY : configuredDirection;
    if (direction == DIRECTION_TWO_WAY) {
      return true;
    }
    if (requestedDirection == DIRECTION_INBOUND) {
      return direction == DIRECTION_INBOUND;
    }
    if (requestedDirection == DIRECTION_OUTBOUND) {
      return direction == DIRECTION_OUTBOUND;
    }
    return direction == requestedDirection;
  }

  @TestVisible
  private static void setTestMappings(List<Field_Mapping__mdt> rows) {
    testMappings = rows;
  }
}