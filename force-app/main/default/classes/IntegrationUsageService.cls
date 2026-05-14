public without sharing class IntegrationUsageService {
    private static final Integer EXPIRING_SOON_DAYS = 7;
    private static final List<String> PRODUCT_KEYS = new List<String>{
        'quickbooks', 'shopify', 'stripe', 'authorizenet', 'paypal', 'fedex', 'ups'
    };
    private static final Map<String, ProductInfo> PRODUCT_INFO_BY_KEY = new Map<String, ProductInfo>{
        'quickbooks' => new ProductInfo('quickbooks', 'QuickBooks', 'QuickBooks', 'QuickBooks_Is_Active__c', 'QuickBooks_End_Date__c'),
        'shopify' => new ProductInfo('shopify', 'Shopify', 'Shopify', 'Shopify_Is_Active__c', 'Shopify_End_Date__c'),
        'stripe' => new ProductInfo('stripe', 'Stripe', 'Stripe', 'Stripe_Active__c', 'Stripe_End_Date__c'),
        'authorizenet' => new ProductInfo('authorizenet', 'Authorize.Net', 'AuthorizeNet', 'AuthorizeNet_Active__c', 'AuthorizeNet_End_Date__c'),
        'paypal' => new ProductInfo('paypal', 'PayPal', 'PayPal', 'PayPal_Active__c', 'PayPal_EndDate__c'),
        'fedex' => new ProductInfo('fedex', 'FedEx', 'FedEx', 'FedEx_Active__c', 'FedEx_End_Date__c'),
        'ups' => new ProductInfo('ups', 'UPS', 'UPS', 'UPS_Active__c', 'UPS_End_Date__c')
    };

    private class ProductInfo {
        String key;
        String label;
        String configDeveloperName;
        String activeField;
        String endDateField;

        ProductInfo(String key, String label, String configDeveloperName, String activeField, String endDateField) {
            this.key = key;
            this.label = label;
            this.configDeveloperName = configDeveloperName;
            this.activeField = activeField;
            this.endDateField = endDateField;
        }
    }

    public class ReportingProductSummary {
        @AuraEnabled public String productKey;
        @AuraEnabled public String product;
        @AuraEnabled public Integer recordSyncCount;
        @AuraEnabled public Integer errorCount;
        @AuraEnabled public Integer endpointUsageCount;
        @AuraEnabled public Integer taskUsageCount;
        @AuraEnabled public Integer activeScheduleCount;
        @AuraEnabled public String subscriptionStatus;
        @AuraEnabled public Integer subscriptionDaysRemaining;
        @AuraEnabled public Datetime lastUpdatedAt;
        @AuraEnabled public Integer recordSyncLimit;
        @AuraEnabled public Integer endpointUsageLimit;
        @AuraEnabled public Integer taskUsageLimit;
        @AuraEnabled public Integer activeScheduleLimit;
    }

    public static void assertCanConsumeTask(String product, Integer units) {
        ProductInfo info = normalizeProduct(product);
        String productLabel = info != null ? info.label : product;

        Integer taskLimit = getTaskUsageLimit(info);
        if (taskLimit <= 0) {
            return;
        }

        Integer currentCount = 0;
        if (info != null) {
            List<Integration_Usage_Summary__c> rows = [
                SELECT Task_Usage_Count__c
                FROM Integration_Usage_Summary__c
                WHERE Product_Key__c = :info.key
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                currentCount = toInt(rows[0].Task_Usage_Count__c);
            }
        }

        if (currentCount + (units == null ? 1 : units) > taskLimit) {
            throw new AuraHandledException('Task limit reached for ' + productLabel + '. Please upgrade or renew your plan.');
        }
    }

    public static void recordSuccessfulRecordSync(String product, Integer count) {
        if (count == null || count <= 0) {
            return;
        }
        incrementMetric(product, count, 'Record_Sync_Count__c');
        incrementMetric(product, count, 'Task_Usage_Count__c');
    }

    public static void recordSuccessfulApiTask(String product) {
        incrementMetric(product, 1, 'Task_Usage_Count__c');
    }

    public static void recordSuccessfulPaymentTask(String product) {
        incrementMetric(product, 1, 'Task_Usage_Count__c');
    }

    public static void incrementRecordSync(String product, Integer count) {
        incrementMetric(product, count, 'Record_Sync_Count__c');
    }

    public static void incrementError(String product, Integer count) {
        incrementMetric(product, count, 'Error_Count__c');
    }

    public static void incrementEndpointUsage(String product, Integer count) {
        incrementMetric(product, count, 'Endpoint_Usage_Count__c');
    }

    public static void incrementTaskUsage(String product, Integer count) {
        incrementMetric(product, count, 'Task_Usage_Count__c');
    }

    public static void syncActiveScheduleCount() {
        try {
            Map<String, Integer> countsByKey = new Map<String, Integer>();
            for (String productKey : PRODUCT_KEYS) {
                countsByKey.put(productKey, 0);
            }

            for (AggregateResult result : [
                SELECT Integration_Type__c product, COUNT_DISTINCT(Logical_Job_Key__c) total
                FROM Scheduled_Integration_Job__c
                WHERE Status__c = 'Active'
                GROUP BY Integration_Type__c
            ]) {
                ProductInfo info = normalizeProduct((String) result.get('product'));
                if (info != null) {
                    countsByKey.put(info.key, aggregateInteger(result.get('total')));
                }
            }

            List<Integration_Usage_Summary__c> updates = new List<Integration_Usage_Summary__c>();
            Map<String, Integration_Usage_Summary__c> summaries = getOrCreateSummariesByKey();
            for (String productKey : PRODUCT_KEYS) {
                Integration_Usage_Summary__c summary = summaries.get(productKey);
                summary.Active_Schedule_Count__c = countsByKey.get(productKey);
                summary.Last_Updated_At__c = Datetime.now();
                updates.add(summary);
            }
            if (!updates.isEmpty()) {
                update updates;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'IntegrationUsageService.syncActiveScheduleCount exception: ' + e.getMessage());
        }
    }

    public static void refreshSubscriptionStatuses() {
        try {
            Map<String, Quickbridge_Config__mdt> configsByDeveloperName = new Map<String, Quickbridge_Config__mdt>();
            for (Quickbridge_Config__mdt config : [
                SELECT DeveloperName,
                    QuickBooks_Is_Active__c, QuickBooks_End_Date__c,
                    Shopify_Is_Active__c, Shopify_End_Date__c,
                    Stripe_Active__c, Stripe_End_Date__c,
                    AuthorizeNet_Active__c, AuthorizeNet_End_Date__c,
                    PayPal_Active__c, PayPal_EndDate__c,
                    FedEx_Active__c, FedEx_End_Date__c,
                    UPS_Active__c, UPS_End_Date__c
                FROM Quickbridge_Config__mdt
                WHERE DeveloperName IN ('QuickBooks', 'Shopify', 'Stripe', 'AuthorizeNet', 'PayPal', 'FedEx', 'UPS')
            ]) {
                configsByDeveloperName.put(config.DeveloperName, config);
            }

            List<Integration_Usage_Summary__c> updates = new List<Integration_Usage_Summary__c>();
            Map<String, Integration_Usage_Summary__c> summaries = getOrCreateSummariesByKey();
            for (String productKey : PRODUCT_KEYS) {
                ProductInfo info = PRODUCT_INFO_BY_KEY.get(productKey);
                Quickbridge_Config__mdt config = configsByDeveloperName.get(info.configDeveloperName);
                SubscriptionState state = deriveSubscriptionState(config, info);
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
            System.debug(LoggingLevel.ERROR, 'IntegrationUsageService.refreshSubscriptionStatuses exception: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<ReportingProductSummary> getReportingSummary() {
        syncActiveScheduleCount();
        refreshSubscriptionStatuses();

        Map<String, Integration_Usage_Summary__c> summaries = getOrCreateSummariesByKey();
        Map<String, Integration_Usage_Limit__mdt> limitsByProduct = new Map<String, Integration_Usage_Limit__mdt>();
        for (Integration_Usage_Limit__mdt limitRow : [
            SELECT Product__c, Record_Sync_Limit__c, Endpoint_Usage_Limit__c, Task_Usage_Limit__c, Active_Schedule_Limit__c, Is_Active__c
            FROM Integration_Usage_Limit__mdt
            WHERE Is_Active__c = true
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
            row.taskUsageCount = toInt(summary.Task_Usage_Count__c);
            row.activeScheduleCount = toInt(summary.Active_Schedule_Count__c);
            row.subscriptionStatus = String.isBlank(summary.Subscription_Status__c) ? 'Inactive' : summary.Subscription_Status__c;
            row.subscriptionDaysRemaining = toNullableInt(summary.Subscription_Days_Remaining__c);
            row.lastUpdatedAt = summary.Last_Updated_At__c;
            row.recordSyncLimit = limitRow == null ? 0 : toInt(limitRow.Record_Sync_Limit__c);
            row.endpointUsageLimit = limitRow == null ? 0 : toInt(limitRow.Endpoint_Usage_Limit__c);
            row.taskUsageLimit = limitRow == null ? 0 : toInt(limitRow.Task_Usage_Limit__c);
            row.activeScheduleLimit = limitRow == null ? 0 : toInt(limitRow.Active_Schedule_Limit__c);
            rows.add(row);
        }
        return rows;
    }

    private static Integer getTaskUsageLimit(ProductInfo info) {
        if (info == null) {
            return 0;
        }
        try {
            for (Integration_Usage_Limit__mdt row : [
                SELECT Task_Usage_Limit__c
                FROM Integration_Usage_Limit__mdt
                WHERE Product__c = :info.label
                AND Is_Active__c = true
                LIMIT 1
            ]) {
                return toInt(row.Task_Usage_Limit__c);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'IntegrationUsageService.getTaskUsageLimit exception: ' + e.getMessage());
        }
        return 0;
    }

    private static void incrementMetric(String product, Integer count, String fieldApiName) {
        if (count == null || count <= 0 || String.isBlank(fieldApiName)) {
            return;
        }

        try {
            ProductInfo info = normalizeProduct(product);
            if (info == null) {
                return;
            }

            Integration_Usage_Summary__c summary = getOrCreateSummary(info);
            Integer currentValue = toInt((Decimal) summary.get(fieldApiName));
            summary.put(fieldApiName, currentValue + count);
            summary.Last_Updated_At__c = Datetime.now();
            update summary;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'IntegrationUsageService.incrementMetric exception: ' + e.getMessage());
        }
    }

    private static Map<String, Integration_Usage_Summary__c> getOrCreateSummariesByKey() {
        Map<String, Integration_Usage_Summary__c> summariesByKey = new Map<String, Integration_Usage_Summary__c>();
        for (Integration_Usage_Summary__c summary : [
            SELECT Id, Product_Key__c, Product__c, Record_Sync_Count__c, Error_Count__c, Endpoint_Usage_Count__c,
                Task_Usage_Count__c, Active_Schedule_Count__c, Subscription_Status__c, Subscription_Days_Remaining__c, Last_Updated_At__c
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
                SELECT Id, Product_Key__c, Product__c, Record_Sync_Count__c, Error_Count__c, Endpoint_Usage_Count__c,
                    Task_Usage_Count__c, Active_Schedule_Count__c, Subscription_Status__c, Subscription_Days_Remaining__c, Last_Updated_At__c
                FROM Integration_Usage_Summary__c
                WHERE Product_Key__c IN :PRODUCT_KEYS
            ]) {
                summariesByKey.put(summary.Product_Key__c, summary);
            }
        }
        return summariesByKey;
    }

    private static Integration_Usage_Summary__c getOrCreateSummary(ProductInfo info) {
        List<Integration_Usage_Summary__c> rows = [
            SELECT Id, Product_Key__c, Product__c, Record_Sync_Count__c, Error_Count__c, Endpoint_Usage_Count__c,
                Task_Usage_Count__c, Active_Schedule_Count__c, Subscription_Status__c, Subscription_Days_Remaining__c, Last_Updated_At__c
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
            Task_Usage_Count__c = 0,
            Active_Schedule_Count__c = 0,
            Subscription_Status__c = 'Inactive',
            Last_Updated_At__c = Datetime.now()
        );
    }

    private class SubscriptionState {
        String status;
        Integer daysRemaining;
    }

    private static SubscriptionState deriveSubscriptionState(Quickbridge_Config__mdt config, ProductInfo info) {
        SubscriptionState state = new SubscriptionState();
        state.status = 'Inactive';
        state.daysRemaining = null;

        if (config == null) {
            return state;
        }

        Object activeValue = config.get(info.activeField);
        Boolean active = activeValue instanceof Boolean && (Boolean) activeValue;
        Object endDateValue = config.get(info.endDateField);
        Date endDate = endDateValue instanceof Date ? (Date) endDateValue : null;
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
        String normalized = product.toLowerCase().replaceAll('[^a-z0-9]', '');
        if (normalized == 'qbo' || normalized == 'quickbooksonline') {
            normalized = 'quickbooks';
        } else if (normalized == 'authnet' || normalized == 'authorizenet') {
            normalized = 'authorizenet';
        }
        return PRODUCT_INFO_BY_KEY.get(normalized);
    }

    private static Integer toInt(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    private static Integer toNullableInt(Decimal value) {
        return value == null ? null : value.intValue();
    }

    private static Integer aggregateInteger(Object value) {
        if (value == null) {
            return 0;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Long) {
            return ((Long) value).intValue();
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).intValue();
        }
        return Integer.valueOf(String.valueOf(value));
    }
}