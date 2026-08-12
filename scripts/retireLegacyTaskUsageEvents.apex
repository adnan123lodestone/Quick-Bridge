IntegrationUsageAggregator.aggregatePendingEvents();

Map<String, Integer> remainingByMetric = new Map<String, Integer>();
for (AggregateResult result : [
  SELECT Summary_Field__c metric, COUNT(Id) pendingCount
  FROM Integration_Usage_Event__c
  WHERE Processed__c = FALSE
  GROUP BY Summary_Field__c
]) {
  remainingByMetric.put(
    (String) result.get('metric'),
    (Integer) result.get('pendingCount')
  );
}

System.debug(LoggingLevel.INFO, 'Remaining pending usage events: ' + remainingByMetric);
