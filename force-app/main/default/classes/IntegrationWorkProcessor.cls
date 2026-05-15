public with sharing class IntegrationWorkProcessor implements Queueable, Database.AllowsCallouts {
    private Id workItemId;
    private String processorToken;

    public IntegrationWorkProcessor(Id workItemId, String processorToken) {
        this.workItemId = workItemId;
        this.processorToken = processorToken;
    }

    public void execute(QueueableContext context) {
        Integration_Work_Item__c item = loadWorkItem();
        if (item == null || item.Status__c != IntegrationWorkService.STATUS_PROCESSING || item.Processor_Token__c != processorToken) {
            return;
        }

        Integration_Work_Lock__c lockRow = loadLock(item.Lock_Key__c);
        if (lockRow == null || lockRow.Work_Item__c != item.Id || lockRow.Processor_Token__c != processorToken) {
            return;
        }
        if (lockRow.Lease_Expires_At__c != null && lockRow.Lease_Expires_At__c < System.now()) {
            markRetry(item, 'Processor lease expired before execution.', true);
            releaseLock(lockRow, 'Expired');
            return;
        }

        try {
            IntegrationWorkRouter.process(item);
            Integration_Work_Item__c latest = [
                SELECT Id, Needs_Reprocess__c
                FROM Integration_Work_Item__c
                WHERE Id = :item.Id
                LIMIT 1
            ];

            if (latest.Needs_Reprocess__c == true) {
                update new Integration_Work_Item__c(
                    Id = item.Id,
                    Status__c = IntegrationWorkService.STATUS_PENDING,
                    Needs_Reprocess__c = false,
                    Next_Attempt_At__c = System.now(),
                    Processor_Token__c = null,
                    Lease_Expires_At__c = null
                );
            } else {
                update new Integration_Work_Item__c(
                    Id = item.Id,
                    Status__c = IntegrationWorkService.STATUS_COMPLETED,
                    Completed_At__c = System.now(),
                    Processor_Token__c = null,
                    Lease_Expires_At__c = null
                );
            }
            releaseLock(lockRow, 'Released');
        } catch (Exception e) {
            Boolean retryable = IntegrationRetryPolicy.isRetryable(e);
            markRetry(item, e.getTypeName() + ': ' + e.getMessage(), retryable);
            releaseLock(lockRow, retryable ? 'Released' : 'Released');
        }
    }

    private Integration_Work_Item__c loadWorkItem() {
        List<Integration_Work_Item__c> rows = [
            SELECT Id, Unique_Key__c, Status__c, Lock_Key__c, Integration__c, Operation__c,
                Source_Object__c, Source_Record_Id__c, Source_Salesforce_Id__c, Source_External_Id__c,
                Payload__c, Attempt_Count__c, Max_Attempts__c, Needs_Reprocess__c, Processor_Token__c,
                Lease_Expires_At__c, External_Result_Id__c
            FROM Integration_Work_Item__c
            WHERE Id = :workItemId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private Integration_Work_Lock__c loadLock(String lockKey) {
        List<Integration_Work_Lock__c> rows = [
            SELECT Id, Lock_Key__c, Status__c, Work_Item__c, Processor_Token__c, Lease_Expires_At__c
            FROM Integration_Work_Lock__c
            WHERE Lock_Key__c = :lockKey
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private void markRetry(Integration_Work_Item__c item, String message, Boolean retryable) {
        Integer attempts = item.Attempt_Count__c == null ? 0 : Integer.valueOf(item.Attempt_Count__c);
        attempts++;
        Integer maxAttempts = IntegrationRetryPolicy.getMaxAttempts(item);

        Integration_Work_Item__c updateItem = new Integration_Work_Item__c(
            Id = item.Id,
            Attempt_Count__c = attempts,
            Processor_Token__c = null,
            Lease_Expires_At__c = null,
            Last_Error__c = message == null ? null : message.left(131000)
        );

        if (retryable && attempts < maxAttempts) {
            updateItem.Status__c = IntegrationWorkService.STATUS_RETRY;
            updateItem.Next_Attempt_At__c = IntegrationRetryPolicy.nextAttemptAt(attempts);
        } else {
            updateItem.Status__c = IntegrationWorkService.STATUS_FAILED;
        }
        update updateItem;
    }

    private void releaseLock(Integration_Work_Lock__c lockRow, String status) {
        update new Integration_Work_Lock__c(
            Id = lockRow.Id,
            Status__c = status,
            Work_Item__c = null,
            Processor_Token__c = null,
            Processor_Job_Id__c = null,
            Lease_Expires_At__c = null
        );
    }
}
