public class QBAccountBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {
    private List<Account> accountsToProcess;
    private Boolean isInsert;
    
    public QBAccountBatch(List<Account> accounts, Boolean isInsert) {
        this.accountsToProcess = accounts;
        this.isInsert = isInsert;
    }
    
    public Iterable<sObject> start(Database.BatchableContext bc) {
        return accountsToProcess;
    }
    
    public void execute(Database.BatchableContext bc, List<Account> scope) {
        QBAccountService.syncAccountsToQuickBooks(scope, isInsert);
    }
    
    public void finish(Database.BatchableContext bc) {
        // Optional: Send notification or log completion
        System.debug('QBAccountBatch completed');
    }
}