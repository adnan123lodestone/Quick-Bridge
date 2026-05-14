global without sharing class PaymentMethodAdminDeployCallback implements Metadata.DeployCallback {
    global void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        if (result == null) {
            System.debug(LoggingLevel.ERROR, 'Payment method metadata deployment returned no result.');
            ErrorLogUtility.LogContext logContext = new ErrorLogUtility.LogContext();
            logContext.gatewayName = 'QuickBridge';
            logContext.classMethodName = 'PaymentMethodAdminDeployCallback.handleResult';
            logContext.errorMessage = 'Payment method metadata deployment returned no result.';
            logContext.errorCategory = 'Deployment Failure';
            ErrorLogUtility.logError(logContext);
            return;
        }

        System.debug(
            LoggingLevel.INFO,
            'Payment method metadata deployment finished with status ' +
            result.status +
            ' and id ' +
            result.id
        );

        if (result.details != null && result.details.componentFailures != null) {
            for (Metadata.DeployMessage failure : result.details.componentFailures) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Payment method deployment failure: ' + failure.fullName + ' => ' + failure.problem
                );
                ErrorLogUtility.LogContext logContext = new ErrorLogUtility.LogContext();
                logContext.gatewayName = 'QuickBridge';
                logContext.classMethodName = 'PaymentMethodAdminDeployCallback.handleResult';
                logContext.errorMessage = 'Payment method deployment failure: ' + failure.fullName + ' => ' + failure.problem;
                logContext.errorCategory = 'Deployment Failure';
                logContext.externalReference = failure.fullName;
                ErrorLogUtility.logError(logContext);
            }
        }
    }
}