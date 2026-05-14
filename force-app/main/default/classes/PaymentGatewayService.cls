public with sharing class PaymentGatewayService {
    
    @AuraEnabled
    public static String verifyCredentialsAndGetGateways() {
        try {
            List<Quickbridge_Config__mdt> configs = [
                SELECT Company_Name__c, Username__c, Password__c 
                FROM Quickbridge_Config__mdt 
                WHERE Username__c != null AND Password__c != null AND Company_Name__c != null
                LIMIT 1
            ];
            
            if (configs.isEmpty()) {
                throw new AuraHandledException('No valid credentials found in QuickBridge Metadata.');
            }
            
            Quickbridge_Config__mdt config = configs[0];
            
            Map<String, String> requestBody = new Map<String, String>();
            requestBody.put('companyName', config.Company_Name__c != null ? config.Company_Name__c.trim() : '');
            requestBody.put('username', config.Username__c != null ? config.Username__c.trim() : '');
            requestBody.put('password', config.Password__c != null ? config.Password__c.trim() : '');
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Server_Org_API/services/apexrest/v1/validateClient/');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(requestBody));
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            logServerOrgFailureIfNeeded(
                'PaymentGatewayService.verifyCredentialsAndGetGateways',
                res
            );
            
            return res.getBody();
            
        } catch(Exception e) {
            ErrorLogUtility.logException(
                'QuickBridge',
                'PaymentGatewayService.verifyCredentialsAndGetGateways',
                e,
                null,
                null
            );
            throw new AuraHandledException('Connection Error: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String getActiveGatewaysForCheckout() {
        try {
            List<Quickbridge_Config__mdt> configs = [
                SELECT Company_Name__c, Username__c, Password__c 
                FROM Quickbridge_Config__mdt 
                WHERE Username__c != null AND Password__c != null AND Label = 'Default'
                LIMIT 1
            ];
            
            if (configs.isEmpty()) {
                throw new AuraHandledException('No valid credentials found in QuickBridge Metadata.');
            }
            
            Quickbridge_Config__mdt config = configs[0];
            
            Map<String, String> requestBody = new Map<String, String>();
            requestBody.put('companyName', config.Company_Name__c != null ? config.Company_Name__c.trim() : '');
            requestBody.put('username', config.Username__c != null ? config.Username__c.trim() : '');
            requestBody.put('password', config.Password__c != null ? config.Password__c.trim() : '');
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Server_Org_API/services/apexrest/v1/validateClient/');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(requestBody));
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            logServerOrgFailureIfNeeded(
                'PaymentGatewayService.getActiveGatewaysForCheckout',
                res
            );
            
            return res.getBody();
            
        } catch(Exception e) {
            ErrorLogUtility.logException(
                'QuickBridge',
                'PaymentGatewayService.getActiveGatewaysForCheckout',
                e,
                null,
                null
            );
            throw new AuraHandledException('Connection Error: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String recoverPin() {
        try {
            List<Quickbridge_Config__mdt> configs = [SELECT Username__c FROM Quickbridge_Config__mdt WHERE Username__c != null LIMIT 1];
            if (configs.isEmpty()) {
                throw new AuraHandledException('No Username found in metadata.');
            }
            
            Map<String, String> requestBody = new Map<String, String>();
            requestBody.put('username', configs[0].Username__c.trim());
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Server_Org_API/services/apexrest/v1/recoverPin/');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(requestBody));
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            logServerOrgFailureIfNeeded(
                'PaymentGatewayService.recoverPin',
                res
            );
            
            return res.getBody();
            
        } catch(Exception e) {
            ErrorLogUtility.logException(
                'QuickBridge',
                'PaymentGatewayService.recoverPin',
                e,
                null,
                null
            );
            throw new AuraHandledException('Connection Error: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Boolean isClientAuthorized(String gatewayName) { // QuickBooks, Shopify
        try {
            List<Quickbridge_Config__mdt> configs = [
                SELECT Company_Name__c, Username__c, Password__c 
                FROM Quickbridge_Config__mdt 
                WHERE Username__c != null AND Password__c != null AND Company_Name__c != null
                LIMIT 1
            ];
            
            if (configs.isEmpty()) {
                System.debug(gatewayName + ' Validation Failed: No valid credentials found in QuickBridge Metadata.');
                return false;
            }
            
            Quickbridge_Config__mdt config = configs[0];
            
            Map<String, String> requestBody = new Map<String, String>();
            requestBody.put('companyName', config.Company_Name__c.trim());
            requestBody.put('username', config.Username__c.trim());
            requestBody.put('password', config.Password__c.trim());
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Server_Org_API/services/apexrest/v1/validateClient/');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(requestBody));
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String status = (String) responseMap.get('status');
                
                if (status == 'Success') {
                    List<Object> activeGatewaysObj = (List<Object>) responseMap.get('activeGateways');
                    if (activeGatewaysObj != null) {
                        for (Object gatewayObj : activeGatewaysObj) {
                            String gateway = (String) gatewayObj;
                            if (gateway != null && gateway.equalsIgnoreCase(gatewayName)) {
                                return true;
                            }
                        }
                    }
                    System.debug(gatewayName + ' Validation Failed: ' + gatewayName + ' license is not active for this client.');
                    return false;
                } else {
                    System.debug('Server Org Validation Failed: ' + (String)responseMap.get('message'));
                    return false;
                }
            } else {
                System.debug('Server Org API call failed with status: ' + res.getStatusCode());
                logServerOrgFailureIfNeeded(
                    'PaymentGatewayService.isClientAuthorized',
                    res
                );
                return false;
            }
            
        } catch(Exception e) {
            System.debug('Exception in isClientAuthorized (' + gatewayName + '): ' + e.getMessage());
            ErrorLogUtility.logException(
                gatewayName,
                'PaymentGatewayService.isClientAuthorized',
                e,
                null,
                null
            );
            return false;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Error_Log__c> getRecentErrorLogs(String gatewayName) {
        return [SELECT Id, Name, Error_Message__c, CreatedDate, Class_Method_Name__c, Gateway_Name__c, Order_Id__c
            FROM Error_Log__c 
            WHERE Gateway_Name__c = :gatewayName 
            ORDER BY CreatedDate DESC 
            LIMIT 10];
    }

    private static void logServerOrgFailureIfNeeded(String classMethodName, HttpResponse response) {
        if (response == null || response.getStatusCode() < 300) {
            return;
        }
        ErrorLogUtility.logCalloutFailure(
            'QuickBridge',
            classMethodName,
            'Server Org API returned HTTP ' + response.getStatusCode() + ': ' + response.getBody(),
            response.getStatusCode(),
            null,
            null
        );
    }
}