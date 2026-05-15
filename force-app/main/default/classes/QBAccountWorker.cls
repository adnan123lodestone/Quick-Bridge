public with sharing class QBAccountWorker {
    public static void process(Integration_Work_Item__c item) {
        Id accountId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);
        if (accountId == null) {
            throw new QBAccountWorkerException('Account work item has no Salesforce Id.');
        }

        List<Account> accounts = [
            SELECT Id, Name, QuickbookID__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new QBAccountWorkerException('Account not found: ' + accountId);
        }

        QBAccountService.syncAccountsToQuickBooks(accounts, isInitialSync(item));
    }

    private static Boolean isInitialSync(Integration_Work_Item__c item) {
        Map<String, Object> payload = IntegrationWorkService.parsePayload(item);
        return payload.containsKey('isInitialSync') && payload.get('isInitialSync') == true;
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