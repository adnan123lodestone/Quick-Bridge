public with sharing class QBAccountWorker implements IntegrationWorkHandler {
    public void handle(Integration_Work_Item__c item) {
        process(item);
    }

    public static void process(Integration_Work_Item__c item) {
        Id accountId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);
        if (accountId == null) {
            throw new QBAccountWorkerException('Account work item has no Salesforce Id.');
        }

        Account accountRecord = QBAccountSelector.selectForOutbound(accountId);
        ConnectorExecutionResult result = QBAccountService.syncAccountsToQuickBooksShared(
            new List<Account>{ accountRecord },
            false
        );
        if (result != null && result.hasFailures()) {
            String message = String.isBlank(result.errorSummary)
                ? 'QuickBooks Account sync failed.'
                : result.errorSummary;
            throw IntegrationRetryPolicy.exceptionForStatus(
                result.retryable == true ? 503 : 400,
                message
            );
        }
    }

    private static Id parseId(String primaryValue, String fallbackValue) {
        try {
            return (Id) (String.isBlank(primaryValue) ? fallbackValue : primaryValue);
        } catch (Exception e) {
            return null;
        }
    }

    public class QBAccountWorkerException extends Exception {}
}
