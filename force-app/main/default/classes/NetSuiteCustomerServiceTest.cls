@IsTest
private class NetSuiteCustomerServiceTest {
  @IsTest
  static void customerSyncUpsertsAccountAndContactUsingNamespacedExternalIds() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    Test.setMock(HttpCalloutMock.class, new CustomerMock());

    Test.startTest();
    NetSuiteCustomerService.SyncSummary summary = NetSuiteCustomerService.syncCustomers(null, 50);
    Test.stopTest();

    System.assertEquals(1, summary.recordsProcessed);
    System.assertEquals(0, summary.recordsFailed);
    Account syncedAccount = [
      SELECT Name, External_Id__c, Phone, BillingCity
      FROM Account
      WHERE External_Id__c = 'netsuite:1001'
      LIMIT 1
    ];
    System.assertEquals('Acme Industrial', syncedAccount.Name);
    System.assertEquals('555-0100', syncedAccount.Phone);
    System.assertEquals('Detroit', syncedAccount.BillingCity);

    Contact syncedContact = [
      SELECT FirstName, LastName, Email, External_Id__c, AccountId
      FROM Contact
      WHERE External_Id__c = 'netsuite:contact:1001'
      LIMIT 1
    ];
    System.assertEquals('Ava', syncedContact.FirstName);
    System.assertEquals('Buyer', syncedContact.LastName);
    System.assertEquals('ava@example.com', syncedContact.Email);
    System.assertEquals(syncedAccount.Id, syncedContact.AccountId);
  }

  private class CustomerMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"items":[{"id":"1001","entityid":"CUST-1001","companyname":"Acme Industrial","firstname":"Ava","lastname":"Buyer","email":"ava@example.com","phone":"555-0100","billcity":"Detroit","lastmodifieddate":"2026-06-30T12:00:00Z"}],"hasMore":false}');
      return response;
    }
  }

}
