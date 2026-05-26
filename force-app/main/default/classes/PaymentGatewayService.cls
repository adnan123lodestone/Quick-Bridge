public with sharing class PaymentGatewayService {

    @AuraEnabled
    public static String getActiveGatewaysForCheckout() {
        try {
            IntegrationEntitlementService.EntitlementResult entitlement = IntegrationEntitlementService.getCheckoutEntitlement();
            if (
                entitlement != null &&
                entitlement.active == true &&
                String.isNotBlank(entitlement.responseBody)
            ) {
                return entitlement.responseBody;
            }
            throw new AuraHandledException(
                String.isBlank(entitlement == null ? null : entitlement.message)
                ? 'No valid entitlement cache or credentials found.'
                : entitlement.message
            );
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBridge', 'PaymentGatewayService.getActiveGatewaysForCheckout', e, null, null);
            throw new AuraHandledException('Connection Error: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Boolean isClientAuthorized(String gatewayName) {
        try {
            return IntegrationEntitlementService.isGatewayAuthorized(gatewayName);
        } catch (Exception e) {
            System.debug('Exception in isClientAuthorized (' + gatewayName + '): ' + e.getMessage());
            ErrorLogUtility.logException(gatewayName, 'PaymentGatewayService.isClientAuthorized', e, null, null);
            return false;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Error_Log__c> getRecentErrorLogs(String gatewayName) {
        return [
            SELECT Id, Name, Error_Message__c, CreatedDate, Class_Method_Name__c, Gateway_Name__c, Order_Id__c
            FROM Error_Log__c
            WHERE Gateway_Name__c = :gatewayName
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
    }
}