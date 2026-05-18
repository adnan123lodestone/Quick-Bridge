public with sharing class IntegrationUsageAggregator implements Queueable {
    private static Boolean aggregationQueued = false;

    public void execute(QueueableContext context) {
        aggregatePendingEvents();
    }

    public static void requestAggregation() {
        if (Test.isRunningTest() || aggregationQueued || System.isBatch() || System.isFuture()) {
            return;
        }
        aggregationQueued = true;
        try {
            System.enqueueJob(new IntegrationUsageAggregator());
        } catch (Exception ignored) {
        }
    }

    public static void aggregatePendingEvents() {
        List<Integration_Usage_Event__c> events = [
            SELECT Id, Product_Key__c, Summary_Field__c, Count__c
            FROM Integration_Usage_Event__c
            WHERE Processed__c = false
            ORDER BY CreatedDate ASC
            LIMIT 2000
        ];
        if (events.isEmpty()) {
            return;
        }

        Map<String, Map<String, Integer>> incrementsByProduct = new Map<String, Map<String, Integer>>();
        for (Integration_Usage_Event__c eventRecord : events) {
            if (String.isBlank(eventRecord.Product_Key__c) || String.isBlank(eventRecord.Summary_Field__c)) {
                continue;
            }
            if (!incrementsByProduct.containsKey(eventRecord.Product_Key__c)) {
                incrementsByProduct.put(eventRecord.Product_Key__c, new Map<String, Integer>());
            }
            Map<String, Integer> increments = incrementsByProduct.get(eventRecord.Product_Key__c);
            Integer current = increments.containsKey(eventRecord.Summary_Field__c) ? increments.get(eventRecord.Summary_Field__c) : 0;
            increments.put(eventRecord.Summary_Field__c, current + (eventRecord.Count__c == null ? 0 : eventRecord.Count__c.intValue()));
        }

        Map<String, Integration_Usage_Summary__c> summaries = IntegrationUsageService.getOrCreateSummariesByKeyForAggregation();
        List<Integration_Usage_Summary__c> updates = new List<Integration_Usage_Summary__c>();
        for (String productKey : incrementsByProduct.keySet()) {
            Integration_Usage_Summary__c summary = summaries.get(productKey);
            if (summary == null) {
                continue;
            }
            for (String fieldName : incrementsByProduct.get(productKey).keySet()) {
                Integer currentValue = summary.get(fieldName) == null ? 0 : ((Decimal) summary.get(fieldName)).intValue();
                summary.put(fieldName, currentValue + incrementsByProduct.get(productKey).get(fieldName));
            }
            summary.Last_Updated_At__c = Datetime.now();
            updates.add(summary);
        }
        if (!updates.isEmpty()) {
            update updates;
        }

        for (Integration_Usage_Event__c eventRecord : events) {
            eventRecord.Processed__c = true;
        }
        update events;
    }
}