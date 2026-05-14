@IsTest
private class IntegrationUsageServiceTest {
    @IsTest
    static void createsRowsAndIncrementsIntegerCounters() {
        Test.startTest();
        IntegrationUsageService.incrementEndpointUsage('qbo', 2);
        IntegrationUsageService.incrementError('Shopify', 1);
        IntegrationUsageService.incrementTaskUsage('fedex', 3);
        List<IntegrationUsageService.ReportingProductSummary> rows = IntegrationUsageService.getReportingSummary();
        Test.stopTest();

        System.assertEquals(7, rows.size(), 'A summary row should be returned for each supported product.');

        Map<String, IntegrationUsageService.ReportingProductSummary> byKey = new Map<String, IntegrationUsageService.ReportingProductSummary>();
        for (IntegrationUsageService.ReportingProductSummary row : rows) {
            byKey.put(row.productKey, row);
        }

        System.assertEquals(2, byKey.get('quickbooks').endpointUsageCount);
        System.assertEquals(1, byKey.get('shopify').errorCount);
        System.assertEquals(3, byKey.get('fedex').taskUsageCount);
        System.assertEquals(0, byKey.get('paypal').recordSyncCount);
    }

    @IsTest
    static void ignoresUnknownProductsAndNonPositiveCounts() {
        Test.startTest();
        IntegrationUsageService.incrementRecordSync('Unknown Gateway', 5);
        IntegrationUsageService.incrementRecordSync('QuickBooks', 0);
        List<IntegrationUsageService.ReportingProductSummary> rows = IntegrationUsageService.getReportingSummary();
        Test.stopTest();

        for (IntegrationUsageService.ReportingProductSummary row : rows) {
            if (row.productKey == 'quickbooks') {
                System.assertEquals(0, row.recordSyncCount);
            }
        }
    }

    @IsTest
    static void recordSuccessfulRecordSyncIncreasesBothCounters() {
        Test.startTest();
        IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', 3);
        Test.stopTest();

        Integration_Usage_Summary__c summary = [
            SELECT Record_Sync_Count__c, Task_Usage_Count__c
            FROM Integration_Usage_Summary__c
            WHERE Product_Key__c = 'quickbooks'
            LIMIT 1
        ];
        System.assertEquals(3, summary.Record_Sync_Count__c.intValue(), 'Record_Sync_Count__c should be incremented by count');
        System.assertEquals(3, summary.Task_Usage_Count__c.intValue(), 'Task_Usage_Count__c should be incremented by count');
    }

    @IsTest
    static void recordSuccessfulApiTaskIncrementsTaskCount() {
        Test.startTest();
        IntegrationUsageService.recordSuccessfulApiTask('fedex');
        IntegrationUsageService.recordSuccessfulApiTask('fedex');
        Test.stopTest();

        Integration_Usage_Summary__c summary = [
            SELECT Task_Usage_Count__c
            FROM Integration_Usage_Summary__c
            WHERE Product_Key__c = 'fedex'
            LIMIT 1
        ];
        System.assertEquals(2, summary.Task_Usage_Count__c.intValue(), 'Task_Usage_Count__c should reflect both task calls');
    }

    @IsTest
    static void recordSuccessfulPaymentTaskIncrementsTaskCount() {
        Test.startTest();
        IntegrationUsageService.recordSuccessfulPaymentTask('Stripe');
        Test.stopTest();

        Integration_Usage_Summary__c summary = [
            SELECT Task_Usage_Count__c
            FROM Integration_Usage_Summary__c
            WHERE Product_Key__c = 'stripe'
            LIMIT 1
        ];
        System.assertEquals(1, summary.Task_Usage_Count__c.intValue(), 'Task_Usage_Count__c should be 1 after one payment task');
    }

    @IsTest
    static void assertCanConsumeTaskAllowsUnknownProduct() {
        // An unknown product normalizes to null, limit lookup returns 0 (unlimited) — should not throw
        Test.startTest();
        Boolean threw = false;
        try {
            IntegrationUsageService.assertCanConsumeTask('UnknownProduct_XYZ', 1);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'assertCanConsumeTask for unknown product should not throw (treated as unlimited)');
    }

    @IsTest
    static void assertCanConsumeTaskIgnoresNullProduct() {
        Test.startTest();
        Boolean threw = false;
        try {
            IntegrationUsageService.assertCanConsumeTask(null, 1);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'assertCanConsumeTask with null product should not throw');
    }
}