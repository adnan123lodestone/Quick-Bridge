public with sharing class IntegrationWorkAdminController {
    public class WorkActionResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<Integration_Work_Item__c> getRecentWorkItems(String statusFilter, Integer limitSize) {
        Integer rowLimit = limitSize == null || limitSize <= 0 ? 50 : Math.min(200, limitSize);
        if (String.isBlank(statusFilter) || statusFilter == 'All') {
            return [
                SELECT Id, Name, Status__c, Integration__c, Operation__c, Lock_Key__c, Attempt_Count__c,
                    Next_Attempt_At__c, Last_Error__c, CreatedDate, LastModifiedDate
                FROM Integration_Work_Item__c
                ORDER BY LastModifiedDate DESC
                LIMIT :rowLimit
            ];
        }
        return [
            SELECT Id, Name, Status__c, Integration__c, Operation__c, Lock_Key__c, Attempt_Count__c,
                Next_Attempt_At__c, Last_Error__c, CreatedDate, LastModifiedDate
            FROM Integration_Work_Item__c
            WHERE Status__c = :statusFilter
            ORDER BY LastModifiedDate DESC
            LIMIT :rowLimit
        ];
    }

    @AuraEnabled
    public static WorkActionResponse retryNow(Id workItemId) {
        WorkActionResponse response = new WorkActionResponse();
        update new Integration_Work_Item__c(
            Id = workItemId,
            Status__c = IntegrationWorkService.STATUS_PENDING,
            Next_Attempt_At__c = System.now(),
            Last_Error__c = null,
            Processor_Token__c = null,
            Lease_Expires_At__c = null
        );
        response.success = true;
        response.message = 'Work item queued for retry.';
        if (!Test.isRunningTest()) {
            System.enqueueJob(new IntegrationWorkDispatcher());
        }
        return response;
    }

    @AuraEnabled
    public static WorkActionResponse cancel(Id workItemId) {
        WorkActionResponse response = new WorkActionResponse();
        update new Integration_Work_Item__c(
            Id = workItemId,
            Status__c = IntegrationWorkService.STATUS_CANCELLED,
            Processor_Token__c = null,
            Lease_Expires_At__c = null
        );
        response.success = true;
        response.message = 'Work item cancelled.';
        return response;
    }

    @AuraEnabled
    public static WorkActionResponse requeue(Id workItemId) {
        return retryNow(workItemId);
    }
}
