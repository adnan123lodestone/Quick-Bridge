public without sharing class ErrorLogLinkBackfillService {
    public class BackfillResult {
        @AuraEnabled public Integer scanned { get; set; }
        @AuraEnabled public Integer created { get; set; }
    }

    public static BackfillResult backfillMissingLinks(Integer limitSize) {
        Integer effectiveLimit = limitSize == null || limitSize <= 0 ? 200 : Math.min(limitSize, 2000);
        List<Error_Log__c> logs = [
            SELECT Id, Source_Object__c, Source_Record_Id__c, Action_Source_Object__c, Action_Source_Record_Id__c, Order_Id__c
            FROM Error_Log__c
            ORDER BY CreatedDate ASC
            LIMIT :effectiveLimit
        ];

        BackfillResult result = new BackfillResult();
        result.scanned = logs.size();
        result.created = 0;
        if (logs.isEmpty()) {
            return result;
        }

        Set<Id> logIds = new Map<Id, Error_Log__c>(logs).keySet();
        Set<String> existingKeys = new Set<String>();
        for (Error_Log_Link__c link : [
            SELECT Error_Log__c, Linked_Object_API_Name__c, Linked_Record_Id__c, Relationship_Role__c
            FROM Error_Log_Link__c
            WHERE Error_Log__c IN :logIds
        ]) {
            existingKeys.add(linkKey(link.Error_Log__c, link.Linked_Object_API_Name__c, link.Linked_Record_Id__c, link.Relationship_Role__c));
        }

        List<Error_Log_Link__c> linksToInsert = new List<Error_Log_Link__c>();
        for (Error_Log__c logRecord : logs) {
            addMissingLink(linksToInsert, existingKeys, logRecord.Id, logRecord.Source_Object__c, logRecord.Source_Record_Id__c, 'Source');
            addMissingLink(linksToInsert, existingKeys, logRecord.Id, logRecord.Action_Source_Object__c, logRecord.Action_Source_Record_Id__c, 'Action Source');
            if (String.isNotBlank(logRecord.Order_Id__c)) {
                addMissingLink(linksToInsert, existingKeys, logRecord.Id, 'Order', logRecord.Order_Id__c, 'Source');
            }
        }

        if (!linksToInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(linksToInsert, false);
            for (Database.SaveResult saveResult : saveResults) {
                if (saveResult != null && saveResult.isSuccess()) {
                    result.created++;
                }
            }
        }
        return result;
    }

    private static void addMissingLink(
        List<Error_Log_Link__c> linksToInsert,
        Set<String> existingKeys,
        Id errorLogId,
        String objectApiName,
        String recordIdText,
        String role
    ) {
        if (errorLogId == null || String.isBlank(objectApiName) || String.isBlank(recordIdText)) {
            return;
        }
        String key = linkKey(errorLogId, objectApiName, recordIdText, role);
        if (existingKeys.contains(key)) {
            return;
        }
        existingKeys.add(key);
        linksToInsert.add(new Error_Log_Link__c(
            Error_Log__c = errorLogId,
            Linked_Object_API_Name__c = objectApiName,
            Linked_Record_Id__c = recordIdText,
            Relationship_Role__c = role
        ));
    }

    private static String linkKey(Id errorLogId, String objectApiName, String recordIdText, String role) {
        return String.valueOf(errorLogId) + '|' + String.valueOf(objectApiName) + '|' + String.valueOf(recordIdText) + '|' + String.valueOf(role);
    }
}
