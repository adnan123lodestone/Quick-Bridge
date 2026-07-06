public with sharing class NetSuiteConnectionValidator {
  public class ValidationResult {
    @AuraEnabled public Boolean success { get; set; }
    @AuraEnabled public String message { get; set; }
    @AuraEnabled public String status { get; set; }
  }

  @AuraEnabled
  public static ValidationResult validateConnection(String sessionToken) {
    QuickBridgeAdminGuard.requireManage();
    QuickBridgeAdminSessionService.requireValidSession(sessionToken);
    return validateConnection();
  }

  public static ValidationResult validateConnection() {
    ValidationResult result = new ValidationResult();
    try {
      NetSuiteConfigService.requireConfigured();
      List<Map<String, Object>> rows = NetSuiteApiClient.configured()
        .suiteql('SELECT id FROM customer WHERE rownum <= 1', null);
      updateHealth('Healthy');
      QuickBridgeAdminGuard.audit(
        'CONNECTION_VALIDATE',
        NetSuiteConfigService.CONNECTOR_KEY,
        'Success',
        'Validated NetSuite REST and SuiteQL access. Rows returned: ' + rows.size(),
        null
      );
      result.success = true;
      result.status = 'Healthy';
      result.message = 'NetSuite connection validated successfully.';
      return result;
    } catch (Exception e) {
      updateHealth('Error');
      QuickBridgeAdminGuard.audit(
        'CONNECTION_VALIDATE',
        NetSuiteConfigService.CONNECTOR_KEY,
        'Failure',
        NetSuiteErrorMapper.sanitize(e.getMessage()),
        null
      );
      result.success = false;
      result.status = 'Error';
      result.message = NetSuiteErrorMapper.sanitize(e.getMessage());
      return result;
    }
  }

  private static void updateHealth(String healthStatus) {
    List<Connector_Instance__c> instances = [
      SELECT Id
      FROM Connector_Instance__c
      WHERE Connector_Key__c = :NetSuiteConfigService.CONNECTOR_KEY
      LIMIT 1
    ];
    if (instances.isEmpty()) {
      return;
    }
    update new Connector_Instance__c(
      Id = instances[0].Id,
      Health_Status__c = healthStatus,
      Last_Health_Check_At__c = Datetime.now()
    );
  }
}
