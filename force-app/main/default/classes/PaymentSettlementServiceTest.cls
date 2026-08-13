@IsTest
private class PaymentSettlementServiceTest {
  private static Order createOrder() {
    Account accountRecord = new Account(Name = 'Settlement Account');
    insert accountRecord;
    Order orderRecord = new Order(
      AccountId = accountRecord.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert orderRecord;
    return orderRecord;
  }

  @IsTest
  static void approvedSettlementCreatesInvoiceAndUpdatesGateway() {
    Order orderRecord = createOrder();
    PaymentSettlementService.SettlementRequest request = new PaymentSettlementService.SettlementRequest();
    request.providerName = 'Stripe';
    request.sourceMethod = 'StripePaymentService.processPayment';
    request.orderId = orderRecord.Id;
    request.amount = 42.50;
    request.transactionId = 'pi_shared_settlement';

    Test.startTest();
    PaymentSettlementService.SettlementResult result = PaymentSettlementService.settleApprovedPayment(
      request
    );
    Test.stopTest();

    System.assertEquals(true, result.invoiceProcessed);
    System.assertEquals(true, result.orderGatewayUpdated);
    System.assertEquals(false, result.hasFailures());
    System.assertEquals(
      'Stripe',
      [SELECT Payment_Gateway__c FROM Order WHERE Id = :orderRecord.Id]
      .Payment_Gateway__c
    );
  }

  @IsTest
  static void postApprovalFailuresAreBoundedAndNeverThrown() {
    PaymentSettlementService.forcedFailureStages = new Set<String>{
      'invoice',
      'order'
    };
    PaymentSettlementService.SettlementRequest request = new PaymentSettlementService.SettlementRequest();
    request.providerName = 'Authorize.Net';
    request.sourceMethod = 'AuthorizeNetPaymentService.processOpaquePayment';
    request.orderId = createOrder().Id;
    request.amount = 25;
    request.transactionId = 'approved_transaction';

    Test.startTest();
    PaymentSettlementService.SettlementResult result = PaymentSettlementService.settleApprovedPayment(
      request
    );
    Test.stopTest();

    System.assertEquals(false, result.invoiceProcessed);
    System.assertEquals(false, result.orderGatewayUpdated);
    System.assertEquals(true, result.hasFailures());
    System.assert(result.errorSummary.length() <= 2000);
    System.assert(result.errorSummary.contains('Invoice creation'));
    System.assert(result.errorSummary.contains('Order gateway update'));
    PaymentSettlementService.forcedFailureStages.clear();
  }

  @IsTest
  static void nullRequestReturnsDiagnosticInsteadOfThrowing() {
    PaymentSettlementService.SettlementResult result = PaymentSettlementService.settleApprovedPayment(
      null
    );
    System.assertEquals(true, result.hasFailures());
  }

  @IsTest
  static void unknownProviderCannotClearOrderGateway() {
    Order orderRecord = createOrder();
    update new Order(Id = orderRecord.Id, Payment_Gateway__c = 'Stripe');
    PaymentSettlementService.SettlementRequest request = new PaymentSettlementService.SettlementRequest();
    request.providerName = 'Untrusted Gateway';
    request.sourceMethod = 'Injected.Method';
    request.orderId = orderRecord.Id;
    request.amount = 10;
    request.transactionId = 'untrusted';

    PaymentSettlementService.SettlementResult result = PaymentSettlementService.settleApprovedPayment(
      request
    );

    System.assertEquals(true, result.hasFailures());
    System.assertEquals(false, result.orderGatewayUpdated);
    System.assertEquals(
      'Stripe',
      [SELECT Payment_Gateway__c FROM Order WHERE Id = :orderRecord.Id]
      .Payment_Gateway__c
    );
  }
}