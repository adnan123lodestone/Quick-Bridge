@IsTest
private class IntegrationUsageServiceTest {
  private static void setupSummaries() {
    List<Integration_Usage_Summary__c> summaries = new List<Integration_Usage_Summary__c>();
    for (IntegrationConnectorRegistry.ConnectorDescriptor connector : IntegrationConnectorRegistry.connectors()) {
      summaries.add(
        new Integration_Usage_Summary__c(
          Product_Key__c = connector.productKey,
          Product__c = connector.label,
          Record_Sync_Count__c = 0,
          Error_Count__c = 0,
          Endpoint_Usage_Count__c = 0,
          Subscription_Status__c = 'Active',
          Last_Updated_At__c = System.now()
        )
      );
    }
    if (!summaries.isEmpty()) {
      insert summaries;
    }
  }

  @IsTest
  static void supportedMetricsAggregateWithoutTaskAccounting() {
    setupSummaries();

    Test.startTest();
    IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', 3);
    IntegrationUsageService.incrementEndpointUsage('QuickBooks', 2);
    IntegrationUsageService.incrementError('QuickBooks', 1);
    Test.stopTest();

    Integration_Usage_Summary__c summary = [
      SELECT Record_Sync_Count__c, Endpoint_Usage_Count__c, Error_Count__c
      FROM Integration_Usage_Summary__c
      WHERE Product_Key__c = 'quickbooks'
      LIMIT 1
    ];
    System.assertEquals(3, summary.Record_Sync_Count__c);
    System.assertEquals(2, summary.Endpoint_Usage_Count__c);
    System.assertEquals(1, summary.Error_Count__c);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Integration_Usage_Event__c
        WHERE Summary_Field__c = 'Task_Usage_Count__c'
      ],
      'Successful record syncs must not create retired task-usage events.'
    );
  }

  @IsTest
  static void legacyTaskEventsAreRetiredWhileSupportedEventsAggregate() {
    setupSummaries();
    insert new List<Integration_Usage_Event__c>{
      new Integration_Usage_Event__c(
        Product_Key__c = 'quickbooks',
        Event_Type__c = 'Task Usage',
        Summary_Field__c = 'Task_Usage_Count__c',
        Count__c = 49,
        Occurred_At__c = System.now(),
        Processed__c = false,
        Processing_Status__c = 'Pending'
      ),
      new Integration_Usage_Event__c(
        Product_Key__c = 'quickbooks',
        Event_Type__c = 'Error',
        Summary_Field__c = 'Error_Count__c',
        Count__c = 2,
        Occurred_At__c = System.now(),
        Processed__c = false,
        Processing_Status__c = 'Pending'
      )
    };

    Test.startTest();
    IntegrationUsageAggregator.aggregatePendingEvents();
    Test.stopTest();

    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Integration_Usage_Event__c
        WHERE Processed__c = true AND Processing_Status__c = 'Processed'
      ]
    );
    System.assertEquals(
      2,
      [
        SELECT Error_Count__c
        FROM Integration_Usage_Summary__c
        WHERE Product_Key__c = 'quickbooks'
        LIMIT 1
      ].Error_Count__c,
      'Supported error usage must continue to aggregate.'
    );
  }

  @IsTest
  static void reportingRetainsSupportedMetricsAndSubscriptionState() {
    setupSummaries();
    IntegrationUsageService.incrementRecordSync('qbo', 4);

    Test.startTest();
    List<IntegrationUsageService.ReportingProductSummary> rows = IntegrationUsageService.getReportingSummary();
    Test.stopTest();

    IntegrationUsageService.ReportingProductSummary quickBooks;
    for (IntegrationUsageService.ReportingProductSummary row : rows) {
      if (row.productKey == 'quickbooks') {
        quickBooks = row;
        break;
      }
    }
    System.assertNotEquals(null, quickBooks);
    System.assertEquals(4, quickBooks.recordSyncCount);
    System.assertNotEquals(null, quickBooks.subscriptionStatus);
    System.assert(quickBooks.recordSyncLimit >= 0);
    System.assert(quickBooks.endpointUsageLimit >= 0);
  }

  @IsTest
  static void invalidMetricsAndProductsAreIgnored() {
    Test.startTest();
    IntegrationUsageService.incrementRecordSync('unknown-product', 3);
    IntegrationUsageService.incrementEndpointUsage(null, 1);
    IntegrationUsageService.incrementError('QuickBooks', 0);
    IntegrationUsageAggregator.aggregatePendingEvents();
    new IntegrationUsageAggregator().execute(null);
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM Integration_Usage_Event__c]);
  }

  @IsTest
  static void missingSummaryIsCreatedForSupportedMetric() {
    Test.startTest();
    IntegrationUsageService.incrementError('DHL', 1);
    Test.stopTest();

    Integration_Usage_Summary__c summary = [
      SELECT Error_Count__c
      FROM Integration_Usage_Summary__c
      WHERE Product_Key__c = 'dhl'
      LIMIT 1
    ];
    System.assertEquals(1, summary.Error_Count__c);
  }

  @IsTest
  static void staleEventsRecoverAndAggregateOnce() {
    setupSummaries();
    insert new Integration_Usage_Event__c(
      Product_Key__c = 'quickbooks',
      Event_Type__c = 'Endpoint Usage',
      Summary_Field__c = 'Endpoint_Usage_Count__c',
      Count__c = 5,
      Occurred_At__c = System.now().addHours(-2),
      Processed__c = false,
      Processing_Status__c = 'Processing',
      Processing_Token__c = 'stale-token',
      Processing_Started_At__c = System.now().addHours(-2)
    );

    Test.startTest();
    System.assertEquals(1, IntegrationUsageAggregator.recoverStaleProcessingEvents(60));
    IntegrationUsageAggregator.aggregatePendingEvents();
    IntegrationUsageAggregator.aggregatePendingEvents();
    Test.stopTest();

    System.assertEquals(
      5,
      [
        SELECT Endpoint_Usage_Count__c
        FROM Integration_Usage_Summary__c
        WHERE Product_Key__c = 'quickbooks'
        LIMIT 1
      ].Endpoint_Usage_Count__c
    );
  }
}
