public without sharing class ErrorLogLinkBackfillService {
    private static final Integer DEFAULT_LIMIT = 2000;

    public class BackfillResult {
        public Integer scanned = 0;
        public Integer inserted = 0;
        public Integer skipped = 0;
        public Integer failed = 0;
    }

    public static BackfillResult backfillMissingLinks() {
        return backfillMissingLinks(DEFAULT_LIMIT);
    }

    public static BackfillResult backfillMissingLinks(Integer maxRows) {
        BackfillResult result = new BackfillResult();
        Integer rowLimit = normalizeLimit(maxRows);

        List<Error_Log__c> errorLogs = [
            SELECT
                Id,
                Source_Object__c,
                Source_Record_Id__c,
                Action_Source_Object__c,
                Action_Source_Record_Id__c
            FROM Error_Log__c
            WHERE
                (Source_Object__c != NULL
                AND Source_Record_Id__c != NULL)
                OR (Action_Source_Object__c != NULL
                AND Action_Source_Record_Id__c != NULL)
            ORDER BY CreatedDate ASC
            LIMIT :rowLimit
        ];
        result.scanned = errorLogs.size();
        if (errorLogs.isEmpty()) {
            return result;
        }

        Set<Id> errorLogIds = new Map<Id, Error_Log__c>(errorLogs).keySet();
        Set<String> knownLinkKeys = new Set<String>();
        for (Error_Log_Link__c existingLink : [
            SELECT
                Error_Log__c,
                Linked_Object_API_Name__c,
                Linked_Record_Id__c,
                Relationship_Role__c
            FROM Error_Log_Link__c
            WHERE Error_Log__c IN :errorLogIds
        ]) {
            knownLinkKeys.add(linkKey(
                existingLink.Error_Log__c,
                existingLink.Linked_Object_API_Name__c,
                existingLink.Linked_Record_Id__c,
                existingLink.Relationship_Role__c
            ));
        }

        List<Error_Log_Link__c> linksToInsert = new List<Error_Log_Link__c>();
        for (Error_Log__c errorLog : errorLogs) {
            addMissingLink(
                linksToInsert,
                knownLinkKeys,
                result,
                errorLog.Id,
                errorLog.Source_Object__c,
                errorLog.Source_Record_Id__c,
                'Source'
            );
            addMissingLink(
                linksToInsert,
                knownLinkKeys,
                result,
                errorLog.Id,
                errorLog.Action_Source_Object__c,
                errorLog.Action_Source_Record_Id__c,
                'Action Source'
            );
        }

        if (linksToInsert.isEmpty()) {
            return result;
        }

        for (Database.SaveResult saveResult : Database.insert(linksToInsert, false)) {
            if (saveResult.isSuccess()) {
                result.inserted++;
            } else {
                result.failed++;
            }
        }
        return result;
    }

    private static Integer normalizeLimit(Integer maxRows) {
        if (maxRows == null || maxRows <= 0 || maxRows > 50000) {
            return DEFAULT_LIMIT;
        }
        return maxRows;
    }

    private static void addMissingLink(
        List<Error_Log_Link__c> linksToInsert,
        Set<String> knownLinkKeys,
        BackfillResult result,
        Id errorLogId,
        String objectApiName,
        String recordIdText,
        String role
    ) {
        if (errorLogId == null || String.isBlank(objectApiName) || String.isBlank(recordIdText)) {
            return;
        }

        String key = linkKey(errorLogId, objectApiName, recordIdText, role);
        if (knownLinkKeys.contains(key)) {
            result.skipped++;
            return;
        }

        knownLinkKeys.add(key);
        linksToInsert.add(new Error_Log_Link__c(
            Error_Log__c = errorLogId,
            Linked_Object_API_Name__c = objectApiName.trim(),
            Linked_Record_Id__c = recordIdText.trim(),
            Relationship_Role__c = role
        ));
    }

    private static String linkKey(Id errorLogId, String objectApiName, String recordIdText, String role) {
        return String.valueOf(errorLogId) +
            '|' +
            String.valueOf(role).trim().toLowerCase() +
            '|' +
            String.valueOf(objectApiName).trim().toLowerCase() +
            '|' +
            String.valueOf(recordIdText).trim();
    }
}
