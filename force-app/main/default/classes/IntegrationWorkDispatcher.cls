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
                Attempt_Count__c, Max_Attempts__c, Next_Attempt_At__c, Additional_Lock_Keys__c
            FROM Integration_Work_Item__c
            WHERE Status__c IN ('Pending', 'Retry')
            AND (Next_Attempt_At__c = null OR Next_Attempt_At__c <= :nowValue)
            ORDER BY CreatedDate ASC
            LIMIT :batchSize
        ];
        if (candidates.isEmpty()) {
            return;
        }

        Map<Id, Integration_Work_Item__c> selectedById = new Map<Id, Integration_Work_Item__c>();
        Map<Id, List<String>> lockKeysByItemId = new Map<Id, List<String>>();
        Set<String> selectedLockKeys = new Set<String>();
        List<Integration_Work_Item__c> malformedItems = new List<Integration_Work_Item__c>();

        for (Integration_Work_Item__c item : candidates) {
            List<String> itemLockKeys;
            try {
                itemLockKeys = lockKeysFor(item);
            } catch (Exception e) {
                malformedItems.add(new Integration_Work_Item__c(
                    Id = item.Id,
                    Status__c = IntegrationWorkService.STATUS_FAILED,
                    Last_Error__c = 'Invalid Additional_Lock_Keys__c JSON: ' + e.getMessage()
                ));
                continue;
            }
            if (itemLockKeys.isEmpty() || overlaps(selectedLockKeys, itemLockKeys)) {
                continue;
            }
            selectedById.put(item.Id, item);
            lockKeysByItemId.put(item.Id, itemLockKeys);
            selectedLockKeys.addAll(itemLockKeys);
        }
        if (!malformedItems.isEmpty()) {
            update malformedItems;
        }
        if (selectedById.isEmpty()) {
            return;
        }

        Map<String, Integration_Work_Lock__c> locksByKey = new Map<String, Integration_Work_Lock__c>();
        for (Integration_Work_Lock__c lockRow : [
            SELECT Id, Name, Lock_Key__c, Status__c, Work_Item__c, Lease_Expires_At__c, Processor_Token__c
            FROM Integration_Work_Lock__c
            WHERE Lock_Key__c IN :selectedLockKeys
            LIMIT :selectedLockKeys.size()
            FOR UPDATE
        ]) {
            locksByKey.put(lockRow.Lock_Key__c, lockRow);
        }

        List<Integration_Work_Lock__c> locksToInsert = new List<Integration_Work_Lock__c>();
        for (String lockKey : selectedLockKeys) {
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

        for (Integration_Work_Item__c item : selectedById.values()) {
            List<String> itemLockKeys = lockKeysByItemId.get(item.Id);
            if (!allLocksAvailable(itemLockKeys, locksByKey, nowValue)) {
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

            for (String lockKey : itemLockKeys) {
                Integration_Work_Lock__c lockRow = locksByKey.get(lockKey);
                locksToUpdate.add(new Integration_Work_Lock__c(
                    Id = lockRow.Id,
                    Work_Item__c = item.Id,
                    Status__c = 'Locked',
                    Processor_Token__c = token,
                    Lease_Expires_At__c = leaseExpiresAt
                ));
            }

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
        Map<Id, List<Integration_Work_Lock__c>> locksByItemId = new Map<Id, List<Integration_Work_Lock__c>>();
        for (Integration_Work_Lock__c lockRow : locksToUpdate) {
            if (!locksByItemId.containsKey(lockRow.Work_Item__c)) {
                locksByItemId.put(lockRow.Work_Item__c, new List<Integration_Work_Lock__c>());
            }
            locksByItemId.get(lockRow.Work_Item__c).add(lockRow);
        }

        for (Integration_Work_Item__c item : itemsToUpdate) {
            String token = tokenByItemId.get(item.Id);
            Id jobId = System.enqueueJob(new IntegrationWorkProcessor(item.Id, token));
            jobUpdates.add(new Integration_Work_Item__c(Id = item.Id, Processor_Job_Id__c = String.valueOf(jobId)));
            for (Integration_Work_Lock__c lockRow : locksByItemId.get(item.Id)) {
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

    private static Boolean overlaps(Set<String> selectedLockKeys, List<String> itemLockKeys) {
        for (String lockKey : itemLockKeys) {
            if (selectedLockKeys.contains(lockKey)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean allLocksAvailable(List<String> itemLockKeys, Map<String, Integration_Work_Lock__c> locksByKey, Datetime nowValue) {
        for (String lockKey : itemLockKeys) {
            Integration_Work_Lock__c lockRow = locksByKey.get(lockKey);
            if (lockRow == null || hasActiveLease(lockRow, nowValue)) {
                return false;
            }
        }
        return true;
    }

    private static List<String> lockKeysFor(Integration_Work_Item__c item) {
        Set<String> keys = new Set<String>();
        if (String.isNotBlank(item.Lock_Key__c)) {
            keys.add(item.Lock_Key__c.trim());
        }
        if (String.isNotBlank(item.Additional_Lock_Keys__c)) {
            Object parsed = JSON.deserializeUntyped(item.Additional_Lock_Keys__c);
            if (!(parsed instanceof List<Object>)) {
                throw new AuraHandledException('Expected a JSON array of lock keys.');
            }
            for (Object value : (List<Object>) parsed) {
                if (value != null && String.isNotBlank(String.valueOf(value))) {
                    keys.add(String.valueOf(value).trim());
                }
            }
        }
        return new List<String>(keys);
    }

    private static String newProcessorToken(Id itemId) {
        String seed = String.valueOf(itemId) + ':' + UserInfo.getUserId() + ':' + String.valueOf(System.now().getTime()) + ':' + String.valueOf(Limits.getCpuTime());
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed))).left(64);
    }
}