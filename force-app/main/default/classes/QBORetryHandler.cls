public with sharing class QBORetryHandler implements RetryHandler {
    public String handle(Error_Log__c log) {
        return QBOErrorHandler.handle(log);
    }
}
