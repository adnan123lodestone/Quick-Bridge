public class QBCreditMemoInboundBatch implements Database.Batchable<String>, Database.AllowsCallouts {

    private String lastSyncDate;

    public QBCreditMemoInboundBatch() {
        Datetime yesterday = Datetime.now().addDays(-1);
        this.lastSyncDate = yesterday.format('yyyy-MM-dd');
    }

    public QBCreditMemoInboundBatch(String syncDate) {
        this.lastSyncDate = syncDate;
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> payloads = new List<String>();
        try {
            payloads = QuickBooksBulkQueryService.serializeRecords(
                QuickBooksBulkQueryService.queryUpdatedSince('CreditMemo', lastSyncDate)
            );
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBCreditMemoInboundBatch.start', e, null, null);
        }
        return payloads;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        IntegrationUsageService.assertCanConsumeTask('QuickBooks', scope == null ? 1 : scope.size());
        List<Credit_Memo__c> recordsToUpsert = new List<Credit_Memo__c>();

        for (String payload : scope) {
            try {
                Map<String, Object> qbRecord = (Map<String, Object>) JSON.deserializeUntyped(payload);
                String qbId = (String) qbRecord.get('Id');
                if (String.isBlank(qbId)) continue;

                Credit_Memo__c cm = new Credit_Memo__c();
                cm.External_Id__c = qbId;
                cm.Is_Synced__c = true;

                Object docNumber = qbRecord.get('DocNumber');
                if (docNumber != null) {
                    cm.Txn_Number__c = String.valueOf(docNumber);
                }

                Object txnDate = qbRecord.get('TxnDate');
                if (txnDate != null) {
                    try { cm.Txn_Date__c = Date.valueOf(String.valueOf(txnDate)); } catch (Exception e) {}
                }

                Object dueDate = qbRecord.get('DueDate');
                if (dueDate != null) {
                    try { cm.Due_Date__c = Date.valueOf(String.valueOf(dueDate)); } catch (Exception e) {}
                }

                Object balance = qbRecord.get('Balance');
                if (balance != null) {
                    try { cm.Credit_Remaining__c = Decimal.valueOf(String.valueOf(balance)); } catch (Exception e) {}
                }

                // Link to Account via CustomerRef
                Object customerRefObj = qbRecord.get('CustomerRef');
                if (customerRefObj instanceof Map<String, Object>) {
                    String customerId = (String) ((Map<String, Object>) customerRefObj).get('value');
                    if (String.isNotBlank(customerId)) {
                        List<Account> matchingAccounts = [
                            SELECT Id FROM Account WHERE QuickbookID__c = :customerId LIMIT 1
                        ];
                        if (!matchingAccounts.isEmpty()) {
                            cm.Customer__c = matchingAccounts[0].Id;
                        }
                    }
                }

                recordsToUpsert.add(cm);
            } catch (Exception e) {
                ErrorLogUtility.logException('QuickBooks', 'QBCreditMemoInboundBatch.execute.processRow', e, 'Credit_Memo__c', null);
            }
        }

        if (!recordsToUpsert.isEmpty()) {
            Database.UpsertResult[] results = Database.upsert(recordsToUpsert, Credit_Memo__c.External_Id__c, false);
            Integer successCount = 0;
            for (Database.UpsertResult r : results) {
                if (r.isSuccess()) successCount++;
            }
            if (successCount > 0) {
                IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', successCount);
            }
            ErrorLogUtility.logUpsertResults(
                'QuickBooks', 'QBCreditMemoInboundBatch.execute.upsert',
                'upsert', recordsToUpsert, results, null, null
            );
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('QBCreditMemoInboundBatch completed');
    }
}