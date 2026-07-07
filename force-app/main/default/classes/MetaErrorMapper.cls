public with sharing class MetaErrorMapper {
  public static String sanitize(String message) {
    return ErrorLogUtility.redactSensitive(message);
  }

  public static void logCalloutFailure(String methodName, String message, Integer statusCode, String externalReference) {
    ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
    context.gatewayName = 'Meta';
    context.classMethodName = methodName;
    context.errorCategory = 'Callout Failure';
    context.httpStatusCode = statusCode;
    context.externalReference = externalReference;
    context.errorMessage = sanitize(message);
    ErrorLogUtility.logError(context);
  }

  public static void logException(String methodName, Exception exceptionRecord) {
    ErrorLogUtility.logException('Meta', methodName, exceptionRecord, null, null);
  }

  public static String userMessage(Integer statusCode, String rawMessage) {
    String sanitized = sanitize(rawMessage);
    String normalized = String.isBlank(sanitized) ? '' : sanitized.toLowerCase();
    if (statusCode == 400 && normalized.contains('malformed')) {
      return 'Meta returned a malformed request error. Review webhook payload or field mapping format.';
    }
    if (statusCode == 400 && normalized.contains('field')) {
      return 'Meta field mapping failed. Review unmapped or invalid Lead Ads fields.';
    }
    if (statusCode == 401 || normalized.contains('access token')) {
      return 'Meta authentication failed. Check the configured credential reference and app permissions.';
    }
    if (statusCode == 403 || normalized.contains('permission')) {
      return 'Meta permission check failed. Confirm the app has access to the page, ad account, and requested scopes.';
    }
    if (statusCode == 404 || normalized.contains('deleted') || normalized.contains('unsupported get request')) {
      return 'Meta object was not found or has been deleted. Confirm the page, ad account, campaign, ad set, or ad still exists.';
    }
    if (statusCode == 429 || normalized.contains('rate')) {
      return 'Meta rate limit was reached. Retry later or reduce sync volume.';
    }
    if (statusCode != null && statusCode >= 500) {
      return String.isBlank(sanitized)
        ? 'Meta is temporarily unavailable. Retry the sync later.'
        : 'Meta is temporarily unavailable. ' + sanitized;
    }
    return String.isBlank(sanitized) ? 'Meta API request failed.' : sanitized;
  }
}