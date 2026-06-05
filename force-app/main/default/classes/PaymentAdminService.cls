public with sharing class PaymentAdminService {
  @AuraEnabled
  public static String verifyCredentialsAndGetGateways(
    String username,
    String password
  ) {
    try {
      AdminLoginRateLimiter.checkAndIncrement(username);
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
        'PaymentAdminService.verifyCredentialsAndGetGateways',
        res
      );
      if (entitlement.active == true) {
        AdminLoginRateLimiter.clearOnSuccess(username);
      }
      return responseBody;
    } catch (Exception e) {
      ErrorLogUtility.logException(
        'QuickBridge',
        'PaymentAdminService.verifyCredentialsAndGetGateways',
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
      if (String.isBlank(username)) {
        throw new AuraHandledException(
          'Username is required to recover your PIN.'
        );
      }
      AdminLoginRateLimiter.checkAndIncrement(
        username,
        AdminLoginRateLimiter.PIN_RECOVERY_BUCKET
      );

      Map<String, String> requestBody = new Map<String, String>();
      requestBody.put('username', username.trim());

      HttpRequest req = new HttpRequest();
      req.setEndpoint(
        'callout:Server_Org_API/services/apexrest/v1/recoverPin/'
      );
      req.setMethod('POST');
      req.setHeader('Content-Type', 'application/json');
      req.setBody(JSON.serialize(requestBody));

      Http http = new Http();
      HttpResponse res = http.send(req);
      logServerOrgFailureIfNeeded('PaymentAdminService.recoverPin', res);
      if (
        res != null &&
        res.getStatusCode() >= 200 &&
        res.getStatusCode() < 300
      ) {
        AdminLoginRateLimiter.clearOnSuccess(
          username,
          AdminLoginRateLimiter.PIN_RECOVERY_BUCKET
        );
      }
      return res.getBody();
    } catch (Exception e) {
      ErrorLogUtility.logException(
        'QuickBridge',
        'PaymentAdminService.recoverPin',
        e,
        null,
        null
      );
      throw new AuraHandledException('Connection Error: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static String refreshLicenses(String sessionToken) {
    Quickbridge_Config__mdt config = Quickbridge_Config__mdt.getInstance(
      'Default'
    );
    if (config == null || String.isBlank(config.Username__c)) {
      return 'Error: Missing Server Org credentials.';
    }

    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Server_Org_API/services/apexrest/v1/getLicenses');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setBody(
      JSON.serialize(
        new Map<String, String>{
          'companyName' => config.Company_Name__c,
          'username' => config.Username__c,
          'password' => config.Password__c
        }
      )
    );
    HttpResponse res = new Http().send(req);

    if (res.getStatusCode() != 200) {
      return 'Error: HTTP ' + res.getStatusCode() + ' - ' + res.getBody();
    }

    Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
      res.getBody()
    );
    if (!'Success'.equals(response.get('status'))) {
      return 'Error from Server: ' + response.get('message');
    }

    List<Object> licenses = (List<Object>) response.get('licenses');
    if (licenses == null || licenses.isEmpty()) {
      return 'No active licenses found.';
    }

    for (Object licObj : licenses) {
      Map<String, Object> lic = (Map<String, Object>) licObj;
      String connectorKey = (String) lic.get('name');
      String startDateStr = (String) lic.get('startDate');
      String endDateStr = (String) lic.get('endDate');
      if (String.isBlank(connectorKey))
        continue;

      ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(
        connectorKey
      );
      if (descriptor == null)
        continue;

      String endField = descriptor.expiryField;
      String startField = deriveStartFieldKey(endField);

      // Always write both date fields — null/blank dates make the connector inactive per activation rule
      if (String.isNotBlank(endField)) {
        ConnectorConfigService.upsertNonSecretValue(
          connectorKey,
          endField,
          endDateStr != null ? endDateStr : ''
        );
      }
      if (String.isNotBlank(startField)) {
        ConnectorConfigService.upsertNonSecretValue(
          connectorKey,
          startField,
          startDateStr != null ? startDateStr : ''
        );
      }
    }

    return 'Success: Licenses refreshed.';
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
      'PaymentAdminService.callServerOrgValidation',
      res
    );
    return res;
  }

  private static void logServerOrgFailureIfNeeded(
    String classMethodName,
    HttpResponse response
  ) {
    if (response == null || response.getStatusCode() < 300)
      return;
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
      if (allowCompanyOnly == true)
        return null;
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
    if (String.isBlank(responseBody))
      return responseBody;
    Map<String, Object> responseMap;
    try {
      responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
    } catch (Exception e) {
      return responseBody;
    }
    if (String.valueOf(responseMap.get('status')) == 'Success') {
      Datetime expiresAt = System.now().addHours(2);
      QuickBridgeAdminSessionService.SessionCreateResult sessionResult = QuickBridgeAdminSessionService.createSession(
        username,
        expiresAt
      );
      responseMap.put('sessionToken', sessionResult.sessionToken);
      responseMap.put('sessionExpiresAt', sessionResult.sessionExpiresAt);
    }
    return JSON.serialize(responseMap);
  }

  private static String deriveStartFieldKey(String expiryFieldKey) {
    if (String.isBlank(expiryFieldKey))
      return null;
    if (expiryFieldKey.containsIgnoreCase('End_Date__c'))
      return expiryFieldKey.replaceAll('(?i)End_Date__c', 'Start_Date__c');
    if (expiryFieldKey.containsIgnoreCase('EndDate__c'))
      return expiryFieldKey.replaceAll('(?i)EndDate__c', 'StartDate__c');
    if (expiryFieldKey.containsIgnoreCase('end_date'))
      return expiryFieldKey.replaceAll('(?i)end_date', 'start_date');
    return null;
  }
}