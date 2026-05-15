public class LockSafeDml {
    public class Result {
        public Boolean hasLockFailure = false;
        public Boolean hasPermanentFailure = false;
        public List<Id> succeededIds = new List<Id>();
        public List<Id> failedRecordIds = new List<Id>();
        public List<String> lockErrorMessages = new List<String>();
        public List<String> permanentErrorMessages = new List<String>();

        public Boolean hasFailures() {
            return hasLockFailure || hasPermanentFailure;
        }

        public String summarizeErrors() {
            List<String> messages = new List<String>();
            messages.addAll(lockErrorMessages);
            messages.addAll(permanentErrorMessages);
            return String.join(messages, '\n');
        }
    }

    public static Result insertRecords(List<SObject> records) {
        return parseResults(records, Database.insert(records, false));
    }

    public static Result updateRecords(List<SObject> records) {
        return parseResults(records, Database.update(records, false));
    }

    public static Result upsertRecords(List<SObject> records) {
        return parseResults(records, Database.upsert(records, false));
    }

    public static Boolean isLockError(Database.Error error) {
        return error != null && (
            error.getStatusCode() == StatusCode.UNABLE_TO_LOCK_ROW
            || IntegrationRetryPolicy.isRetryableMessage(error.getMessage())
        );
    }

    private static Result parseResults(List<SObject> records, List<Database.SaveResult> saveResults) {
        Result parsed = new Result();
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult saveResult = saveResults[i];
            parseOneResult(parsed, records, i, saveResult.isSuccess(), saveResult.getId(), saveResult.getErrors());
        }
        return parsed;
    }

    private static Result parseResults(List<SObject> records, List<Database.UpsertResult> saveResults) {
        Result parsed = new Result();
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.UpsertResult saveResult = saveResults[i];
            parseOneResult(parsed, records, i, saveResult.isSuccess(), saveResult.getId(), saveResult.getErrors());
        }
        return parsed;
    }

    private static void parseOneResult(Result parsed, List<SObject> records, Integer index, Boolean isSuccess, Id resultId, Database.Error[] errors) {
        SObject record = records == null || index >= records.size() ? null : records[index];
        if (isSuccess) {
            parsed.succeededIds.add(resultId);
            return;
        }

        if (record != null && record.Id != null) {
            parsed.failedRecordIds.add(record.Id);
        }

        for (Database.Error error : errors) {
            String message = error.getStatusCode() + ': ' + error.getMessage();
            if (isLockError(error)) {
                parsed.hasLockFailure = true;
                parsed.lockErrorMessages.add(message);
            } else {
                parsed.hasPermanentFailure = true;
                parsed.permanentErrorMessages.add(message);
            }
        }
    }
}