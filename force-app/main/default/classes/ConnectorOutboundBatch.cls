public without sharing class ConnectorOutboundBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
  private static final Integer MAX_RETRY_ATTEMPTS = 5;

  private ConnectorExecutionRequest request;
  private ConnectorExecutionResult aggregateResult;

  public ConnectorOutboundBatch(ConnectorExecutionRequest request) {
    this.request = request;
    this.aggregateResult = ConnectorExecutionResult.success();
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    try {
      request = request == null ? null : request.normalizedCopy();
      if (request == null) {
        throw new IllegalArgumentException(
          'Connector execution request is required.'
        );
      }
      request.validate();
      Boolean leaseAccepted = ConnectorScheduleService.markRunning(
        request.scheduleId,
        request.leaseToken,
        context == null ? null : context.getJobId()
      );
      if (request.scheduleId != null && !leaseAccepted) {
        throw new IllegalArgumentException(
          'Connector outbound execution no longer owns the schedule lease.'
        );
      }
      return ConnectorExecutionService.buildQueryLocator(
        request,
        new Set<String>{ 'Id' }
      );
    } catch (Exception exceptionValue) {
      aggregateResult = ConnectorExecutionResult.failed(
        exceptionValue.getMessage(),
        false,
        null
      );
      return Database.getQueryLocator('SELECT Id FROM Account WHERE Id = NULL');
    }
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    if (scope == null || scope.isEmpty() || aggregateResult.hasFailures()) {
      return;
    }
    try {
      aggregateResult.mergeFrom(
        ConnectorExecutionService.executeOutboundScope(request, scope)
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
          'Connector outbound execution no longer owns the schedule lease.',
          false,
          null
        )
      );
    }
  }

  public void finish(Database.BatchableContext context) {
    if (aggregateResult == null) {
      ConnectorScheduleService.completeFailure(
        request == null ? null : request.scheduleId,
        request == null ? null : request.leaseToken,
        'Connector outbound execution returned no result.'
      );
      return;
    }

    if (shouldRetry()) {
      Integer retryAttempt = request.retryAttempt == null
        ? 0
        : request.retryAttempt;
      if (retryAttempt >= MAX_RETRY_ATTEMPTS) {
        ConnectorScheduleService.completeFailure(
          request.scheduleId,
          request.leaseToken,
          'Connector outbound execution exceeded ' +
            MAX_RETRY_ATTEMPTS +
            ' retry attempts. ' +
            safeErrorSummary()
        );
        return;
      }

      if (!isSupportedRetryDelay()) {
        ConnectorScheduleService.completeFailure(
          request.scheduleId,
          request.leaseToken,
          'Connector outbound retry delay exceeds the supported 60-minute scheduling window. ' +
          safeErrorSummary()
        );
        return;
      }

      ConnectorExecutionRequest retryRequest = request.normalizedCopy();
      retryRequest.recordIds = new List<Id>(aggregateResult.retryRecordIds);
      retryRequest.retryAttempt = retryAttempt + 1;
      Integer delayMinutes = retryDelayMinutes();
      Id retryJobId = System.scheduleBatch(
        new ConnectorOutboundBatch(retryRequest),
        retryJobNameForRequest(),
        delayMinutes,
        normalizedScopeSize()
      );
      ConnectorScheduleService.markRunning(
        request.scheduleId,
        request.leaseToken,
        retryJobId,
        delayMinutes * 60
      );
      return;
    }

    ConnectorScheduleService.complete(
      request == null ? null : request.scheduleId,
      request == null ? null : request.leaseToken,
      aggregateResult
    );
  }

  private Boolean shouldRetry() {
    if (
      request == null ||
      aggregateResult.retryable != true ||
      aggregateResult.retryRecordIds == null ||
      aggregateResult.retryRecordIds.isEmpty()
    ) {
      return false;
    }
    return aggregateResult.failedCount != null &&
      aggregateResult.failedCount == aggregateResult.retryRecordIds.size();
  }

  private Integer retryDelayMinutes() {
    Integer delaySeconds = aggregateResult.retryDelaySeconds == null
      ? 60
      : Math.max(1, aggregateResult.retryDelaySeconds);
    return Math.max(1, (Integer) Math.ceil(delaySeconds / 60.0));
  }

  private Boolean isSupportedRetryDelay() {
    return aggregateResult.retryDelaySeconds == null ||
      aggregateResult.retryDelaySeconds <= 3600;
  }

  private Integer normalizedScopeSize() {
    if (request.scopeSize == null || request.scopeSize < 1) {
      return 1;
    }
    return Math.min(200, request.scopeSize);
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

  private String retryJobPrefix() {
    if (
      request != null &&
      request.connectorKey != null &&
      request.connectorKey.toLowerCase() == 'shopify'
    ) {
      String entity = String.isBlank(request.externalEntity)
        ? ''
        : request.externalEntity.toLowerCase();
      if (entity == 'customer') {
        return 'ShopifyCustomersOutboundBatch_RateLimit_Retry';
      }
      if (entity == 'product') {
        return 'ShopifyProductsOutboundBatch_RateLimit_Retry';
      }
      if (entity == 'order') {
        return 'ShopifyOrdersOutboundBatch_RateLimit_Retry';
      }
    }
    return 'ConnectorOutboundRetry';
  }

  private String retryJobNameForRequest() {
    String prefixValue = retryJobPrefix();
    return prefixValue.startsWith('Shopify')
      ? prefixValue + '_' + Datetime.now().getTime()
      : retryJobName(prefixValue);
  }
}
