public with sharing class IntegrationWorkDispatcher implements Queueable {
    public void execute(QueueableContext context) {
        dispatchDueWork();
    }

    public static void dispatchDueWork() {
        Integer batchSize = IntegrationWorkService.dispatchBatchSize();
        Integer availableQueueableJobs = Limits.getLimitQueueableJobs() - Limits.getQueueableJobs();
        if (availableQueueableJobs <= 0) {
            return;
        }
        batchSize = Math.min(batchSize, availableQueueableJobs);
        Datetime nowValue = System.now();

        List<Integration_Work_Item__c> candidates = [
            SELECT Id, Unique_Key__c, Status__c, Lock_Key__c, Integration__c, Operation__c,
                Attempt_Count__c, Max_Attempts__c, Next_Attempt_At__c
            FROM Integration_Work_Item__c
            WHERE Status__c IN ('Pending', 'Retry')
            AND (Next_Attempt_At__c = null OR Next_Attempt_At__c <= :nowValue)
            ORDER BY CreatedDate ASC
            LIMIT :batchSize
        ];
        if (candidates.isEmpty()) {
            return;
        }

        Map<String, Integration_Work_Item__c> itemByLockKey = new Map<String, Integration_Work_Item__c>();
        for (Integration_Work_Item__c item : candidates) {
            if (String.isBlank(item.Lock_Key__c) || itemByLockKey.containsKey(item.Lock_Key__c)) {
                continue;
            }
            itemByLockKey.put(item.Lock_Key__c, item);
        }
        if (itemByLockKey.isEmpty()) {
            return;
        }

        Map<String, Integration_Work_Lock__c> locksByKey = new Map<String, Integration_Work_Lock__c>();
        for (Integration_Work_Lock__c lockRow : [
            SELECT Id, Name, Lock_Key__c, Status__c, Work_Item__c, Lease_Expires_At__c, Processor_Token__c
            FROM Integration_Work_Lock__c
            WHERE Lock_Key__c IN :itemByLockKey.keySet()
            FOR UPDATE
        ]) {
            locksByKey.put(lockRow.Lock_Key__c, lockRow);
        }

        List<Integration_Work_Lock__c> locksToInsert = new List<Integration_Work_Lock__c>();
        for (String lockKey : itemByLockKey.keySet()) {
            if (!locksByKey.containsKey(lockKey)) {
                locksToInsert.add(new Integration_Work_Lock__c(
                    Name = lockKey.left(80),
                    Lock_Key__c = lockKey,
                    Status__c = 'Released'
                ));
            }
        }
        if (!locksToInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(locksToInsert, false);
            for (Integer i = 0; i < insertResults.size(); i++) {
                if (insertResults[i].isSuccess()) {
                    Integration_Work_Lock__c insertedLock = locksToInsert[i];
                    locksByKey.put(insertedLock.Lock_Key__c, insertedLock);
                }
            }
        }

        List<Integration_Work_Item__c> itemsToUpdate = new List<Integration_Work_Item__c>();
        List<Integration_Work_Lock__c> locksToUpdate = new List<Integration_Work_Lock__c>();
        Map<Id, String> tokenByItemId = new Map<Id, String>();
        Datetime leaseExpiresAt = nowValue.addMinutes(IntegrationWorkService.leaseMinutes());

        for (String lockKey : itemByLockKey.keySet()) {
            Integration_Work_Item__c item = itemByLockKey.get(lockKey);
            Integration_Work_Lock__c lockRow = locksByKey.get(lockKey);
            if (lockRow == null || hasActiveLease(lockRow, nowValue)) {
                continue;
            }

            String token = newProcessorToken(item.Id);
            tokenByItemId.put(item.Id, token);

            itemsToUpdate.add(new Integration_Work_Item__c(
                Id = item.Id,
                Status__c = IntegrationWorkService.STATUS_PROCESSING,
                Processor_Token__c = token,
                Processing_Started_At__c = nowValue,
                Last_Attempt_At__c = nowValue,
                Lease_Expires_At__c = leaseExpiresAt,
                Last_Error__c = null
            ));

            locksToUpdate.add(new Integration_Work_Lock__c(
                Id = lockRow.Id,
                Work_Item__c = item.Id,
                Status__c = 'Locked',
                Processor_Token__c = token,
                Lease_Expires_At__c = leaseExpiresAt
            ));

            if (itemsToUpdate.size() >= availableQueueableJobs) {
                break;
            }
        }

        if (itemsToUpdate.isEmpty()) {
            return;
        }

        update locksToUpdate;
        update itemsToUpdate;

        List<Integration_Work_Item__c> jobUpdates = new List<Integration_Work_Item__c>();
        List<Integration_Work_Lock__c> lockJobUpdates = new List<Integration_Work_Lock__c>();
        Map<Id, Integration_Work_Lock__c> lockByItemId = new Map<Id, Integration_Work_Lock__c>();
        for (Integration_Work_Lock__c lockRow : locksToUpdate) {
            lockByItemId.put(lockRow.Work_Item__c, lockRow);
        }

        for (Integration_Work_Item__c item : itemsToUpdate) {
            String token = tokenByItemId.get(item.Id);
            Id jobId = System.enqueueJob(new IntegrationWorkProcessor(item.Id, token));
            jobUpdates.add(new Integration_Work_Item__c(Id = item.Id, Processor_Job_Id__c = String.valueOf(jobId)));
            Integration_Work_Lock__c lockRow = lockByItemId.get(item.Id);
            if (lockRow != null) {
                lockJobUpdates.add(new Integration_Work_Lock__c(Id = lockRow.Id, Processor_Job_Id__c = String.valueOf(jobId)));
            }
        }

        if (!jobUpdates.isEmpty()) {
            update jobUpdates;
        }
        if (!lockJobUpdates.isEmpty()) {
            update lockJobUpdates;
        }
    }

    private static Boolean hasActiveLease(Integration_Work_Lock__c lockRow, Datetime nowValue) {
        return lockRow.Status__c == 'Locked'
            && lockRow.Lease_Expires_At__c != null
            && lockRow.Lease_Expires_At__c > nowValue;
    }

    private static String newProcessorToken(Id itemId) {
        String seed = String.valueOf(itemId) + ':' + UserInfo.getUserId() + ':' + String.valueOf(System.now().getTime()) + ':' + String.valueOf(Limits.getCpuTime());
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed))).left(64);
    }
}