/**
 * Compatibility strategy for provider implementations that already expose a
 * deterministic one-page inbound operation. New connector operations can
 * implement ConnectorExecutionService.OperationExecutor directly; this class
 * keeps the shared batch independent of provider-named Batchable classes while
 * the existing public entry points remain available.
 */
public inherited sharing class ConnectorInboundOperationExecutor implements ConnectorExecutionService.OperationExecutor {
  private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{
    408,
    409,
    425,
    429,
    500,
    502,
    503,
    504
  };

  public ConnectorExecutionResult executeInboundPage(
    ConnectorExecutionRequest request
  ) {
    try {
      ConnectorOperationRegistry.OperationDefinition definition = ConnectorOperationRegistry.resolve(
        request
      );
      String entity = normalize(request.externalEntity);
      String connector = normalize(request.connectorKey);
      ConnectorExecutionResult result;

      if (
        connector == 'qbo' &&
        (entity == 'customer' ||
        entity == 'item' ||
        entity == 'vendor')
      ) {
        return executeQuickBooksPage(request, entity);
      }

      String safeCursor = safeCursor(request.cursor, definition);
      if (connector == 'shopify' && entity == 'customer') {
        ConnectorExecutionRequest safeRequest = request.normalizedCopy();
        safeRequest.cursor = safeCursor;
        result = ShopifyCustomersBatch.executeSharedPage(safeRequest);
      } else if (connector == 'shopify' && entity == 'product') {
        ConnectorExecutionRequest safeRequest = request.normalizedCopy();
        safeRequest.cursor = safeCursor;
        result = ShopifyProductsBatch.executeSharedPage(safeRequest);
      } else if (connector == 'shopify' && entity == 'order') {
        ConnectorExecutionRequest safeRequest = request.normalizedCopy();
        safeRequest.cursor = safeCursor;
        result = ShopifyOrdersBatch.executeSharedPage(safeRequest);
      } else if (entity == 'profile') {
        result = new KlaviyoProfilesBatch(safeCursor).executeSharedPage();
      } else if (entity == 'list') {
        result = new KlaviyoListsBatch(safeCursor).executeSharedPage();
      } else if (entity == 'event') {
        result = new KlaviyoEventsBatch(safeCursor).executeSharedPage();
      } else if (connector == 'klaviyo' && entity == 'campaignmember') {
        if (request.recordIds == null || request.recordIds.size() != 1) {
          throw new ConnectorInboundOperationExecutorException(
            'Klaviyo campaign member synchronization requires one Campaign record.'
          );
        }
        Id campaignId = request.recordIds[0];
        if (String.isBlank(safeCursor)) {
          Campaign campaignValue = [
            SELECT Profile_s_URL__c
            FROM Campaign
            WHERE Id = :campaignId
            LIMIT 1
          ];
          safeCursor = safeCursor(campaignValue.Profile_s_URL__c, definition);
        }
        result = new KlaviyoCampaignMembersBatch(campaignId, safeCursor)
          .executeSharedPage();
      } else {
        return ConnectorExecutionResult.failed(
          'The registered inbound operation is not implemented by the compatibility strategy.',
          false,
          null
        );
      }

      if (String.isNotBlank(result.nextCursor)) {
        result.nextCursor = safeCursor(result.nextCursor, definition);
      }
      return result;
    } catch (Exception exceptionValue) {
      IntegrationRetryPolicy.RetryDecision retryDecision = IntegrationRetryPolicy.classify(
        exceptionValue
      );
      return ConnectorExecutionResult.failed(
        exceptionValue.getMessage(),
        retryDecision.retryable,
        retryDecision.retryable == true &&
          retryDecision.retryAfterSeconds == null
          ? 60
          : retryDecision.retryAfterSeconds
      );
    }
  }

  private static ConnectorExecutionResult executeQuickBooksPage(
    ConnectorExecutionRequest request,
    String entity
  ) {
    Integer startPosition = 1;
    if (String.isNotBlank(request.cursor)) {
      String safeCursorValue = request.cursor.trim();
      if (!Pattern.matches('^[1-9][0-9]{0,8}$', safeCursorValue)) {
        throw new ConnectorInboundOperationExecutorException(
          'QuickBooks pagination cursor is invalid.'
        );
      }
      startPosition = Integer.valueOf(safeCursorValue);
    }

    Integer pageSize = 50;
    String syncDate = (request.sinceValue == null
        ? Datetime.now().addDays(-1)
        : request.sinceValue)
      .format('yyyy-MM-dd');
    String quickBooksEntity = entity == 'customer'
      ? 'Customer'
      : (entity == 'vendor' ? 'Vendor' : 'Item');
    List<String> payloads = QuickBooksBulkQueryService.serializeRecords(
      QuickBooksBulkQueryService.queryUpdatedSincePage(
        quickBooksEntity,
        syncDate,
        startPosition,
        pageSize
      )
    );

    if (!payloads.isEmpty()) {
      if (entity == 'customer') {
        return finalizeQuickBooksPage(
          new QBCustomerToAccountSyncBatch(syncDate)
            .executeSharedScope(payloads),
          payloads.size(),
          pageSize,
          startPosition
        );
      } else if (entity == 'vendor') {
        return finalizeQuickBooksPage(
          new QBVendorToAccountSyncBatch(syncDate).executeSharedScope(payloads),
          payloads.size(),
          pageSize,
          startPosition
        );
      } else {
        return finalizeQuickBooksPage(
          new QBItemToProductSyncBatch(syncDate).executeSharedScope(payloads),
          payloads.size(),
          pageSize,
          startPosition
        );
      }
    }

    ConnectorExecutionResult result = ConnectorExecutionResult.success();
    result.processedCount = payloads.size();
    result.nextCursor = payloads.size() == pageSize
      ? String.valueOf(startPosition + pageSize)
      : null;
    return result;
  }

  private static ConnectorExecutionResult finalizeQuickBooksPage(
    ConnectorExecutionResult result,
    Integer payloadCount,
    Integer pageSize,
    Integer startPosition
  ) {
    ConnectorExecutionResult safeResult = result == null
      ? ConnectorExecutionResult.failed(
          'QuickBooks inbound processing returned no execution result.',
          false,
          null
        )
      : result;
    safeResult.nextCursor = payloadCount == pageSize &&
      !safeResult.hasFailures()
      ? String.valueOf(startPosition + pageSize)
      : null;
    return safeResult;
  }

  public ConnectorExecutionResult executeOutboundScope(
    ConnectorExecutionRequest request,
    List<SObject> scope
  ) {
    return ConnectorExecutionResult.failed(
      'The inbound compatibility strategy does not support outbound execution.',
      false,
      null
    );
  }

  public ConnectorExecutionResult executeSingle(
    ConnectorExecutionRequest request
  ) {
    return ConnectorExecutionResult.failed(
      'The inbound compatibility strategy does not support single-record execution.',
      false,
      null
    );
  }

  @TestVisible
  public static Boolean isRetryableStatus(Integer statusCode) {
    return statusCode != null &&
      (RETRYABLE_STATUS_CODES.contains(statusCode) ||
      (statusCode >= 500 &&
      statusCode <= 599));
  }

  public static Boolean isRetryableException(Exception exceptionValue) {
    if (exceptionValue == null) {
      return false;
    }
    if (exceptionValue instanceof IntegrationRetryPolicy.StatusCodeException) {
      return isRetryableStatus(
        ((IntegrationRetryPolicy.StatusCodeException) exceptionValue).statusCode
      );
    }
    Integer statusCode = IntegrationRetryPolicy.httpStatusCodeFromMessage(
      exceptionValue.getMessage()
    );
    return isRetryableStatus(statusCode) ||
      IntegrationRetryPolicy.isRetryableMessage(exceptionValue.getMessage());
  }

  @TestVisible
  public static Integer retryAfterSeconds(HttpResponse response) {
    String value = response == null ? null : response.getHeader('Retry-After');
    if (
      String.isBlank(value) || !Pattern.matches('^[0-9]{1,10}$', value.trim())
    ) {
      return null;
    }
    try {
      return Math.min(86400, Integer.valueOf(value.trim()));
    } catch (Exception ignored) {
      return null;
    }
  }

  private static String safeCursor(
    String cursor,
    ConnectorOperationRegistry.OperationDefinition definition
  ) {
    if (String.isBlank(cursor)) {
      return null;
    }
    if (
      definition == null ||
      String.isBlank(definition.namedCredential) ||
      String.isBlank(definition.relativeEndpoint) ||
      String.isBlank(definition.approvedBaseUrl)
    ) {
      throw new ConnectorInboundOperationExecutorException(
        'The registered inbound operation is missing its approved endpoint boundary.'
      );
    }

    String candidate = cursor.trim();
    String lowerCandidate = candidate.toLowerCase();
    if (lowerCandidate.startsWith('https://')) {
      candidate = ConnectorHttpClient.safeRelativeNext(
        definition.approvedBaseUrl,
        candidate
      );
    } else if (
      lowerCandidate.startsWith('http://') ||
      lowerCandidate.startsWith('callout:') ||
      !candidate.startsWith('/')
    ) {
      throw new ConnectorInboundOperationExecutorException(
        'Connector pagination must remain inside the approved HTTPS API boundary.'
      );
    }

    // Reuse the shared client validation for path injection and control chars.
    ConnectorHttpClient.toNamedCredentialEndpoint(
      definition.namedCredential,
      candidate
    );
    String candidatePath = candidate.contains('?')
      ? candidate.substringBefore('?')
      : candidate;
    String approvedPath = definition.relativeEndpoint.contains('?')
      ? definition.relativeEndpoint.substringBefore('?')
      : definition.relativeEndpoint;
    if (
      candidatePath != approvedPath &&
      !candidatePath.startsWith(approvedPath + '/')
    ) {
      throw new ConnectorInboundOperationExecutorException(
        'Connector pagination changed the registered operation path.'
      );
    }
    return candidate;
  }

  private static String normalize(String value) {
    return String.isBlank(value)
      ? ''
      : value.toLowerCase().replaceAll('[^a-z0-9]', '');
  }

  public class ConnectorInboundOperationExecutorException extends Exception {
  }
}