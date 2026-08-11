/**
 * Performs provider-independent work only after a payment provider has
 * returned an approved payment. Provider services retain ownership of their
 * callout sequence and response semantics; settlement failures are isolated so
 * an approved provider response is never converted into a decline.
 */
public inherited sharing class PaymentSettlementService {
  private static final Integer MAX_DIAGNOSTIC_LENGTH = 2000;

  public class SettlementRequest {
    public String providerName { get; set; }
    public String sourceMethod { get; set; }
    public String orderId { get; set; }
    public Id accountId { get; set; }
    public Decimal amount { get; set; }
    public String transactionId { get; set; }
  }

  public class SettlementResult {
    public Boolean usageRecorded { get; set; }
    public Boolean invoiceProcessed { get; set; }
    public Boolean orderGatewayUpdated { get; set; }
    public String errorSummary { get; set; }

    public SettlementResult() {
      usageRecorded = false;
      invoiceProcessed = false;
      orderGatewayUpdated = false;
    }

    public Boolean hasFailures() {
      return String.isNotBlank(errorSummary);
    }
  }

  @TestVisible
  private static Set<String> forcedFailureStages = new Set<String>();

  public static SettlementResult settleApprovedPayment(
    SettlementRequest request
  ) {
    SettlementResult result = new SettlementResult();
    if (request == null) {
      addDiagnostic(result, 'Payment settlement request is required.');
      return result;
    }
    String approvedProvider = canonicalProvider(request.providerName);
    if (approvedProvider == null) {
      addDiagnostic(
        result,
        'Payment settlement requires an approved payment provider.'
      );
      return result;
    }
    request.providerName = approvedProvider;
    request.sourceMethod = canonicalSourceMethod(approvedProvider);

    recordUsage(request, result);
    processInvoice(request, result);
    updateOrderGateway(request, result);
    return result;
  }

  private static void recordUsage(
    SettlementRequest request,
    SettlementResult result
  ) {
    try {
      failForTest('usage');
      IntegrationUsageService.recordSuccessfulPaymentTask(request.providerName);
      result.usageRecorded = true;
    } catch (Exception exceptionValue) {
      addDiagnostic(result, 'Usage accounting: ' + exceptionValue.getMessage());
      safeLogException(
        request,
        request.sourceMethod + '.usageAccounting',
        exceptionValue
      );
    }
  }

  private static void processInvoice(
    SettlementRequest request,
    SettlementResult result
  ) {
    try {
      failForTest('invoice');
      OrderContext orderContext = loadOrderContext(request.orderId);
      Decimal resolvedAmount = request.amount == null &&
        orderContext != null
        ? orderContext.totalAmount
        : request.amount;
      Id resolvedAccountId = request.accountId == null &&
        orderContext != null
        ? orderContext.accountId
        : request.accountId;
      if (resolvedAmount == null) {
        throw new PaymentSettlementException(
          'Invoice settlement requires a payment amount or a valid Order.'
        );
      }

      Map<String, Object> invoiceData = new Map<String, Object>{
        'Amount__c' => resolvedAmount,
        'Reference_number__c' => request.transactionId
      };
      if (String.isNotBlank(request.orderId)) {
        invoiceData.put('Order__c', request.orderId);
      }
      if (resolvedAccountId != null) {
        invoiceData.put('Related_Account__c', resolvedAccountId);
      }
      QuickBridgeRecordEngine.processIncomingInvoice(invoiceData);
      result.invoiceProcessed = true;
    } catch (Exception exceptionValue) {
      addDiagnostic(result, 'Invoice creation: ' + exceptionValue.getMessage());
      safeLogException(
        request,
        request.sourceMethod + '.invoiceCreation',
        exceptionValue
      );
    }
  }

  private static void updateOrderGateway(
    SettlementRequest request,
    SettlementResult result
  ) {
    if (String.isBlank(request.orderId)) {
      return;
    }
    try {
      failForTest('order');
      update new Order(
        Id = parseId(request.orderId),
        Payment_Gateway__c = request.providerName
      );
      result.orderGatewayUpdated = true;
    } catch (Exception exceptionValue) {
      addDiagnostic(
        result,
        'Order gateway update: ' + exceptionValue.getMessage()
      );
      safeLogDmlFailure(
        request,
        request.sourceMethod + '.updateOrderGateway',
        exceptionValue
      );
    }
  }

  private static OrderContext loadOrderContext(String orderId) {
    Id parsedOrderId = parseId(orderId);
    if (parsedOrderId == null) {
      return null;
    }
    Order orderRecord = [
      SELECT AccountId, TotalAmount
      FROM Order
      WHERE Id = :parsedOrderId
      LIMIT 1
    ];
    OrderContext result = new OrderContext();
    result.accountId = orderRecord.AccountId;
    result.totalAmount = orderRecord.TotalAmount;
    return result;
  }

  private static void safeLogException(
    SettlementRequest request,
    String methodName,
    Exception exceptionValue
  ) {
    try {
      ErrorLogUtility.logException(
        request.providerName,
        methodName,
        exceptionValue,
        'Order',
        parseId(request.orderId)
      );
    } catch (Exception ignored) {
      System.debug(
        LoggingLevel.ERROR,
        'PaymentSettlementService could not persist an exception log: ' +
        boundedMessage(ignored.getMessage())
      );
    }
  }

  private static void safeLogDmlFailure(
    SettlementRequest request,
    String methodName,
    Exception exceptionValue
  ) {
    try {
      Id orderId = parseId(request.orderId);
      ErrorLogUtility.logDmlFailure(
        request.providerName,
        methodName,
        'update',
        'Order',
        orderId,
        boundedMessage(
          exceptionValue.getTypeName() + ': ' + exceptionValue.getMessage()
        ),
        'Order',
        orderId
      );
    } catch (Exception ignored) {
      System.debug(
        LoggingLevel.ERROR,
        'PaymentSettlementService could not persist a DML log: ' +
        boundedMessage(ignored.getMessage())
      );
    }
  }

  private static String canonicalProvider(String providerName) {
    String normalized = String.isBlank(providerName)
      ? ''
      : providerName.toLowerCase().replaceAll('[^a-z0-9]', '');
    if (normalized == 'stripe') {
      return 'Stripe';
    }
    if (normalized == 'paypal') {
      return 'PayPal';
    }
    if (normalized == 'authorizenet' || normalized == 'authnet') {
      return 'Authorize.Net';
    }
    return null;
  }

  private static String canonicalSourceMethod(String providerName) {
    if (providerName == 'Stripe') {
      return 'StripePaymentService.processPayment';
    }
    if (providerName == 'PayPal') {
      return 'PayPalPaymentService.captureOrder';
    }
    return 'AuthorizeNetPaymentService.processOpaquePayment';
  }

  private static void addDiagnostic(SettlementResult result, String message) {
    String sanitized = boundedMessage(message);
    if (String.isBlank(sanitized)) {
      return;
    }
    result.errorSummary = boundedMessage(
      String.isBlank(result.errorSummary)
        ? sanitized
        : result.errorSummary + ' | ' + sanitized
    );
  }

  private static String boundedMessage(String message) {
    if (String.isBlank(message)) {
      return null;
    }
    String sanitized = message.replaceAll('[\\r\\n\\t]+', ' ').trim();
    sanitized = sanitized.replaceAll(
      '(?i)(authorization\\s*[:=]\\s*(?:bearer|basic)\\s+)[^ ,;]+',
      '$1[REDACTED]'
    );
    sanitized = sanitized.replaceAll(
      '(?i)("?(?:access[_-]?token|client[_-]?secret|password|api[_-]?key)"?\\s*[:=]\\s*"?)[^" ,;&}]+',
      '$1[REDACTED]'
    );
    return sanitized.length() <= MAX_DIAGNOSTIC_LENGTH
      ? sanitized
      : sanitized.substring(0, MAX_DIAGNOSTIC_LENGTH - 3) + '...';
  }

  private static Id parseId(String rawId) {
    if (String.isBlank(rawId)) {
      return null;
    }
    try {
      return (Id) rawId;
    } catch (Exception ignored) {
      return null;
    }
  }

  private static void failForTest(String stage) {
    if (Test.isRunningTest() && forcedFailureStages.contains(stage)) {
      throw new SettlementTestException(
        'Forced ' + stage + ' settlement failure.'
      );
    }
  }

  private class OrderContext {
    private Id accountId;
    private Decimal totalAmount;
  }

  private class SettlementTestException extends Exception {
  }

  private class PaymentSettlementException extends Exception {
  }
}
