public without sharing class IntegrationUsageService {
  private static final Integer EXPIRING_SOON_DAYS = 7;
  private static final List<String> PRODUCT_KEYS = registryProductKeys();
  private static final Map<String, ProductInfo> PRODUCT_INFO_BY_KEY = registryProductInfo();

  private class ProductInfo {
    String key;
    String label;
    String configDeveloperName;
    String activeField;
    String endDateField;

    ProductInfo(
      String key,
      String label,
      String configDeveloperName,
      String activeField,
      String endDateField
    ) {
      this.key = key;
      this.label = label;
      this.configDeveloperName = configDeveloperName;
      this.activeField = activeField;
      this.endDateField = endDateField;
    }
  }

  public class ReportingProductSummary {
    @AuraEnabled
    public String productKey;
    @AuraEnabled
    public String product;
    @AuraEnabled
    public Integer recordSyncCount;
    @AuraEnabled
    public Integer errorCount;
    @AuraEnabled
    public Integer endpointUsageCount;
    @AuraEnabled
    public String subscriptionStatus;
    @AuraEnabled
    public Integer subscriptionDaysRemaining;
    @AuraEnabled
    public Datetime lastUpdatedAt;
    @AuraEnabled
    public Integer recordSyncLimit;
    @AuraEnabled
    public Integer endpointUsageLimit;
  }

  public static void recordSuccessfulRecordSync(String product, Integer count) {
    if (count == null || count <= 0) {
      return;
    }
    incrementMetric(product, count, 'Record_Sync_Count__c');
  }

  public static void incrementRecordSync(String product, Integer count) {
    incrementMetric(product, count, 'Record_Sync_Count__c');
  }

  public static void incrementError(String product, Integer count) {
    incrementMetric(product, count, 'Error_Count__c');
  }

  /**
   * Records one usage event for each successfully persisted Error Log while
   * using a single DML statement for the collection.
   */
  public static void incrementErrors(List<String> products) {
    if (products == null || products.isEmpty()) {
      return;
    }
    List<Integration_Usage_Event__c> events = new List<Integration_Usage_Event__c>();
    Datetime occurredAt = Datetime.now();
    for (String product : products) {
      ProductInfo info = normalizeProduct(product);
      if (info != null) {
        events.add(buildUsageEvent(info, 1, 'Error_Count__c', occurredAt));
      }
    }
    insertUsageEvents(events);
  }

  public static void incrementEndpointUsage(String product, Integer count) {
    incrementMetric(product, count, 'Endpoint_Usage_Count__c');
  }

  public static void refreshSubscriptionStatuses() {
    try {
      List<Integration_Usage_Summary__c> updates = new List<Integration_Usage_Summary__c>();
      Map<String, Integration_Usage_Summary__c> summaries = getOrCreateSummariesByKey();
      for (String productKey : PRODUCT_KEYS) {
        ProductInfo info = PRODUCT_INFO_BY_KEY.get(productKey);
        SubscriptionState state = deriveSubscriptionState(info);
        Integration_Usage_Summary__c summary = summaries.get(productKey);
        summary.Subscription_Status__c = state.status;
        summary.Subscription_Days_Remaining__c = state.daysRemaining;
        summary.Last_Updated_At__c = Datetime.now();
        updates.add(summary);
      }
      if (!updates.isEmpty()) {
        update updates;
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'IntegrationUsageService.refreshSubscriptionStatuses exception: ' +
        e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=false)
  public static List<ReportingProductSummary> getReportingSummary() {
    IntegrationUsageAggregator.aggregatePendingEvents();
    refreshSubscriptionStatuses();

    Map<String, Integration_Usage_Summary__c> summaries = getOrCreateSummariesByKey();
    Map<String, Integration_Usage_Limit__mdt> limitsByProduct = new Map<String, Integration_Usage_Limit__mdt>();
    for (Integration_Usage_Limit__mdt limitRow : [
      SELECT
        Product__c,
        Record_Sync_Limit__c,
        Endpoint_Usage_Limit__c,
        Is_Active__c
      FROM Integration_Usage_Limit__mdt
      WHERE Is_Active__c = TRUE
    ]) {
      ProductInfo info = normalizeProduct(limitRow.Product__c);
      if (info != null) {
        limitsByProduct.put(info.key, limitRow);
      }
    }

    List<ReportingProductSummary> rows = new List<ReportingProductSummary>();
    for (String productKey : PRODUCT_KEYS) {
      Integration_Usage_Summary__c summary = summaries.get(productKey);
      Integration_Usage_Limit__mdt limitRow = limitsByProduct.get(productKey);

      ReportingProductSummary row = new ReportingProductSummary();
      row.productKey = productKey;
      row.product = PRODUCT_INFO_BY_KEY.get(productKey).label;
      row.recordSyncCount = toInt(summary.Record_Sync_Count__c);
      row.errorCount = toInt(summary.Error_Count__c);
      row.endpointUsageCount = toInt(summary.Endpoint_Usage_Count__c);
      row.subscriptionStatus = String.isBlank(summary.Subscription_Status__c)
        ? 'Inactive'
        : summary.Subscription_Status__c;
      row.subscriptionDaysRemaining = toNullableInt(
        summary.Subscription_Days_Remaining__c
      );
      row.lastUpdatedAt = summary.Last_Updated_At__c;
      row.recordSyncLimit = limitRow == null
        ? 0
        : toInt(limitRow.Record_Sync_Limit__c);
      row.endpointUsageLimit = limitRow == null
        ? 0
        : toInt(limitRow.Endpoint_Usage_Limit__c);
      rows.add(row);
    }
    return rows;
  }

  private static void incrementMetric(
    String product,
    Integer count,
    String fieldApiName
  ) {
    if (count == null || count <= 0 || String.isBlank(fieldApiName)) {
      return;
    }

    ProductInfo info = normalizeProduct(product);
    if (info == null) {
      return;
    }
    insertUsageEvents(new List<Integration_Usage_Event__c>{
      buildUsageEvent(info, count, fieldApiName, Datetime.now())
    });
  }

  private static Integration_Usage_Event__c buildUsageEvent(
    ProductInfo info,
    Integer count,
    String fieldApiName,
    Datetime occurredAt
  ) {
    return new Integration_Usage_Event__c(
      Product_Key__c = info.key,
      Event_Type__c = fieldApiNameToEventType(fieldApiName),
      Summary_Field__c = fieldApiName,
      Count__c = count,
      Occurred_At__c = occurredAt,
      Processed__c = false,
      Processing_Status__c = 'Pending'
    );
  }

  private static void insertUsageEvents(List<Integration_Usage_Event__c> events) {
    if (events == null || events.isEmpty()) {
      return;
    }
    try {
      Database.insert(events, false);
      if (Test.isRunningTest()) {
        IntegrationUsageAggregator.aggregatePendingEvents();
      } else {
        IntegrationUsageAggregator.requestAggregation();
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'IntegrationUsageService.insertUsageEvents exception: ' + e.getMessage()
      );
    }
  }

  private static String fieldApiNameToEventType(String fieldApiName) {
    if (fieldApiName == 'Record_Sync_Count__c') {
      return 'Record Sync';
    }
    if (fieldApiName == 'Endpoint_Usage_Count__c') {
      return 'Endpoint Usage';
    }
    if (fieldApiName == 'Error_Count__c') {
      return 'Error';
    }
    return fieldApiName;
  }

  public static Map<String, Integration_Usage_Summary__c> getOrCreateSummariesByKeyForAggregation() {
    return getOrCreateSummariesByKey();
  }

  private static Map<String, Integration_Usage_Summary__c> getOrCreateSummariesByKey() {
    Map<String, Integration_Usage_Summary__c> summariesByKey = new Map<String, Integration_Usage_Summary__c>();
    for (Integration_Usage_Summary__c summary : [
      SELECT
        Id,
        Product_Key__c,
        Product__c,
        Record_Sync_Count__c,
        Error_Count__c,
        Endpoint_Usage_Count__c,
        Subscription_Status__c,
        Subscription_Days_Remaining__c,
        Last_Updated_At__c
      FROM Integration_Usage_Summary__c
      WHERE Product_Key__c IN :PRODUCT_KEYS
    ]) {
      summariesByKey.put(summary.Product_Key__c, summary);
    }

    List<Integration_Usage_Summary__c> missing = new List<Integration_Usage_Summary__c>();
    for (String productKey : PRODUCT_KEYS) {
      if (!summariesByKey.containsKey(productKey)) {
        missing.add(newSummary(PRODUCT_INFO_BY_KEY.get(productKey)));
      }
    }
    if (!missing.isEmpty()) {
      insert missing;
      for (Integration_Usage_Summary__c summary : [
        SELECT
          Id,
          Product_Key__c,
          Product__c,
          Record_Sync_Count__c,
          Error_Count__c,
          Endpoint_Usage_Count__c,
          Subscription_Status__c,
          Subscription_Days_Remaining__c,
          Last_Updated_At__c
        FROM Integration_Usage_Summary__c
        WHERE Product_Key__c IN :PRODUCT_KEYS
      ]) {
        summariesByKey.put(summary.Product_Key__c, summary);
      }
    }
    return summariesByKey;
  }

  private static Integration_Usage_Summary__c getOrCreateSummary(
    ProductInfo info
  ) {
    List<Integration_Usage_Summary__c> rows = [
      SELECT
        Id,
        Product_Key__c,
        Product__c,
        Record_Sync_Count__c,
        Error_Count__c,
        Endpoint_Usage_Count__c,
        Subscription_Status__c,
        Subscription_Days_Remaining__c,
        Last_Updated_At__c
      FROM Integration_Usage_Summary__c
      WHERE Product_Key__c = :info.key
      LIMIT 1
    ];
    if (!rows.isEmpty()) {
      return rows[0];
    }

    Integration_Usage_Summary__c summary = newSummary(info);
    insert summary;
    return summary;
  }

  private static Integration_Usage_Summary__c newSummary(ProductInfo info) {
    return new Integration_Usage_Summary__c(
      Product_Key__c = info.key,
      Product__c = info.label,
      Record_Sync_Count__c = 0,
      Error_Count__c = 0,
      Endpoint_Usage_Count__c = 0,
      Subscription_Status__c = 'Inactive',
      Last_Updated_At__c = Datetime.now()
    );
  }

  private class SubscriptionState {
    String status;
    Integer daysRemaining;
  }

  private static SubscriptionState deriveSubscriptionState(ProductInfo info) {
    SubscriptionState state = new SubscriptionState();
    state.status = 'Inactive';
    state.daysRemaining = null;

    if (info == null) {
      return state;
    }

    Boolean active = ConnectorConfigResolver.getBoolean(
      info.key,
      info.activeField
    );
    Date endDate = ConnectorConfigResolver.getDate(info.key, info.endDateField);
    if (endDate != null) {
      state.daysRemaining = Date.today().daysBetween(endDate);
    }

    if (!active) {
      return state;
    }
    if (endDate == null) {
      state.status = 'Active';
      return state;
    }
    if (state.daysRemaining < 0) {
      state.status = 'Expired';
    } else if (state.daysRemaining <= EXPIRING_SOON_DAYS) {
      state.status = 'Expiring Soon';
    } else {
      state.status = 'Active';
    }
    return state;
  }

  private static ProductInfo normalizeProduct(String product) {
    if (String.isBlank(product)) {
      return null;
    }
    String normalized = IntegrationConnectorRegistry.normalizeProductKey(
      product
    );
    if (String.isBlank(normalized)) {
      normalized = product.toLowerCase().replaceAll('[^a-z0-9]', '');
      if (normalized == 'qbo' || normalized == 'quickbooksonline') {
        normalized = 'quickbooks';
      } else if (normalized == 'authnet' || normalized == 'authorizenet') {
        normalized = 'authorizenet';
      }
    }
    return PRODUCT_INFO_BY_KEY.get(normalized);
  }

  private static List<String> registryProductKeys() {
    List<String> keys = IntegrationConnectorRegistry.productKeys();
    return keys.isEmpty()
      ? new List<String>{
          'quickbooks',
          'shopify',
          'stripe',
          'authorizenet',
          'paypal',
          'fedex',
          'ups'
        }
      : keys;
  }

  private static Map<String, ProductInfo> registryProductInfo() {
    Map<String, ProductInfo> result = new Map<String, ProductInfo>();
    for (
      IntegrationConnectorRegistry.ConnectorDescriptor connector : IntegrationConnectorRegistry.connectors()
    ) {
      result.put(
        connector.productKey,
        new ProductInfo(
          connector.productKey,
          connector.label,
          connector.configRecordName,
          connector.activeField,
          connector.expiryField
        )
      );
    }
    if (result.isEmpty()) {
      result.put(
        'quickbooks',
        new ProductInfo(
          'quickbooks',
          'QuickBooks',
          'QuickBooks',
          'QuickBooks_Is_Active__c',
          'QuickBooks_End_Date__c'
        )
      );
      result.put(
        'shopify',
        new ProductInfo(
          'shopify',
          'Shopify',
          'Shopify',
          'Shopify_Is_Active__c',
          'Shopify_End_Date__c'
        )
      );
      result.put(
        'stripe',
        new ProductInfo(
          'stripe',
          'Stripe',
          'Stripe',
          'Stripe_Active__c',
          'Stripe_End_Date__c'
        )
      );
      result.put(
        'authorizenet',
        new ProductInfo(
          'authorizenet',
          'Authorize.Net',
          'AuthorizeNet',
          'AuthorizeNet_Active__c',
          'AuthorizeNet_End_Date__c'
        )
      );
      result.put(
        'paypal',
        new ProductInfo(
          'paypal',
          'PayPal',
          'PayPal',
          'PayPal_Active__c',
          'PayPal_EndDate__c'
        )
      );
      result.put(
        'fedex',
        new ProductInfo(
          'fedex',
          'FedEx',
          'FedEx',
          'FedEx_Active__c',
          'FedEx_End_Date__c'
        )
      );
      result.put(
        'ups',
        new ProductInfo('ups', 'UPS', 'UPS', 'UPS_Active__c', 'UPS_End_Date__c')
      );
    }
    return result;
  }

  private static Integer toInt(Decimal value) {
    return value == null ? 0 : value.intValue();
  }

  private static Integer toNullableInt(Decimal value) {
    return value == null ? null : value.intValue();
  }
  
}