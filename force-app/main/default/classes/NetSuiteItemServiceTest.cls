@IsTest
private class NetSuiteItemServiceTest {
  @IsTest
  static void itemSyncUpsertsProductUsingNamespacedExternalId() {
    NetSuiteConfigService.setTestConfig(NetSuiteConfigService.testConfigured());
    Test.setMock(HttpCalloutMock.class, new ItemMock());

    Test.startTest();
    NetSuiteItemService.SyncSummary summary = NetSuiteItemService.syncItems(null, 50);
    Test.stopTest();

    System.assertEquals(1, summary.recordsProcessed);
    System.assertEquals(0, summary.recordsFailed);
    Product2 syncedProduct = [
      SELECT Name, ProductCode, Description, External_Id__c, IsActive
      FROM Product2
      WHERE External_Id__c = 'netsuite:2002'
      LIMIT 1
    ];
    System.assertEquals('Blue Widget', syncedProduct.Name);
    System.assertEquals('BW-2002', syncedProduct.ProductCode);
    System.assertEquals('Widget from NetSuite', syncedProduct.Description);
    System.assertEquals(true, syncedProduct.IsActive);
  }

  private class ItemMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"items":[{"id":"2002","itemid":"BW-2002","displayname":"Blue Widget","salesdescription":"Widget from NetSuite","isinactive":"F","lastmodifieddate":"2026-06-30T12:00:00Z"}],"hasMore":false}');
      return response;
    }
  }

}
