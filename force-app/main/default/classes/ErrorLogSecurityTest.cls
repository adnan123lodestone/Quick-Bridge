@isTest
private class ErrorLogSecurityTest {
  // A user guaranteed NOT to hold the QuickBridge custom permissions, so the
  // guard's FeatureManagement.checkPermission returns false for the deny tests.
  private static User minimalUser() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    return new User(
      Alias = 'qbminu',
      Email = 'qb.minimal@example.com.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Minimal',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'qb.minimal.' + System.now().getTime() + '@example.com.invalid'
    );
  }

  private static Error_Log__c seedLog() {
    Error_Log__c log = new Error_Log__c(
      Gateway_Name__c = 'QuickBooks',
      Error_Category__c = 'Callout Failure',
      Error_Message__c = 'Auth failed token=abcd1234 password=hunter2 Authorization: Bearer XyZ.123',
      Retry_Count__c = 0
    );
    insert log;
    return log;
  }

  @isTest
  static void getDynamicLogsRequiresViewPermission() {
    seedLog();
    QuickBridgeAdminGuard.bypassForTests = false; // honor real permission checks
    User u = minimalUser();
    insert u;

    Test.startTest();
    Boolean blocked = false;
    System.runAs(u) {
      try {
        ErrorLogUtility.getDynamicLogs('QuickBooks');
      } catch (Exception e) {
        blocked = true;
      }
    }
    Test.stopTest();

    System.assertEquals(
      true,
      blocked,
      'Log read must be blocked without View_QuickBridge.'
    );
  }

  @isTest
  static void updateRetryCountRequiresRunSyncPermission() {
    Error_Log__c log = seedLog();
    QuickBridgeAdminGuard.bypassForTests = false; // honor real permission checks
    User u = minimalUser();
    insert u;

    Test.startTest();
    Boolean blocked = false;
    System.runAs(u) {
      try {
        ErrorLogUtility.updateRetryCount(log.Id);
      } catch (Exception e) {
        blocked = true;
      }
    }
    Test.stopTest();

    System.assertEquals(
      true,
      blocked,
      'Retry update must be blocked without Run_QuickBridge_Sync/Manage.'
    );
  }

  @isTest
  static void getDynamicLogsRedactsSecretsInMessage() {
    seedLog();
    // bypassForTests default -> guard allows in test context.

    Test.startTest();
    Map<String, Object> result = ErrorLogUtility.getDynamicLogs('QuickBooks');
    Test.stopTest();

    List<Error_Log__c> records = (List<Error_Log__c>) result.get('records');
    System.assert(!records.isEmpty(), 'Expected at least one log record.');
    String msg = records[0].Error_Message__c;
    System.assert(
      !msg.contains('hunter2') && !msg.contains('abcd1234'),
      'Credential values must be redacted: ' + msg
    );
    // The bare token after "Bearer" must NOT survive (regression guard).
    System.assert(
      !msg.contains('XyZ.123'),
      'Bearer token value must be fully redacted: ' + msg
    );
    System.assert(
      msg.contains('REDACTED'),
      'Redaction marker expected: ' + msg
    );
  }

  @isTest
  static void redactSensitiveHandlesBlankAndPlainText() {
    System.assertEquals(null, ErrorLogUtility.redactSensitive(null));
    System.assertEquals('', ErrorLogUtility.redactSensitive(''));
    System.assertEquals(
      'A plain message with no secrets.',
      ErrorLogUtility.redactSensitive('A plain message with no secrets.')
    );
  }
}