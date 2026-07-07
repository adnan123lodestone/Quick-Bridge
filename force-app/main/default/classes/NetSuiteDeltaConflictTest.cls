@IsTest
private class NetSuiteDeltaConflictTest {
  @IsTest
  static void phaseOneCustomerSyncAdvancesLastSuccessfulSyncAt() {
    insertNetSuiteRuntimeConfig(new Map<String, String>{
      'enable_customer_sync' => 'true',
      'enable_item_sync' => 'true'
    });
    Test.setMock(HttpCalloutMock.class, new SuiteQLRowsMock(
      '{"items":[{"id":"1009","entityid":"CUST-1009","companyname":"Delta Customer","lastmodifieddate":"2026-07-01T12:34:56Z"}],"hasMore":false}'
    ));

    Test.startTest();
    NetSuiteCustomerService.SyncSummary summary = NetSuiteCustomerService.syncCustomers(null, 10);
    Test.stopTest();

    System.assertEquals(1, summary.recordsProcessed);
    Connector_Config_Value__c watermark = [
      SELECT Value__c
      FROM Connector_Config_Value__c
      WHERE Connector_Key__c = 'netsuite'
      AND Field_Key__c = 'last_successful_sync_at'
      LIMIT 1
    ];
    System.assert(watermark.Value__c.contains('2026-07-01 12:34:56'));
  }

  @IsTest
  static void failedTransactionSyncDoesNotAdvanceLastSuccessfulSyncAt() {
    insertNetSuiteRuntimeConfig(new Map<String, String>{
      'enable_sales_order_sync' => 'true'
    });
    Test.setMock(HttpCalloutMock.class, new SuiteQLRowsMock(
      '{"items":[{"id":"4309","tranid":"SO-4309","trandate":"2026-07-01","status":"Draft","lastmodifieddate":"2026-07-01T12:00:00Z"}],"hasMore":false}'
    ));

    Test.startTest();
    NetSuiteSalesOrderService.SyncSummary summary = NetSuiteSalesOrderService.syncSalesOrders(null, 10);
    Test.stopTest();

    System.assertEquals(0, summary.recordsProcessed);
    System.assertEquals(1, summary.recordsFailed);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Connector_Config_Value__c WHERE Connector_Key__c = 'netsuite' AND Field_Key__c = 'last_successful_sync_at']
    );
  }

  @IsTest
  static void inboundInvoiceConflictLogsNeedsReviewAndDoesNotOverwriteLocalChange() {
    insertNetSuiteRuntimeConfig(new Map<String, String>{
      'enable_invoice_sync' => 'true',
      'last_successful_sync_at' => '2026-07-01 00:00:00'
    });
    Invoice__c invoiceRecord = new Invoice__c(
      External_Id__c = 'netsuite:8802',
      Reference_number__c = 'LOCAL-INV',
      Amount__c = 10,
      Status__c = 'Draft'
    );
    insert invoiceRecord;
    invoiceRecord.Amount__c = 11;
    update invoiceRecord;

    Test.setMock(HttpCalloutMock.class, new SuiteQLRowsMock(
      '{"items":[{"id":"8802","tranid":"NS-INV","total":88.02,"status":"Open","lastmodifieddate":"2026-07-02T12:00:00Z"}],"hasMore":false}'
    ));

    Test.startTest();
    NetSuiteInvoiceService.SyncSummary summary = NetSuiteInvoiceService.syncInvoices(null, 10);
    Test.stopTest();

    System.assertEquals(0, summary.recordsProcessed);
    System.assertEquals(1, summary.recordsFailed);
    Invoice__c refreshed = [
      SELECT Reference_number__c, Amount__c, Status__c
      FROM Invoice__c
      WHERE Id = :invoiceRecord.Id
    ];
    System.assertEquals('LOCAL-INV', refreshed.Reference_number__c);
    System.assertEquals(11, refreshed.Amount__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Error_Log__c
        WHERE Gateway_Name__c = 'NetSuite'
        AND Error_Category__c = 'Needs Review'
        AND External_Reference__c = 'netsuite:8802'
      ]
    );
  }

  private static void insertNetSuiteRuntimeConfig(Map<String, String> overrides) {
    Connector_Instance__c instanceRecord = new Connector_Instance__c(
      Name = 'NetSuite',
      Connector_Key__c = 'netsuite',
      Connector_Label__c = 'NetSuite',
      Active__c = true,
      Environment__c = 'Sandbox',
      Entitlement_Status__c = 'Active',
      Health_Status__c = 'Unknown',
      Named_Credential__c = 'NetSuite_TBA'
    );
    insert instanceRecord;

    Map<String, String> values = new Map<String, String>{
      'account_id' => '123456_SB1',
      'suiteql_url' => '/services/rest/query/v1/suiteql',
      'auth_type' => 'TBA',
      'enable_customer_sync' => 'true',
      'enable_item_sync' => 'true',
      'enable_sales_order_sync' => 'false',
      'enable_invoice_sync' => 'false',
      'enable_payment_sync' => 'false',
      'enable_fulfillment_sync' => 'false',
      'polling_interval_minutes' => '60'
    };
    if (overrides != null) {
      values.putAll(overrides);
    }
    List<Connector_Config_Value__c> rows = new List<Connector_Config_Value__c>();
    for (String fieldKey : values.keySet()) {
      rows.add(new Connector_Config_Value__c(
        Name = 'netsuite:' + fieldKey,
        Connector_Instance__c = instanceRecord.Id,
        Connector_Key__c = 'netsuite',
        Field_Key__c = fieldKey,
        Value__c = values.get(fieldKey),
        Is_Secret_Reference__c = false
      ));
    }
    insert rows;
  }

  private class SuiteQLRowsMock implements HttpCalloutMock {
    private String body;

    SuiteQLRowsMock(String body) {
      this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody(body);
      return response;
    }
  }
}