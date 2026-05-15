public with sharing class CarrierIntegrationWorker {
    public static void process(Integration_Work_Item__c item) {
        String operation = normalize(item.Operation__c);
        if (operation == 'trackingsync' || operation == 'trackingupdate') {
            Database.executeBatch(new CarrierTrackingStatusBatch(), 10);
            return;
        }
        throw new CarrierIntegrationWorkerException('Unsupported carrier operation: ' + item.Operation__c);
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    public class CarrierIntegrationWorkerException extends Exception {}
}
