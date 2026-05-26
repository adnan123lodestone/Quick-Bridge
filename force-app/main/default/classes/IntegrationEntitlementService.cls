public with sharing class IntegrationEntitlementService {
  private static final String CHECKOUT_CACHE_KEY = 'checkout';
  private static final Integer DEFAULT_TTL_MINUTES = 15;

  public class EntitlementResult {
    public Boolean cacheHit;
    public Boolean active;
    public String responseBody;
    public List<String> activeGateways;
    public String message;
  }

  public static EntitlementResult getCheckoutEntitlement() {
    Integration_Entitlement__c cached = loadCache(CHECKOUT_CACHE_KEY);
    if (isFresh(cached)) {
      return fromCache(cached);
    }

    if (cached != null) {
      requestCheckoutRefresh();
      EntitlementResult cachedResult = fromCache(cached);
      cachedResult.cacheHit = true;
      if (
        cached.Status__c == 'Active' &&
        cached.Fail_Policy__c == 'Fail Open'
      ) {
        return cachedResult;
      }
      cachedResult.active = false;
      cachedResult.message = 'Checkout entitlement cache is stale and fail policy is closed.';
      return cachedResult;
    }

    requestCheckoutRefresh();
    EntitlementResult missing = new EntitlementResult();
    missing.cacheHit = false;
    missing.active = false;
    missing.activeGateways = new List<String>();
    missing.message = 'Checkout entitlement cache is missing.';
    return missing;
  }

  public static Boolean isGatewayAuthorized(String gatewayName) {
    EntitlementResult result = getCheckoutEntitlement();
    if (
      result == null ||
      result.active != true ||
      result.activeGateways == null ||
      String.isBlank(gatewayName)
    ) {
      return false;
    }
    String normalizedGateway = IntegrationConnectorRegistry.normalize(
      gatewayName
    );
    for (String gateway : result.activeGateways) {
      if (
        IntegrationConnectorRegistry.normalize(gateway) == normalizedGateway
      ) {
        return true;
      }
    }
    return false;
  }

  public static EntitlementResult refreshCheckoutEntitlement(
    String username,
    String password,
    Boolean useSuppliedCredentials
  ) {
    EntitlementResult result = new EntitlementResult();
    result.cacheHit = false;
    try {
      HttpResponse response = PaymentAdminService.callServerOrgValidation(
        username,
        password,
        useSuppliedCredentials == true
      );
      result.responseBody = response == null ? null : response.getBody();
      result.active =
        response != null &&
        response.getStatusCode() >= 200 &&
        response.getStatusCode() < 300 &&
        isSuccess(result.responseBody);
      result.activeGateways = parseGateways(result.responseBody);
      result.message = parseMessage(result.responseBody);
      writeCache(result, null);
      return result;
    } catch (Exception e) {
      result.active = false;
      result.message = e.getMessage();
      writeCache(result, e);
      if (useSuppliedCredentials == true) {
        throw e;
      }
      return result;
    }
  }

  public static EntitlementResult refreshCheckoutEntitlementForLogin(
    String username,
    String password
  ) {
    if (String.isBlank(username) || String.isBlank(password)) {
      throw new AuraHandledException('User ID and PIN are required.');
    }
    return refreshCheckoutEntitlement(username, password, true);
  }

  public static void requestCheckoutRefresh() {
    if (System.isBatch() || System.isFuture() || System.isQueueable()) {
      return;
    }
    try {
      System.enqueueJob(
        new IntegrationEntitlementRefreshJob(CHECKOUT_CACHE_KEY)
      );
    } catch (Exception ignored) {
    }
  }

  private static Integration_Entitlement__c loadCache(String cacheKey) {
    List<Integration_Entitlement__c> rows = [
      SELECT
        Id,
        Cache_Key__c,
        Product_Key__c,
        Status__c,
        Active_Gateways_JSON__c,
        Raw_Response__c,
        Last_Refreshed_At__c,
        Expires_At__c,
        TTL_Minutes__c,
        Refresh_Status__c,
        Fail_Policy__c,
        Last_Error__c
      FROM Integration_Entitlement__c
      WHERE Cache_Key__c = :cacheKey
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static Boolean isFresh(Integration_Entitlement__c cached) {
    return cached != null &&
      cached.Expires_At__c != null &&
      cached.Expires_At__c > System.now() &&
      String.isNotBlank(cached.Raw_Response__c);
  }

  private static EntitlementResult fromCache(
    Integration_Entitlement__c cached
  ) {
    EntitlementResult result = new EntitlementResult();
    result.cacheHit = true;
    result.active = cached.Status__c == 'Active';
    result.responseBody = cached.Raw_Response__c;
    result.activeGateways = parseGateways(cached.Raw_Response__c);
    result.message = parseMessage(cached.Raw_Response__c);
    return result;
  }

  private static void writeCache(
    EntitlementResult result,
    Exception exceptionRecord
  ) {
    try {
      Integration_Entitlement__c existing = loadCache(CHECKOUT_CACHE_KEY);
      String failPolicy = existing != null &&
        String.isNotBlank(existing.Fail_Policy__c)
        ? existing.Fail_Policy__c
        : defaultFailPolicy();
      Integration_Entitlement__c cacheRecord = new Integration_Entitlement__c(
        Cache_Key__c = CHECKOUT_CACHE_KEY,
        Name = 'Checkout Entitlement',
        Product_Key__c = 'checkout',
        Status__c = result != null &&
          result.active == true
          ? 'Active'
          : 'Inactive',
        Active_Gateways_JSON__c = result == null ||
          result.activeGateways == null
          ? null
          : JSON.serialize(result.activeGateways),
        Raw_Response__c = result == null ? null : result.responseBody,
        Last_Refreshed_At__c = System.now(),
        Expires_At__c = System.now().addMinutes(DEFAULT_TTL_MINUTES),
        TTL_Minutes__c = DEFAULT_TTL_MINUTES,
        Refresh_Status__c = exceptionRecord == null ? 'Success' : 'Failed',
        Fail_Policy__c = failPolicy,
        Last_Error__c = exceptionRecord == null
          ? null
          : exceptionRecord.getTypeName() + ': ' + exceptionRecord.getMessage()
      );
      upsert cacheRecord Cache_Key__c;
    } catch (Exception e) {
      ErrorLogUtility.logException(
        'QuickBridge',
        'IntegrationEntitlementService.writeCache',
        e,
        null,
        null
      );
    }
  }

  private static String defaultFailPolicy() {
    return 'Fail Closed';
  }

  private static Boolean isSuccess(String responseBody) {
    if (String.isBlank(responseBody)) {
      return false;
    }
    try {
      Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
        responseBody
      );
      return String.valueOf(responseMap.get('status')) == 'Success';
    } catch (Exception e) {
      return false;
    }
  }

  private static String parseMessage(String responseBody) {
    if (String.isBlank(responseBody)) {
      return null;
    }
    try {
      Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
        responseBody
      );
      return responseMap.get('message') == null
        ? null
        : String.valueOf(responseMap.get('message'));
    } catch (Exception e) {
      return null;
    }
  }

  private static List<String> parseGateways(String responseBody) {
    List<String> gateways = new List<String>();
    if (String.isBlank(responseBody)) {
      return gateways;
    }
    try {
      Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
        responseBody
      );
      Object activeGateways = responseMap.get('activeGateways');
      if (activeGateways instanceof List<Object>) {
        for (Object gateway : (List<Object>) activeGateways) {
          if (gateway != null) {
            gateways.add(String.valueOf(gateway));
          }
        }
      }
    } catch (Exception ignored) {
    }
    return gateways;
  }
}