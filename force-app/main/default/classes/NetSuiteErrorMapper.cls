public with sharing class NetSuiteErrorMapper {
  public static String sanitize(String message) {
    return ErrorLogUtility.redactSensitive(message);
  }

  public static void logCalloutFailure(String methodName, String message, Integer statusCode, String externalReference) {
    ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
    context.gatewayName = 'NetSuite';
    context.classMethodName = methodName;
    context.errorCategory = 'Callout Failure';
    context.httpStatusCode = statusCode;
    context.externalReference = externalReference;
    context.errorMessage = sanitize(message);
    ErrorLogUtility.logError(context);
  }

  public static void logException(String methodName, Exception exceptionRecord) {
    ErrorLogUtility.logException('NetSuite', methodName, exceptionRecord, null, null);
  }

  public static String userMessage(Integer statusCode, String rawMessage) {
    String sanitized = sanitize(rawMessage);
    String normalized = String.isBlank(sanitized) ? '' : sanitized.toLowerCase();
    if (normalized.contains('missing customer') || normalized.contains('invalid entity')) {
      return 'NetSuite transaction is missing a customer. Sync or map the related Customer before retrying.';
    }
    if (normalized.contains('missing item') || normalized.contains('invalid item')) {
      return 'NetSuite transaction line is missing an item. Sync or map the related Item/Product before retrying.';
    }
    if (normalized.contains('subsidiary')) {
      return 'NetSuite rejected the subsidiary value. Check the default subsidiary and transaction mapping.';
    }
    if (normalized.contains('location')) {
      return 'NetSuite rejected the location value. Check the default location or fulfillment location mapping.';
    }
    if (normalized.contains('closed period') || normalized.contains('posting period')) {
      return 'NetSuite rejected the transaction because the accounting period is closed. Reopen the period or change the transaction date.';
    }
    if (normalized.contains('duplicate')) {
      return 'NetSuite rejected the record as a duplicate. Review the external ID and transaction number mapping before retrying.';
    }
    if (statusCode == 401) {
      return 'NetSuite authentication failed. Check the Named Credential and NetSuite integration role.';
    }
    if (statusCode == 403) {
      return 'NetSuite permission check failed. Confirm the integration role can use REST Web Services and SuiteQL.';
    }
    if (statusCode == 404) {
      return 'NetSuite endpoint or record was not found. Check the account ID and REST endpoint configuration.';
    }
    if (statusCode == 429) {
      return 'NetSuite rate or governance limit was reached. Retry later or reduce sync volume.';
    }
    if (statusCode != null && statusCode >= 500) {
      return 'NetSuite is temporarily unavailable. Retry the sync later.';
    }
    return String.isBlank(sanitized) ? 'NetSuite request failed.' : sanitized;
  }
}
