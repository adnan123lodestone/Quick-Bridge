public without sharing class ConnectorInboundBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {
  private static final Integer MAX_RETRY_ATTEMPTS = 5;

  private ConnectorExecutionRequest request;
  private ConnectorExecutionResult aggregateResult;
  private Integer maximumPages;

  public ConnectorInboundBatch(ConnectorExecutionRequest request) {
    this.request = request;
    this.aggregateResult = ConnectorExecutionResult.success();
    this.maximumPages = ConnectorHttpClient.DEFAULT_MAX_PAGES;
  }

  public Iterable<Integer> start(Database.BatchableContext context) {
    try {
      request = request == null ? null : request.normalizedCopy();
      if (request == null) {
        throw new IllegalArgumentException(
          'Connector execution request is required.'
        );
      }
      request.validate();
      ConnectorOperationRegistry.OperationDefinition definition = ConnectorOperationRegistry.resolve(
        request
      );
      Integer configuredLimit = definition == null
        ? null
        : definition.maximumPages;
      maximumPages = configuredLimit == null
        ? ConnectorHttpClient.DEFAULT_MAX_PAGES
        : Math.max(
            1,
            Math.min(ConnectorHttpClient.ABSOLUTE_MAX_PAGES, configuredLimit)
          );
      Boolean leaseAccepted = ConnectorScheduleService.markRunning(
        request.scheduleId,
        request.leaseToken,
        context == null ? null : context.getJobId()
      );
      if (request.scheduleId != null && !leaseAccepted) {
        throw new IllegalArgumentException(
          'Connector inbound execution no longer owns the schedule lease.'
        );
      }
      return new List<Integer>{ 1 };
    } catch (Exception exceptionValue) {
      aggregateResult = ConnectorExecutionResult.failed(
        exceptionValue.getMessage(),
        false,
        null
      );
      return new List<Integer>();
    }
  }

  public void execute(Database.BatchableContext context, List<Integer> scope) {
    if (scope == null || scope.isEmpty() || aggregateResult.hasFailures()) {
      return;
    }
    try {
      aggregateResult.mergeFrom(
        ConnectorExecutionService.executeInboundPage(request)
      );
      renewScheduleLease(context);
    } catch (Exception exceptionValue) {
      aggregateResult.mergeFrom(
        ConnectorExecutionResult.failed(
          exceptionValue.getMessage(),
          false,
          null
        )
      );
    }
  }

  private void renewScheduleLease(Database.BatchableContext context) {
    if (
      request.scheduleId != null &&
      !ConnectorScheduleService.markRunning(
        request.scheduleId,
        request.leaseToken,
        context == null ? null : context.getJobId()
      )
    ) {
      aggregateResult.mergeFrom(
        ConnectorExecutionResult.failed(
          'Connector inbound execution no longer owns the schedule lease.',
          false,
          null
        )
      );
    }
  }

  public void finish(Database.BatchableContext context) {
    if (aggregateResult != null && shouldRetry()) {
      scheduleRetry();
      return;
    }
    if (aggregateResult == null || aggregateResult.hasFailures()) {
      ConnectorScheduleService.completeFailure(
        request == null ? null : request.scheduleId,
        request == null ? null : request.leaseToken,
        aggregateResult == null
          ? 'Connector inbound execution returned no result.'
          : aggregateResult.errorSummary
      );
      return;
    }

    if (String.isNotBlank(aggregateResult.nextCursor)) {
      if (aggregateResult.nextCursor == request.cursor) {
        ConnectorScheduleService.completeFailure(
          request.scheduleId,
          request.leaseToken,
          'Connector inbound pagination returned the same cursor twice.'
        );
        return;
      }

      Integer currentPage = request.pageNumber == null ? 1 : request.pageNumber;
      if (currentPage >= maximumPages) {
        ConnectorScheduleService.completeFailure(
          request.scheduleId,
          request.leaseToken,
          'Connector inbound pagination exceeded ' + maximumPages + ' pages.'
        );
        return;
      }

      ConnectorExecutionRequest nextRequest = request.normalizedCopy();
      nextRequest.cursor = aggregateResult.nextCursor;
      nextRequest.pageNumber = currentPage + 1;
      nextRequest.retryAttempt = 0;
      Id nextJobId = Database.executeBatch(
        new ConnectorInboundBatch(nextRequest),
        1
      );
      if (
        !ConnectorScheduleService.markRunning(
          request.scheduleId,
          request.leaseToken,
          nextJobId
        ) && request.scheduleId != null
      ) {
        return;
      }
      return;
    }

    ConnectorScheduleService.completeSuccess(
      request.scheduleId,
      request.leaseToken
    );
  }

  private Boolean shouldRetry() {
    return request != null &&
      aggregateResult != null &&
      aggregateResult.hasFailures() &&
      aggregateResult.retryable == true &&
      (request.retryAttempt == null ||
      request.retryAttempt < MAX_RETRY_ATTEMPTS);
  }

  private void scheduleRetry() {
    if (
      aggregateResult.retryDelaySeconds != null &&
      aggregateResult.retryDelaySeconds > 3600
    ) {
      ConnectorScheduleService.completeFailure(
        request.scheduleId,
        request.leaseToken,
        'Connector inbound retry delay exceeds the supported 60-minute scheduling window. ' +
        safeErrorSummary()
      );
      return;
    }

    ConnectorExecutionRequest retryRequest = request.normalizedCopy();
    retryRequest.retryAttempt =
      (request.retryAttempt == null ? 0 : request.retryAttempt) + 1;
    Integer delayMinutes = retryDelayMinutes();
    Id retryJobId = System.scheduleBatch(
      new ConnectorInboundBatch(retryRequest),
      retryJobName('ConnectorInboundRetry'),
      delayMinutes,
      1
    );
    ConnectorScheduleService.markRunning(
      request.scheduleId,
      request.leaseToken,
      retryJobId,
      delayMinutes * 60
    );
  }

  private Integer retryDelayMinutes() {
    Integer delaySeconds = aggregateResult.retryDelaySeconds == null
      ? 60
      : Math.max(1, aggregateResult.retryDelaySeconds);
    return Math.max(1, (Integer) Math.ceil(delaySeconds / 60.0));
  }

  private String safeErrorSummary() {
    return String.isBlank(aggregateResult.errorSummary)
      ? ''
      : aggregateResult.errorSummary;
  }

  private static String retryJobName(String prefixValue) {
    String seed =
      String.valueOf(Datetime.now().getTime()) +
      ':' +
      Math.random();
    String suffix = EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(seed))
      )
      .substring(0, 10);
    return prefixValue + '_' + Datetime.now().getTime() + '_' + suffix;
  }
}
