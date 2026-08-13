public with sharing class IntegrationUsageAggregator implements Queueable {
  private static Boolean aggregationQueued = false;
  private static final Integer DEFAULT_BATCH_SIZE = 2000;
  private static final Integer DEFAULT_STALE_MINUTES = 60;
  private static final Set<String> SUPPORTED_SUMMARY_FIELDS = new Set<String>{
    'Record_Sync_Count__c',
    'Error_Count__c',
    'Endpoint_Usage_Count__c'
  };

  public void execute(QueueableContext context) {
    aggregatePendingEvents();
  }

  public static void requestAggregation() {
    if (
      Test.isRunningTest() ||
      aggregationQueued ||
      System.isBatch() ||
      System.isFuture() ||
      System.isQueueable()
    ) {
      return;
    }
    aggregationQueued = true;
    try {
      System.enqueueJob(new IntegrationUsageAggregator());
    } catch (Exception ignored) {
    }
  }

  public static void aggregatePendingEvents() {
    recoverStaleProcessingEvents(DEFAULT_STALE_MINUTES);

    String processingToken = generateProcessingToken();
    Datetime nowValue = Datetime.now();
    List<Integration_Usage_Event__c> events = claimPendingEvents(
      processingToken,
      nowValue,
      DEFAULT_BATCH_SIZE
    );
    if (events.isEmpty()) {
      return;
    }

    try {
      events = [
        SELECT
          Id,
          Product_Key__c,
          Summary_Field__c,
          Count__c,
          Processing_Token__c,
          Processing_Status__c,
          Processed__c
        FROM Integration_Usage_Event__c
        WHERE
          Processing_Token__c = :processingToken
          AND Processing_Status__c = 'Processing'
          AND Processed__c = FALSE
      ];

      Map<String, Map<String, Integer>> incrementsByProduct = new Map<String, Map<String, Integer>>();
      for (Integration_Usage_Event__c eventRecord : events) {
        if (
          String.isBlank(eventRecord.Product_Key__c) ||
          String.isBlank(eventRecord.Summary_Field__c) ||
          !SUPPORTED_SUMMARY_FIELDS.contains(eventRecord.Summary_Field__c)
        ) {
          continue;
        }
        if (!incrementsByProduct.containsKey(eventRecord.Product_Key__c)) {
          incrementsByProduct.put(
            eventRecord.Product_Key__c,
            new Map<String, Integer>()
          );
        }
        Map<String, Integer> increments = incrementsByProduct.get(
          eventRecord.Product_Key__c
        );
        Integer current = increments.containsKey(eventRecord.Summary_Field__c)
          ? increments.get(eventRecord.Summary_Field__c)
          : 0;
        increments.put(
          eventRecord.Summary_Field__c,
          current +
          (eventRecord.Count__c == null ? 0 : eventRecord.Count__c.intValue())
        );
      }

      Map<String, Integration_Usage_Summary__c> summaries = IntegrationUsageService.getOrCreateSummariesByKeyForAggregation();
      List<Integration_Usage_Summary__c> updates = new List<Integration_Usage_Summary__c>();
      for (String productKey : incrementsByProduct.keySet()) {
        Integration_Usage_Summary__c summary = summaries.get(productKey);
        if (summary == null) {
          continue;
        }
        for (String fieldName : incrementsByProduct.get(productKey).keySet()) {
          Integer currentValue = summary.get(fieldName) == null
            ? 0
            : ((Decimal) summary.get(fieldName)).intValue();
          summary.put(
            fieldName,
            currentValue + incrementsByProduct.get(productKey).get(fieldName)
          );
        }
        summary.Last_Updated_At__c = Datetime.now();
        updates.add(summary);
      }
      if (!updates.isEmpty()) {
        update updates;
      }

      for (Integration_Usage_Event__c eventRecord : events) {
        eventRecord.Processed__c = true;
        eventRecord.Processing_Status__c = 'Processed';
        eventRecord.Processed_At__c = Datetime.now();
        eventRecord.Aggregation_Error__c = null;
      }
      update events;
    } catch (Exception e) {
      markClaimedEventsFailed(processingToken, e.getMessage());
    }
  }

  public static Integer recoverStaleProcessingEvents(
    Integer staleAfterMinutes
  ) {
    Integer thresholdMinutes = staleAfterMinutes == null ||
      staleAfterMinutes <= 0
      ? DEFAULT_STALE_MINUTES
      : staleAfterMinutes;
    Datetime staleBefore = Datetime.now().addMinutes(-thresholdMinutes);
    List<Integration_Usage_Event__c> staleEvents = [
      SELECT
        Id,
        Processing_Status__c,
        Processing_Token__c,
        Processing_Started_At__c,
        Aggregation_Error__c
      FROM Integration_Usage_Event__c
      WHERE
        Processed__c = FALSE
        AND Processing_Status__c = 'Processing'
        AND Processing_Started_At__c < :staleBefore
      LIMIT :DEFAULT_BATCH_SIZE
      FOR UPDATE
    ];
    for (Integration_Usage_Event__c eventRecord : staleEvents) {
      eventRecord.Processing_Status__c = 'Pending';
      eventRecord.Processing_Token__c = null;
      eventRecord.Processing_Started_At__c = null;
      eventRecord.Aggregation_Error__c = null;
    }
    if (!staleEvents.isEmpty()) {
      update staleEvents;
    }
    return staleEvents.size();
  }

  private static List<Integration_Usage_Event__c> claimPendingEvents(
    String processingToken,
    Datetime nowValue,
    Integer batchSize
  ) {
    List<Integration_Usage_Event__c> events = [
      SELECT
        Id,
        Processing_Status__c,
        Processing_Token__c,
        Processing_Started_At__c,
        Processed__c
      FROM Integration_Usage_Event__c
      WHERE
        Processed__c = FALSE
        AND (Processing_Status__c = 'Pending'
        OR Processing_Status__c = NULL
        OR Processing_Status__c = 'Failed')
      LIMIT :batchSize
      FOR UPDATE
    ];
    for (Integration_Usage_Event__c eventRecord : events) {
      eventRecord.Processing_Status__c = 'Processing';
      eventRecord.Processing_Token__c = processingToken;
      eventRecord.Processing_Started_At__c = nowValue;
      eventRecord.Aggregation_Error__c = null;
    }
    if (!events.isEmpty()) {
      update events;
    }
    return events;
  }

  private static void markClaimedEventsFailed(
    String processingToken,
    String message
  ) {
    List<Integration_Usage_Event__c> events = [
      SELECT Id, Processing_Status__c, Processing_Token__c, Aggregation_Error__c
      FROM Integration_Usage_Event__c
      WHERE
        Processing_Token__c = :processingToken
        AND Processing_Status__c = 'Processing'
        AND Processed__c = FALSE
      FOR UPDATE
    ];
    for (Integration_Usage_Event__c eventRecord : events) {
      eventRecord.Processing_Status__c = 'Failed';
      eventRecord.Aggregation_Error__c = String.isBlank(message)
        ? 'Usage aggregation failed.'
        : message.left(32768);
    }
    if (!events.isEmpty()) {
      update events;
    }
  }

  private static String generateProcessingToken() {
    String seed =
      UserInfo.getOrganizationId() +
      ':' +
      UserInfo.getUserId() +
      ':' +
      String.valueOf(Datetime.now().getTime()) +
      ':' +
      String.valueOf(Math.random());
    return EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(seed))
      )
      .substring(0, 64);
  }
}