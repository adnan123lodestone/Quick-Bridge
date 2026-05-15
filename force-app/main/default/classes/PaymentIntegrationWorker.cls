public with sharing class PaymentIntegrationWorker {
    public static void process(Integration_Work_Item__c item) {
        throw new PaymentIntegrationWorkerException('Payment work is queued, but no direct payment mutation worker is implemented for operation: ' + item.Operation__c);
    }

    public class PaymentIntegrationWorkerException extends Exception {}
}
