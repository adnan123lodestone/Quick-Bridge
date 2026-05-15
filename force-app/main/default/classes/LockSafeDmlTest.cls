@IsTest
private class LockSafeDmlTest {
    @IsTest
    static void permanentFailureIsReported() {
        List<SObject> records = new List<SObject>{ new Account() };

        LockSafeDml.Result result = LockSafeDml.insertRecords(records);

        System.assertEquals(true, result.hasPermanentFailure);
        System.assertEquals(false, result.hasLockFailure);
        System.assert(result.summarizeErrors().contains('REQUIRED_FIELD_MISSING'));
    }

    @IsTest
    static void retryPolicyDetectsLockMessages() {
        System.assertEquals(true, IntegrationRetryPolicy.isRetryableMessage('UNABLE_TO_LOCK_ROW: row locked'));
        System.assertEquals(true, IntegrationRetryPolicy.isRetryableMessage('Read timed out'));
        System.assertEquals(false, IntegrationRetryPolicy.isRetryableMessage('Required field missing'));
        System.assert(IntegrationRetryPolicy.nextAttemptAt(1) > System.now());
    }

    @IsTest
    static void successPathsReportSucceededIds() {
        Account accountRecord = new Account(Name = 'Lock Safe Success');
        LockSafeDml.Result insertResult = LockSafeDml.insertRecords(new List<SObject>{ accountRecord });
        System.assertEquals(false, insertResult.hasFailures());
        System.assertEquals(1, insertResult.succeededIds.size());

        accountRecord.Name = 'Lock Safe Updated';
        LockSafeDml.Result updateResult = LockSafeDml.updateRecords(new List<SObject>{ accountRecord });
        System.assertEquals(false, updateResult.hasFailures());

        accountRecord.Name = 'Lock Safe Upserted';
        LockSafeDml.Result upsertResult = LockSafeDml.upsertRecords(new List<SObject>{ accountRecord });
        System.assertEquals(false, upsertResult.hasFailures());
    }
}