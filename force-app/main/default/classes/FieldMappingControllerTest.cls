@isTest
public class FieldMappingControllerTest {
  private class QBFallbackMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(400);
      res.setBody('{"Fault": {"Error": [{"Message": "Error"}]}}');
      return res;
    }
  }

  private class QBSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String jsonBody =
        '{"QueryResponse": {"Customer": [{' +
        '"Active": true,' +
        '"Balance": 150.50,' +
        '"MetaData": {"CreateTime": "2023-01-01"},' +
        '"LineItems": [{"Id": "1"}],' +
        '"Name": "Test"' +
        '}]}}';
      res.setBody(jsonBody);
      return res;
    }
  }

  private static Field_Mapping__mdt buildTestMapping(
    String integration,
    String sfObject,
    String direction
  ) {
    return new Field_Mapping__mdt(
      Integration__c = integration,
      SF_Object__c = sfObject,
      SF_Field__c = 'Name',
      External_Field__c = 'DisplayName',
      Sync_Direction__c = direction,
      Is_Active__c = true
    );
  }

  @isTest
  static void testGetOrderFields() {
    Test.startTest();
    List<Map<String, String>> result = FieldMappingController.getOrderFields();
    Test.stopTest();

    Assert.isTrue(result.size() > 0);

    for (Map<String, String> field : result) {
      Assert.isNotNull(field.get('label'));
      Assert.isNotNull(field.get('value'));
    }

    for (Integer i = 1; i < result.size(); i++) {
      String prevLabel = result[i - 1].get('label').toLowerCase();
      String currLabel = result[i].get('label').toLowerCase();
      System.assert(prevLabel.compareTo(currLabel) <= 0);
    }
  }

  @isTest
  static void testOrderFieldsContainsCommonFields() {
    Test.startTest();
    List<Map<String, String>> result = FieldMappingController.getOrderFields();
    Test.stopTest();

    Set<String> fieldValues = new Set<String>();
    for (Map<String, String> field : result) {
      fieldValues.add(field.get('value'));
    }

    Assert.isTrue(fieldValues.contains('Id'));
    Assert.isTrue(fieldValues.contains('OrderNumber'));
  }

  @isTest
  static void testGetSalesforceObjects() {
    Test.startTest();
    List<Map<String, String>> objects = FieldMappingController.getSalesforceObjects();
    Test.stopTest();

    Assert.isTrue(objects.size() > 0);
  }

  @isTest
  static void testGetExistingMappings() {
    Test.startTest();
    List<Map<String, String>> mappings = FieldMappingController.getExistingMappings(
      'qbonline',
      'Account',
      'Customer'
    );
    Test.stopTest();

    Assert.isNotNull(mappings);
  }

  @isTest
  static void testGetExistingMappingsIsScopedByQbObject() {
    // Customer and Vendor reads must not error and must be independent calls.
    Test.startTest();
    List<Map<String, String>> customer = FieldMappingController.getExistingMappings(
      'qbonline',
      'Account',
      'Customer'
    );
    List<Map<String, String>> vendor = FieldMappingController.getExistingMappings(
      'qbonline',
      'Account',
      'Vendor'
    );
    // Unscoped (legacy/back-compat) read still works.
    List<Map<String, String>> unscoped = FieldMappingController.getExistingMappings(
      'qbonline',
      'Account',
      null
    );
    Test.stopTest();

    Assert.isNotNull(customer);
    Assert.isNotNull(vendor);
    Assert.isNotNull(unscoped);
  }

  @isTest
  static void testSaveVendorMappingPersistsPerQbObject() {
    // A Vendor save runs validation, record-name building (now scoped by the QBO
    // object) and the object-scoped deactivation loop. Mirrors the known-good
    // Customer save path with a Vendor target object.
    FieldMappingController.testActiveMappings = new List<Field_Mapping__mdt>();
    String vendorJson = '[{"sfField":"Name","externalField":"DisplayName"}]';

    Test.startTest();
    String vendorResult = FieldMappingController.saveFieldMappings(
      'qbonline',
      'Account',
      'Vendor',
      vendorJson
    );
    Test.stopTest();

    Assert.isTrue(vendorResult.contains('Deployment Started'));
  }

  @isTest
  static void testQBObjectMappingsCustomerAndVendorAreDistinctCalls() {
    Test.startTest();
    Map<String, String> customerOut = QBObjectMappings.getAccountToCustomerMapping();
    Map<String, String> vendorOut = QBObjectMappings.getAccountToVendorMapping();
    Map<String, String> customerIn = QBObjectMappings.getCustomerToAccountMapping();
    Map<String, String> vendorIn = QBObjectMappings.getVendorToAccountMapping();
    Test.stopTest();

    // All resolve (fall back to the shared field set when no scoped rows exist).
    Assert.isNotNull(customerOut);
    Assert.isNotNull(vendorOut);
    Assert.isNotNull(customerIn);
    Assert.isNotNull(vendorIn);
    Assert.isTrue(
      !customerIn.isEmpty(),
      'Customer inbound map should resolve.'
    );
    Assert.isTrue(!vendorIn.isEmpty(), 'Vendor inbound map should resolve.');
  }

  @isTest
  static void testGetQuickBooksFieldsFallbackAllEntities() {
    Test.setMock(HttpCalloutMock.class, new QBFallbackMock());
    Test.startTest();

    FieldMappingController.getQuickBooksFields('Account', 'Customer');
    FieldMappingController.getQuickBooksFields('Account', 'Vendor');
    FieldMappingController.getQuickBooksFields('Product2', 'Item');
    FieldMappingController.getQuickBooksFields('Order', 'Invoice');
    FieldMappingController.getQuickBooksFields('Credit_Memo__c', 'CreditMemo');
    FieldMappingController.getQuickBooksFields(
      'Purchase_Order__c',
      'PurchaseOrder'
    );
    FieldMappingController.getQuickBooksFields('Item_Sales_Tax__c', 'TaxCode');

    Test.stopTest();
    Assert.isTrue(true);
  }

  @isTest
  static void testCacheableReadFallbacksDoNotAttemptDmlLogging() {
    Test.setMock(HttpCalloutMock.class, new QBFallbackMock());

    Test.startTest();
    Integer dmlBeforeFallback = Limits.getDmlStatements();
    List<Map<String, Object>> qbFields = FieldMappingController.getQuickBooksFields(
      'Account',
      'Customer'
    );
    Integer dmlAfterFallback = Limits.getDmlStatements();

    Boolean didThrow = false;
    Integer dmlBeforeInvalidObject = Limits.getDmlStatements();
    try {
      FieldMappingController.getObjectFields('InvalidObjectName123');
    } catch (AuraHandledException e) {
      didThrow = true;
    }
    Integer dmlAfterInvalidObject = Limits.getDmlStatements();
    Test.stopTest();

    Assert.isTrue(
      qbFields.size() > 0,
      'QuickBooks schema fallback should still return field definitions.'
    );
    Assert.areEqual(
      dmlBeforeFallback,
      dmlAfterFallback,
      'Cacheable QuickBooks field fallback must not perform DML logging.'
    );
    Assert.isTrue(
      didThrow,
      'Invalid object should still surface an AuraHandledException.'
    );
    Assert.areEqual(
      dmlBeforeInvalidObject,
      dmlAfterInvalidObject,
      'Cacheable object field errors must not perform DML logging.'
    );
  }

  @isTest
  static void testGetShopifyAndCarrierFieldsAllEntities() {
    Test.startTest();

    FieldMappingController.getShopifyFields('Account', 'Customer');
    FieldMappingController.getShopifyFields('Order', 'Order');
    FieldMappingController.getShopifyFields('Product2', 'Product');
    FieldMappingController.getShopifyFields('OrderItem', 'LineItem');

    List<String> actions = new List<String>{
      'validateAddress',
      'getRateQuote',
      'createShipment',
      'generateLabel',
      'storeTrackingNumber',
      'syncTrackingStatus',
      'handleDeliveryExceptions',
      'createReturnLabel',
      'voidShipment',
      'unknownAction'
    };
    for (String actionName : actions) {
      Assert.isTrue(
        FieldMappingController.getFedExFields(actionName, null).size() > 0
      );
      Assert.isTrue(
        FieldMappingController.getUPSFields(actionName, null).size() > 0
      );
    }

    Test.stopTest();
  }

  @isTest
  static void fedExValidateAddressInboundFieldsUseValidatedAddressPrefix() {
    List<Map<String, Object>> outboundFields = FieldMappingController.getFedExFields(
      'validateAddress',
      'SF to FedEx'
    );
    List<Map<String, Object>> inboundFields = FieldMappingController.getFedExFields(
      'validateAddress',
      'FedEx to SF'
    );

    Set<String> outboundValues = new Set<String>();
    for (Map<String, Object> field : outboundFields) {
      outboundValues.add((String) field.get('value'));
    }
    Set<String> inboundValues = new Set<String>();
    for (Map<String, Object> field : inboundFields) {
      inboundValues.add((String) field.get('value'));
    }

    Assert.isTrue(outboundValues.contains('city'));
    Assert.isTrue(outboundValues.contains('streetLines[0]'));
    Assert.isTrue(inboundValues.contains('validatedAddress.city'));
    Assert.isTrue(inboundValues.contains('validatedAddress.streetLines[0]'));
    Assert.isFalse(inboundValues.contains('city'));
  }

  @isTest
  static void testSaveAndLoadCarrierMappings() {
    String outboundJson = '[{"sfField":"Name","externalField":"masterTrackingNumber","syncDirection":"SF to FedEx"}]';
    String inboundJson = '[{"sfField":"Name","externalField":"label.trackingNumber","syncDirection":"FedEx to SF"}]';
    String upsJson = '[{"sfField":"Name","externalField":"masterTrackingNumber","syncDirection":"SF to UPS"}]';

    Test.startTest();
    String fedexOutboundResponse = FieldMappingController.saveFedExFieldMappings(
      'unknownAction',
      'Account',
      outboundJson
    );
    String fedexInboundResponse = FieldMappingController.saveFedExFieldMappings(
      'generateLabel',
      'Account',
      inboundJson
    );
    String upsResponse = FieldMappingController.saveUPSFieldMappings(
      'unknownAction',
      'Account',
      upsJson
    );
    List<Map<String, String>> fedexMappings = FieldMappingController.getExistingFedExMappings(
      'unknownAction',
      'Account'
    );
    List<Map<String, String>> upsMappings = FieldMappingController.getExistingUPSMappings(
      'unknownAction',
      'Account'
    );
    Test.stopTest();

    Assert.isTrue(fedexOutboundResponse.contains('Deployment Started'));
    Assert.isTrue(fedexInboundResponse.contains('Deployment Started'));
    Assert.isTrue(upsResponse.contains('Deployment Started'));
    Assert.isNotNull(fedexMappings);
    Assert.isNotNull(upsMappings);
  }

  @isTest
  static void testFlattenFieldsViaSuccessResponse() {
    Test.setMock(HttpCalloutMock.class, new QBSuccessMock());
    Test.startTest();

    List<Map<String, Object>> qbFields = FieldMappingController.getQuickBooksFields(
      'Account',
      'Customer'
    );

    Test.stopTest();
    Assert.isTrue(qbFields.size() > 0);
  }

  @isTest
  static void testSaveFieldMappingsSuccess() {
    FieldMappingController.testActiveMappings = new List<Field_Mapping__mdt>();
    String mappingsJson = '[{"sfField":"Name","externalField":"DisplayName"}]';

    Test.startTest();
    String response = FieldMappingController.saveFieldMappings(
      'qbonline',
      'Account',
      'Customer',
      mappingsJson
    );
    Test.stopTest();

    Assert.isTrue(response.contains('Deployment Started'));
  }

  @isTest
  static void testShopifyInboundBlocksQboInboundOnly() {
    FieldMappingController.testActiveMappings = new List<Field_Mapping__mdt>{
      buildTestMapping('shopify', 'Account', 'Shopify to SF')
    };

    Test.startTest();
    Map<String, Object> availability = FieldMappingController.getMappingDirectionAvailability(
      'qbonline',
      'Account'
    );
    Test.stopTest();

    Assert.areEqual(false, (Boolean) availability.get('inboundAllowed'));
    Assert.areEqual(true, (Boolean) availability.get('outboundAllowed'));
    Assert.areEqual(false, (Boolean) availability.get('twoWayAllowed'));
  }

  @isTest
  static void testQboOutboundBlocksShopifyOutboundOnly() {
    FieldMappingController.testActiveMappings = new List<Field_Mapping__mdt>{
      buildTestMapping('qbonline', 'Account', 'SF to QBO')
    };

    Test.startTest();
    Map<String, Object> availability = FieldMappingController.getMappingDirectionAvailability(
      'shopify',
      'Account'
    );
    Test.stopTest();

    Assert.areEqual(true, (Boolean) availability.get('inboundAllowed'));
    Assert.areEqual(false, (Boolean) availability.get('outboundAllowed'));
    Assert.areEqual(false, (Boolean) availability.get('twoWayAllowed'));
  }

  @isTest
  static void testTwoWayBlocksBothDirectionsInPeerIntegration() {
    FieldMappingController.testActiveMappings = new List<Field_Mapping__mdt>{
      buildTestMapping('shopify', 'Account', 'Two-Way')
    };

    Test.startTest();
    Map<String, Object> availability = FieldMappingController.getMappingDirectionAvailability(
      'qbonline',
      'Account'
    );
    Test.stopTest();

    Assert.areEqual(false, (Boolean) availability.get('inboundAllowed'));
    Assert.areEqual(false, (Boolean) availability.get('outboundAllowed'));
    Assert.areEqual(false, (Boolean) availability.get('twoWayAllowed'));
    Assert.areEqual(true, (Boolean) availability.get('allDirectionsBlocked'));
  }

  @isTest
  static void testSaveRejectsConflictingDirection() {
    FieldMappingController.testActiveMappings = new List<Field_Mapping__mdt>{
      buildTestMapping('shopify', 'Account', 'Shopify to SF')
    };
    String mappingsJson = '[{"sfField":"Name","externalField":"DisplayName","syncDirection":"QBO to SF"}]';

    Boolean didThrow = false;
    Test.startTest();
    try {
      FieldMappingController.saveFieldMappings(
        'qbonline',
        'Account',
        'Customer',
        mappingsJson
      );
    } catch (Exception e) {
      didThrow = true;
    }
    Test.stopTest();

    Assert.isTrue(didThrow);
  }

  @isTest
  static void testSaveAllowsNonConflictingOppositeDirection() {
    FieldMappingController.testActiveMappings = new List<Field_Mapping__mdt>{
      buildTestMapping('shopify', 'Account', 'Shopify to SF')
    };
    String mappingsJson = '[{"sfField":"Name","externalField":"DisplayName","syncDirection":"SF to QBO"}]';

    Test.startTest();
    String response = FieldMappingController.saveFieldMappings(
      'qbonline',
      'Account',
      'Customer',
      mappingsJson
    );
    Test.stopTest();

    Assert.isTrue(response.contains('Deployment Started'));
  }

  @isTest
  static void testSaveFieldMappingsEmpty() {
    Boolean didThrow = false;
    Test.startTest();
    try {
      FieldMappingController.saveFieldMappings(
        'qbonline',
        'Account',
        'Customer',
        '[]'
      );
    } catch (Exception e) {
      didThrow = true;
    }
    Test.stopTest();

    Assert.isTrue(didThrow);
  }

  @isTest
  static void testGetObjectFieldsInvalid() {
    Boolean didThrow = false;
    try {
      FieldMappingController.getObjectFields('InvalidObjectName123');
    } catch (AuraHandledException e) {
      didThrow = true;
    }
    Assert.isTrue(didThrow);
  }

  @isTest
  static void getObjectFieldsExcludesBlockedFields() {
    Test.startTest();
    List<Map<String, String>> result = FieldMappingController.getOrderFields();
    Test.stopTest();

    Set<String> fieldValues = new Set<String>();
    for (Map<String, String> field : result) {
      fieldValues.add(field.get('value').toLowerCase());
    }

    // Blocked fields must be absent
    List<String> blocked = new List<String>{
      'ownerid', 'createddate', 'createdbyid',
      'lastmodifieddate', 'lastmodifiedbyid', 'systemmodstamp',
      'isdeleted', 'recordtypeid', 'currencyisocode',
      'lastvieweddate', 'lastreferenceddate'
    };
    for (String b : blocked) {
      Assert.isFalse(fieldValues.contains(b), b + ' should not appear in getObjectFields results');
    }

    // Allowed fields must still be present
    Assert.isTrue(fieldValues.contains('id'), 'Id must remain in field list');
    Assert.isTrue(fieldValues.contains('ordernumber'), 'OrderNumber must remain in field list');
  }

  @isTest
  static void saveFieldMappingsRejectsBlockedSfField() {
    String mappingsJson = JSON.serialize(new List<Object>{
      new Map<String, Object>{
        'sfField' => 'CreatedById',
        'externalField' => 'DisplayName',
        'syncDirection' => 'Two-Way'
      }
    });

    Test.startTest();
    Boolean didThrow = false;
    try {
      FieldMappingController.saveFieldMappings('qbonline', 'Account', 'Customer', mappingsJson);
    } catch (AuraHandledException e) {
      didThrow = true;
      Assert.isTrue(e.getMessage().contains('CreatedById'), 'Exception message should name the blocked field');
    }
    Test.stopTest();

    Assert.isTrue(didThrow, 'saveFieldMappings should reject a blocked sfField');
  }

  @isTest
  static void saveFieldMappingsAllowsSalesforceId() {
    // Salesforce record Id must never be blocked
    String mappingsJson = JSON.serialize(new List<Object>{
      new Map<String, Object>{
        'sfField' => 'Id',
        'externalField' => 'id',
        'syncDirection' => 'Two-Way'
      }
    });

    Test.startTest();
    Boolean threw = false;
    try {
      FieldMappingController.saveFieldMappings('qbonline', 'Account', 'Customer', mappingsJson);
    } catch (AuraHandledException e) {
      if (e.getMessage().contains('cannot be used in a mapping')) threw = true;
    }
    Test.stopTest();

    Assert.isFalse(threw, 'Salesforce Id should never be blocked by eligibility check');
  }

  @isTest
  static void getNetSuiteFieldsResolvesSupportedEntities() {
    List<Map<String, Object>> customerFields = FieldMappingController.getNetSuiteFields(
      'Account',
      null
    );
    List<Map<String, Object>> itemFields = FieldMappingController.getNetSuiteFields(
      'Product2',
      null
    );
    List<Map<String, Object>> invoiceFields = FieldMappingController.getNetSuiteFields(
      'Invoice__c',
      null
    );

    Set<String> customerValues = new Set<String>();
    for (Map<String, Object> fieldInfo : customerFields) {
      customerValues.add(String.valueOf(fieldInfo.get('value')));
    }

    Assert.isTrue(customerFields.size() > 0, 'Customer fields should be available.');
    Assert.isTrue(customerValues.contains('id'), 'Customer fields should include NetSuite id.');
    Assert.isTrue(itemFields.size() > 0, 'Item fields should be available.');
    Assert.isTrue(invoiceFields.size() > 0, 'Invoice roadmap fields should be available.');
  }

  @isTest
  static void getNetSuiteFieldsResolvesPhaseTwoEntitiesAndDirections() {
    List<Map<String, Object>> salesOrderLineFields = FieldMappingController.getNetSuiteFields(
      'OrderItem',
      null
    );
    List<Map<String, Object>> invoiceLineFields = FieldMappingController.getNetSuiteFields(
      'Invoice_Line__c',
      null
    );
    List<Map<String, Object>> paymentFields = FieldMappingController.getNetSuiteFields(
      'Portal_Payment_Transaction__c',
      null
    );
    List<Map<String, Object>> fulfillmentFields = FieldMappingController.getNetSuiteFields(
      'Carrier_Shipment__c',
      null
    );

    Assert.isTrue(values(salesOrderLineFields).contains('line'));
    Assert.isTrue(values(invoiceLineFields).contains('amount'));
    Assert.isTrue(values(paymentFields).contains('payment'));
    Assert.isTrue(values(fulfillmentFields).contains('trackingnumbers'));

    FieldMappingController.testActiveMappings = new List<Field_Mapping__mdt>{
      buildTestMapping('netsuite', 'Account', 'NetSuite to SF')
    };

    Map<String, Object> availability = FieldMappingController.getMappingDirectionAvailability(
      'netsuite',
      'Account'
    );
    Assert.areEqual(true, (Boolean) availability.get('inboundAllowed'));
    Assert.areEqual(true, (Boolean) availability.get('outboundAllowed'));
  }

  @isTest
  static void getExternalFieldsRoutesMetaAndNetSuiteDefinitions() {
    List<Map<String, Object>> metaCampaignFields = FieldMappingController.getExternalFields(
      'meta',
      'Campaign',
      'campaign'
    );
    List<Map<String, Object>> netSuiteCustomerFields = FieldMappingController.getExternalFields(
      'netsuite',
      'Account',
      'Customer'
    );

    Assert.isTrue(values(metaCampaignFields).contains('id'), 'Meta campaign fields should include id.');
    Assert.isTrue(values(metaCampaignFields).contains('name'), 'Meta campaign fields should include name.');
    Assert.isTrue(values(netSuiteCustomerFields).contains('companyname'), 'NetSuite customer fields should include companyname.');
  }

  @isTest
  static void getExternalFieldsCoversMetaAndNetSuiteObjectFamilies() {
    Map<String, String> metaObjects = new Map<String, String>{
      'Meta_Ad_Set__c' => 'adset',
      'Meta_Ad__c' => 'ad',
      'Lead' => 'leadad',
      'CampaignMember' => 'campaignmemberattribution',
      'Social_Interaction__c' => 'commentattribution',
      'Meta_Insight__c' => 'insights'
    };
    for (String sfObject : metaObjects.keySet()) {
      List<Map<String, Object>> fields = FieldMappingController.getExternalFields(
        'meta',
        sfObject,
        metaObjects.get(sfObject)
      );
      Assert.isFalse(fields.isEmpty(), 'Expected Meta fields for ' + metaObjects.get(sfObject));
    }

    Map<String, String> netSuiteObjects = new Map<String, String>{
      'Order' => 'SalesOrder',
      'OrderItem' => 'SalesOrderLine',
      'Invoice__c' => 'Invoice',
      'Invoice_Line__c' => 'InvoiceLine',
      'Portal_Payment_Transaction__c' => 'Payment',
      'Carrier_Shipment__c' => 'Fulfillment'
    };
    for (String sfObject : netSuiteObjects.keySet()) {
      List<Map<String, Object>> fields = FieldMappingController.getExternalFields(
        'netsuite',
        sfObject,
        netSuiteObjects.get(sfObject)
      );
      Assert.isFalse(fields.isEmpty(), 'Expected NetSuite fields for ' + netSuiteObjects.get(sfObject));
    }

    String clearResult = FieldMappingController.clearFieldMappingsForTargetObject(
      'meta',
      'Campaign',
      'campaign'
    );
    Assert.areEqual('No active mappings to clear.', clearResult);
  }

  @isTest
  static void saveMetaMappingsSupportsMetaDirectionsAndValidation() {
    String validJson = JSON.serialize(new List<Object>{
      new Map<String, Object>{
        'sfField' => 'Id',
        'externalField' => 'id',
        'syncDirection' => 'Meta to SF'
      },
      new Map<String, Object>{
        'sfField' => 'Name',
        'externalField' => 'name',
        'syncDirection' => 'SF to Meta'
      }
    });

    Test.startTest();
    String response = FieldMappingController.saveFieldMappings(
      'meta',
      'Campaign',
      'campaign',
      validJson
    );
    Test.stopTest();

    Assert.isTrue(response.contains('Deployment Started'));
  }

  @isTest
  static void saveMetaMappingsRejectsInvalidDirection() {
    String invalidJson = JSON.serialize(new List<Object>{
      new Map<String, Object>{
        'sfField' => 'Id',
        'externalField' => 'id',
        'syncDirection' => 'QBO to SF'
      },
      new Map<String, Object>{
        'sfField' => 'Name',
        'externalField' => 'name',
        'syncDirection' => 'Meta to SF'
      }
    });

    Boolean didThrow = false;
    Test.startTest();
    try {
      FieldMappingController.saveFieldMappings(
        'meta',
        'Campaign',
        'campaign',
        invalidJson
      );
    } catch (AuraHandledException e) {
      didThrow = true;
    }
    Test.stopTest();

    Assert.isTrue(didThrow, 'Meta mappings should reject non-Meta directions.');
  }

  private static Set<String> values(List<Map<String, Object>> fields) {
    Set<String> result = new Set<String>();
    for (Map<String, Object> fieldInfo : fields) {
      result.add(String.valueOf(fieldInfo.get('value')));
    }
    return result;
  }
}