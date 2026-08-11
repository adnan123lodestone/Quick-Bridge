public with sharing class QBQuoteWorker implements IntegrationWorkHandler {
    public void handle(Integration_Work_Item__c item) {
        process(item);
    }

    public static void process(Integration_Work_Item__c item) {
        Id quoteId = parseId(item.Source_Salesforce_Id__c, item.Source_Record_Id__c);
        if (quoteId == null) {
            throw new QBQuoteWorkerException('Quote work item has no Salesforce Id.');
        }

        List<Quote> scope = QBQuoteToEstimateSyncBatch.loadQuotesForSharedExecution(
            new Set<Id>{ quoteId }
        );
        if (!scope.isEmpty()) {
            QBQuoteToEstimateSyncBatch batch = new QBQuoteToEstimateSyncBatch(new Set<Id>{ quoteId }, isInitialSync(item));
            ConnectorExecutionResult result = batch.executeSharedScope(scope);
            if (result == null || result.hasFailures()) {
                throw new QBQuoteWorkerException(
                    'Quote synchronization failed. ' +
                    ConnectorExecutionResult.sanitizeError(
                        result == null ? null : result.errorSummary
                    )
                );
            }
        }
    }

    private static Boolean isInitialSync(Integration_Work_Item__c item) {
        Map<String, Object> payload = IntegrationWorkService.parsePayload(item);
        return payload != null && payload.containsKey('isInitialSync') && payload.get('isInitialSync') == true;
    }

    private static Id parseId(String primaryValue, String fallbackValue) {
        if (String.isNotBlank(primaryValue)) {
            try {
                return (Id) primaryValue.trim();
            } catch (Exception ignored) {}
        }
        if (String.isNotBlank(fallbackValue)) {
            try {
                return (Id) fallbackValue.trim();
            } catch (Exception ignored) {}
        }
        return null;
    }

    public class QBQuoteWorkerException extends Exception {}
}
