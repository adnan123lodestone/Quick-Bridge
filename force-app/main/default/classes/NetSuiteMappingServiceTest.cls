@IsTest
private class NetSuiteMappingServiceTest {
  @IsTest
  static void outboundPayloadUsesActiveNetSuiteMappings() {
    NetSuiteMappingService.setTestMappings(new List<Field_Mapping__mdt>{
      mapping('Account', 'Customer', 'Name', 'companyname', 'SF to NetSuite'),
      mapping('Account', 'Customer', 'Phone', 'phone', 'SF to NetSuite')
    });

    Account accountRecord = new Account(Name = 'Mapped Customer', Phone = '555-0199');

    Map<String, Object> payload = NetSuiteRecordMapper.toNetSuitePayload(
      accountRecord,
      'Account',
      'Customer'
    );

    System.assertEquals('Mapped Customer', payload.get('companyname'));
    System.assertEquals('555-0199', payload.get('phone'));
    System.assertEquals(false, payload.containsKey('Name'));
  }

  @IsTest
  static void inboundRecordUsesNetSuiteMappingsAndExternalId() {
    NetSuiteMappingService.setTestMappings(new List<Field_Mapping__mdt>{
      mapping('Invoice__c', 'Invoice', 'Reference_number__c', 'tranid', 'NetSuite to SF'),
      mapping('Invoice__c', 'Invoice', 'Amount__c', 'total', 'NetSuite to SF'),
      mapping('Invoice__c', 'Invoice', 'Status__c', 'status', 'NetSuite to SF')
    });

    SObject record = NetSuiteRecordMapper.toSalesforceRecord(
      'Invoice__c',
      'Invoice',
      new Map<String, Object>{
        'id' => '3003',
        'tranid' => 'INV-3003',
        'total' => 125.50,
        'status' => 'Open'
      }
    );

    System.assertEquals('netsuite:3003', String.valueOf(record.get(Invoice__c.External_Id__c)));
    System.assertEquals('INV-3003', String.valueOf(record.get(Invoice__c.Reference_number__c)));
    System.assertEquals(Decimal.valueOf('125.50'), (Decimal) record.get(Invoice__c.Amount__c));
    System.assertEquals('Open', String.valueOf(record.get(Invoice__c.Status__c)));
  }

  @IsTest
  static void mappingDirectionFiltersOutboundAndInbound() {
    NetSuiteMappingService.setTestMappings(new List<Field_Mapping__mdt>{
      mapping('Product2', 'Item', 'Name', 'displayname', 'NetSuite to SF'),
      mapping('Product2', 'Item', 'ProductCode', 'itemid', 'SF to NetSuite'),
      mapping('Product2', 'Item', 'Description', 'salesdescription', 'Two-Way')
    });

    List<NetSuiteMappingService.MappingRule> outboundRules =
      NetSuiteMappingService.activeRules('Product2', 'Item', NetSuiteMappingService.DIRECTION_OUTBOUND);
    List<NetSuiteMappingService.MappingRule> inboundRules =
      NetSuiteMappingService.activeRules('Product2', 'Item', NetSuiteMappingService.DIRECTION_INBOUND);

    System.assertEquals(2, outboundRules.size(), 'Outbound should include outbound and two-way rules.');
    System.assertEquals(2, inboundRules.size(), 'Inbound should include inbound and two-way rules.');
    System.assertEquals('itemid', outboundRules[0].externalField);
    System.assertEquals('displayname', inboundRules[0].externalField);
  }

  @IsTest
  static void fallbackMapperHandlesStandardObjectsAndTypeCoercion() {
    NetSuiteMappingService.setTestMappings(new List<Field_Mapping__mdt>());

    SObject orderRecord = NetSuiteRecordMapper.toSalesforceRecord(
      'Order',
      'SalesOrder',
      new Map<String, Object>{
        'id' => '4201',
        'tranid' => 'SO-4201',
        'trandate' => '2026-07-01',
        'status' => 'Draft'
      }
    );
    Order mappedOrder = (Order) orderRecord;
    System.assertEquals('netsuite:4201', mappedOrder.External_Id__c);
    System.assertEquals(Date.newInstance(2026, 7, 1), mappedOrder.EffectiveDate);
    System.assertEquals('SO-4201', mappedOrder.OrderReferenceNumber);

    SObject productRecord = NetSuiteRecordMapper.toSalesforceRecord(
      'Product2',
      'Item',
      new Map<String, Object>{
        'id' => '8101',
        'itemid' => 'SKU-8101',
        'displayname' => 'Mapped Product',
        'salesdescription' => 'Suite item',
        'isinactive' => 'true'
      }
    );
    Product2 mappedProduct = (Product2) productRecord;
    System.assertEquals('netsuite:8101', mappedProduct.External_Id__c);
    System.assertEquals(true, mappedProduct.IsActive);

    Map<String, Object> payload = NetSuiteRecordMapper.toNetSuitePayload(
      new Product2(Name = 'Outbound Product', ProductCode = 'SKU-OUT', Description = 'Mapped', IsActive = true),
      'Product2',
      'Item'
    );
    System.assertEquals('SKU-OUT', payload.get('itemid'));
    System.assertEquals('Outbound Product', payload.get('displayname'));
  }

  @IsTest
  static void mapperRejectsInvalidInputs() {
    Boolean nullSourceThrew = false;
    try {
      NetSuiteRecordMapper.toNetSuitePayload(null, 'Account', 'Customer');
    } catch (NetSuiteRecordMapper.NetSuiteRecordMapperException expected) {
      nullSourceThrew = true;
      System.assert(expected.getMessage().contains('source record'));
    }
    System.assert(nullSourceThrew, 'Null source records should be rejected.');

    Boolean unsupportedObjectThrew = false;
    try {
      NetSuiteRecordMapper.toSalesforceRecord(
        'Does_Not_Exist__c',
        'Customer',
        new Map<String, Object>{ 'id' => '1' }
      );
    } catch (NetSuiteRecordMapper.NetSuiteRecordMapperException expected) {
      unsupportedObjectThrew = true;
      System.assert(expected.getMessage().contains('Unsupported Salesforce object'));
    }
    System.assert(unsupportedObjectThrew, 'Unsupported target objects should be rejected.');
  }

  private static Field_Mapping__mdt mapping(
    String sfObject,
    String externalObject,
    String sfField,
    String externalField,
    String direction
  ) {
    Field_Mapping__mdt row = new Field_Mapping__mdt();
    row.Integration__c = 'netsuite';
    row.SF_Object__c = sfObject;
    row.Target_Object_API_Name__c = externalObject;
    row.SF_Field__c = sfField;
    row.External_Field__c = externalField;
    row.Sync_Direction__c = direction;
    row.Is_Active__c = true;
    return row;
  }
}
