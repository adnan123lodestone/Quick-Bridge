public with sharing class PaymentGatewayService {
  @AuraEnabled
  public static String verifyCredentialsAndGetGateways(
    String username,
  String password
  ) {
    try {
      IntegrationEntitlementService.EntitlementResult entitlement = IntegrationEntitlementService.refreshCheckoutEntitlementForLogin(
        username,
      password
        );
      String responseBody = addSessionDetails(
        entitlement.responseBody,
      username
        );
      HttpResponse res = new HttpResponse();
      res.setStatusCode(entitlement.active == true ? 200 : 401);
      res.setBody(responseBody);
      logServerOrgFailureIfNeeded(
        'PaymentGatewayService.verifyCredentialsAndGetGateways',
      res
        );
      return responseBody;
    } catch (Exception e) {
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
  public static Boolean revokeAdminSession(String sessionToken) {
    return QuickBridgeAdminSessionService.revokeSession(sessionToken);
  }
  
  @AuraEnabled
  public static String recoverPin(String username) {
    try {
      String recoveryUsername = username;
      if (String.isBlank(recoveryUsername)) {
        List<Quickbridge_Config__mdt> configs = [
          SELECT Username__c
          FROM Quickbridge_Config__mdt
          WHERE Username__c != NULL
          LIMIT 1
        ];
        if (!configs.isEmpty()) {
          recoveryUsername = configs[0].Username__c;
        }
      }
      if (String.isBlank(recoveryUsername)) {
        throw new AuraHandledException('No Username found in metadata.');
      }
      
      Map<String, String> requestBody = new Map<String, String>();
      requestBody.put('username', recoveryUsername.trim());
      
      HttpRequest req = new HttpRequest();
      req.setEndpoint(
        'callout:Server_Org_API/services/apexrest/v1/recoverPin/'
        );
      req.setMethod('POST');
      req.setHeader('Content-Type', 'application/json');
      req.setBody(JSON.serialize(requestBody));
      
      Http http = new Http();
      HttpResponse res = http.send(req);
      logServerOrgFailureIfNeeded('PaymentGatewayService.recoverPin', res);
      
      return res.getBody();
    } catch (Exception e) {
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
  public static Boolean isClientAuthorized(String gatewayName) {
    // QuickBooks, Shopify
    try {
      return IntegrationEntitlementService.isGatewayAuthorized(gatewayName);
    } catch (Exception e) {
      System.debug(
        'Exception in isClientAuthorized (' +
        gatewayName +
        '): ' +
        e.getMessage()
        );
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
    return [
      SELECT
        Id,
        Name,
        Error_Message__c,
        CreatedDate,
        Class_Method_Name__c,
        Gateway_Name__c,
        Order_Id__c
      FROM Error_Log__c
      WHERE Gateway_Name__c = :gatewayName
      ORDER BY CreatedDate DESC
      LIMIT 10
    ];
  }
  
  private static void logServerOrgFailureIfNeeded(
    String classMethodName,
  HttpResponse response
  ) {
    if (response == null || response.getStatusCode() < 300) {
      return;
    }
    ErrorLogUtility.logCalloutFailure(
      'QuickBridge',
    classMethodName,
    'Server Org API returned HTTP ' +
      response.getStatusCode() +
      ': ' +
      response.getBody(),
    response.getStatusCode(),
    null,
    null
      );
  }
  
  public static HttpResponse callServerOrgValidation(
    String username,
  String password,
  Boolean useSuppliedCredentials
  ) {
    Quickbridge_Config__mdt config = loadServerOrgConfig(
      useSuppliedCredentials == true
      );
    
    Map<String, String> requestBody = new Map<String, String>();
    requestBody.put(
      'companyName',
    config != null &&
      config.Company_Name__c != null
      ? config.Company_Name__c.trim()
      : ''
      );
    requestBody.put(
      'username',
    useSuppliedCredentials == true
      ? username.trim()
      : config.Username__c.trim()
      );
    requestBody.put(
      'password',
    useSuppliedCredentials == true
      ? password.trim()
      : config.Password__c.trim()
      );
    
    HttpRequest req = new HttpRequest();
    req.setEndpoint(
      'callout:Server_Org_API/services/apexrest/v1/validateClient/'
      );
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setBody(JSON.serialize(requestBody));
    
    HttpResponse res = new Http().send(req);
    logServerOrgFailureIfNeeded(
      'PaymentGatewayService.callServerOrgValidation',
    res
      );
    return res;
  }
  
  private static Quickbridge_Config__mdt loadServerOrgConfig(
    Boolean allowCompanyOnly
  ) {
    List<Quickbridge_Config__mdt> configs;
    if (allowCompanyOnly == true) {
      configs = [
        SELECT Company_Name__c, Username__c, Password__c
        FROM Quickbridge_Config__mdt
        WHERE Company_Name__c != NULL
        LIMIT 1
      ];
    } else {
      configs = [
        SELECT Company_Name__c, Username__c, Password__c
        FROM Quickbridge_Config__mdt
        WHERE
          Username__c != NULL
          AND Password__c != NULL
          AND Company_Name__c != NULL
        LIMIT 1
      ];
    }
    if (configs.isEmpty()) {
      if (allowCompanyOnly == true) {
        return null;
      }
      throw new AuraHandledException(
        'No valid credentials found in QuickBridge Metadata.'
        );
    }
    return configs[0];
  }
  
  private static String addSessionDetails(
    String responseBody,
  String username
  ) {
    if (String.isBlank(responseBody)) {
      return responseBody;
    }
    Map<String, Object> responseMap;
    try {
      responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
    } catch (Exception e) {
      return responseBody;
    }
    if (String.valueOf(responseMap.get('status')) == 'Success') {
      Datetime expiresAt = System.now().addHours(8);
      QuickBridgeAdminSessionService.SessionCreateResult sessionResult = QuickBridgeAdminSessionService.createSession(
        username,
      expiresAt
        );
      responseMap.put('sessionToken', sessionResult.sessionToken);
      responseMap.put('sessionExpiresAt', sessionResult.sessionExpiresAt);
    }
    return JSON.serialize(responseMap);
  }
  
  @AuraEnabled
  public static String refreshLicenses(String sessionToken) {
    // QuickBridgeAdminSessionService.requireValidSession(sessionToken);
    
    // Get current credentials from Quickbridge_Config__mdt or session
    Quickbridge_Config__mdt config = Quickbridge_Config__mdt.getInstance('Default');
    if (config == null || String.isBlank(config.Username__c)) {
      return 'Error: Missing Server Org credentials.';
    }
    
    // Call Server Org /v1/getLicenses endpoint
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Server_Org_API/services/apexrest/v1/getLicenses');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setBody(JSON.serialize(new Map<String, String>{
      'companyName' => config.Company_Name__c,
      'username'    => config.Username__c,
      'password'    => config.Password__c
    }));
    HttpResponse res = new Http().send(req);
    
    if (res.getStatusCode() != 200) {
      return 'Error: HTTP ' + res.getStatusCode() + ' - ' + res.getBody();
    }
    
    Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    if (!'Success'.equals(response.get('status'))) {
      return 'Error from Server: ' + response.get('message');
    }
    
    List<Object> licenses = (List<Object>) response.get('licenses');
    if (licenses == null || licenses.isEmpty()) {
      return 'No active licenses found.';
    }
    
    // Update each gateway's start/end dates
    for (Object licObj : licenses) {
      Map<String, Object> lic = (Map<String, Object>) licObj;
      String connectorKey = (String) lic.get('name');      // e.g., 'stripe', 'qbo'
      Date startDate = Date.valueOf((String) lic.get('startDate'));
      Date endDate   = Date.valueOf((String) lic.get('endDate'));
      
      // Determine the correct field API names for this connector
      Map<String, String> startFieldByConnector = new Map<String, String>{
        'stripe' => 'Stripe_Start_Date__c',
        'qbo' => 'QuickBooks_Start_Date__c',
        'shopify' => 'Shopify_Start_Date__c',
        'authorizenet' => 'AuthorizeNet_Start_Date__c',
        'paypal' => 'PayPal_StartDate__c',
        'fedex' => 'FedEx_Start_Date__c',
        'ups' => 'UPS_Start_Date__c'
      };
      Map<String, String> endFieldByConnector = new Map<String, String>{
        'stripe' => 'Stripe_End_Date__c',
        'qbo' => 'QuickBooks_End_Date__c',
        'shopify' => 'Shopify_End_Date__c',
        'authorizenet' => 'AuthorizeNet_End_Date__c',
        'paypal' => 'PayPal_EndDate__c',
        'fedex' => 'FedEx_End_Date__c',       
        'ups' => 'UPS_End_Date__c'             
      };
      String startField = startFieldByConnector.get(connectorKey);
      String endField = endFieldByConnector.get(connectorKey);
      if (String.isNotBlank(startField)) {
        ConnectorConfigService.upsertNonSecretValue(connectorKey, startField, String.valueOf(startDate));
      }
      if (String.isNotBlank(endField)) {
        ConnectorConfigService.upsertNonSecretValue(connectorKey, endField, String.valueOf(endDate));
      }
    }
    
    return 'Success: Licenses refreshed.';
  }
}