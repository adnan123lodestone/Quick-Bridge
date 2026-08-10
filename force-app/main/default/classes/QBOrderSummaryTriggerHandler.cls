public with sharing class QBOrderSummaryTriggerHandler {
    
    public static Boolean isProcessing = false;

    public static void handleOrderSummaryTrigger(List<SObject> newList, Map<Id, SObject> oldMap, Boolean isUpdate) {
        if (isProcessing || System.isBatch() || System.isFuture() || System.isQueueable()) {
            return;
        }

        if (!Schema.getGlobalDescribe().containsKey('OrderSummary')) {
            return;
        }

        Set<Id> summaryIdsToSync = new Set<Id>();

        try {
            for (SObject summary : newList) {
                Id summaryId = (Id)summary.get('Id');
                SObject oldSummary = oldMap == null ? null : oldMap.get(summaryId);

                if (shouldSyncOrderSummary(summary, oldSummary, isUpdate)) {
                    summaryIdsToSync.add(summaryId);
                }
            }

            if (!summaryIdsToSync.isEmpty()) {
                syncOrderSummariesAsync(summaryIdsToSync);
            }
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBOrderSummaryTriggerHandler.handleOrderSummaryTrigger',
                e,
                'OrderSummary',
                newList == null || newList.isEmpty() ? null : (Id)newList[0].get('Id')
            );
        }
    }

    public static void handleOrderItemSummaryTrigger(List<SObject> newItems) {
        if (isProcessing || System.isBatch() || System.isFuture() || System.isQueueable()) {
            return;
        }

        if (!Schema.getGlobalDescribe().containsKey('OrderSummary')) {
            return;
        }

        Set<Id> summaryIdsToSync = new Set<Id>();

        try {
            for (SObject item : newItems) {
                try {
                    Id parentId = (Id)item.get('OrderSummaryId');
                    if (parentId != null) {
                        summaryIdsToSync.add(parentId);
                    }
                } catch (Exception e) {}
            }

            if (!summaryIdsToSync.isEmpty()) {
                syncOrderSummariesAsync(summaryIdsToSync);
            }
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBOrderSummaryTriggerHandler.handleOrderItemSummaryTrigger',
                e,
                'OrderItemSummary',
                null
            );
        }
    }

    @future(callout=true)
    public static void syncOrderSummariesAsync(Set<Id> summaryIds) {
        if (summaryIds == null || summaryIds.isEmpty()) return;

        isProcessing = true;
        try {
            for (Id summaryId : summaryIds) {
                try {
                    QBOrderSummaryRecordActionController.syncToQuickBooks(summaryId);
                } catch (Exception ex) {
                    ErrorLogUtility.logException(
                        'QuickBooks',
                        'QBOrderSummaryTriggerHandler.syncOrderSummariesAsync',
                        ex,
                        'OrderSummary',
                        summaryId
                    );
                }
            }
        } finally {
            isProcessing = false;
        }
    }

    private static Boolean shouldSyncOrderSummary(SObject newSummary, SObject oldSummary, Boolean isUpdate) {
        if (!isUpdate || oldSummary == null) {
            return true;
        }

        String newQbId = (String)getFieldValue(newSummary, 'QuickbookID__c');
        String oldQbId = (String)getFieldValue(oldSummary, 'QuickbookID__c');
        String newSyncToken = (String)getFieldValue(newSummary, 'SyncToken__c');
        String oldSyncToken = (String)getFieldValue(oldSummary, 'SyncToken__c');

        Boolean qbIdChanged = (newQbId != oldQbId);
        Boolean tokenChanged = (newSyncToken != oldSyncToken);

        Map<String, String> fieldMap = QBObjectMappings.getOrderSummaryToInvoiceMapping();
        Boolean functionalFieldChanged = false;

        for (String sfField : fieldMap.keySet()) {
            if (sfField.equalsIgnoreCase('QuickbookID__c') || sfField.equalsIgnoreCase('SyncToken__c')) {
                continue;
            }
            try {
                Object newVal = getFieldValue(newSummary, sfField);
                Object oldVal = getFieldValue(oldSummary, sfField);
                if (newVal != oldVal) {
                    functionalFieldChanged = true;
                    break;
                }
            } catch (Exception e) {}
        }

        if (functionalFieldChanged) return true;
        if (String.isBlank(newQbId)) return true;

        if ((qbIdChanged || tokenChanged) && !functionalFieldChanged) {
            return false;
        }

        return false;
    }

    private static Object getFieldValue(SObject obj, String fieldName) {
        if (obj == null || String.isBlank(fieldName)) return null;
        try {
            return obj.get(fieldName);
        } catch (Exception e) {
            try {
                return obj.get('QuickBridgeTLG__' + fieldName);
            } catch (Exception ex) {
                return null;
            }
        }
    }
}