public class RetryDispatcher {
  private static final Integer MAX_RETRY_COUNT = 3;
  private static final Integer MAX_AGE_DAYS = 30;

  @AuraEnabled
  public static String retryError(Id errorLogId) {
    Error_Log__c log = [
      SELECT
        Id,
        Gateway_Name__c,
        Source_Object__c,
        Source_Record_Id__c,
        Class_Method_Name__c,
        Error_Message__c,
        Retry_Count__c,
        Is_Retryable__c,
        CreatedDate,
        Retry_Status__c,
        Retry_History_Notes__c
      FROM Error_Log__c
      WHERE Id = :errorLogId
      LIMIT 1
    ];

    // Validations
    if (!log.Is_Retryable__c) {
      throw new AuraHandledException('This error is not retryable.');
    }
    if (log.Retry_Count__c >= MAX_RETRY_COUNT) {
      throw new AuraHandledException('Max retry limit reached.');
    }
    if (log.CreatedDate < Datetime.now().addDays(-MAX_AGE_DAYS)) {
      throw new AuraHandledException('Error is older than 30 days.');
    }

    // Update status
    log.Retry_Status__c = 'Retrying';
    update log;

    String result;
    try {
      if (log.Gateway_Name__c == 'QuickBooks') {
        result = QBOErrorHandler.handle(log);
      } else if (log.Gateway_Name__c == 'Shopify') {
        result = ShopifyErrorHandler.handle(log);
      } else {
        throw new AuraHandledException('Unsupported gateway.');
      }

      log.Retry_Status__c = 'Success';
      log.Retry_History_Notes__c = appendNote(
        log.Retry_History_Notes__c,
        'Retry succeeded at ' + Datetime.now()
      );
    } catch (Exception e) {
      log.Retry_Count__c =
        (log.Retry_Count__c == null ? 0 : log.Retry_Count__c) + 1;
      log.Retry_Status__c = (log.Retry_Count__c >= MAX_RETRY_COUNT)
        ? 'Failed'
        : 'Pending';
      log.Retry_History_Notes__c = appendNote(
        log.Retry_History_Notes__c,
        'Retry failed at ' + Datetime.now() + ': ' + e.getMessage()
      );
      throw new AuraHandledException('Retry failed: ' + e.getMessage());
    } finally {
      update log;
    }
    return result;
  }

  private static String appendNote(String existing, String newNote) {
    String timestamp = Datetime.now().format();
    String entry = '[' + timestamp + '] ' + newNote;
    if (String.isBlank(existing))
      return entry;
    return existing + '\n' + entry;
  }
}
