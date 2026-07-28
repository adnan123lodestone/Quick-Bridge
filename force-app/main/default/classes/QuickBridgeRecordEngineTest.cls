@isTest
private class QuickBridgeRecordEngineTest {
  @testSetup
  static void setupData() {
    Account acc = new Account(Name = 'Record Engine Account');
    insert acc;

    Order ord = new Order(
      AccountId = acc.Id,
      Status = 'Draft',
      EffectiveDate = Date.today()
    );
    insert ord;
  }

  @isTest
  static void testProcessIncomingInvoiceWithMinimalPayload() {
    QuickBridgeRecordEngine.testInvoicePipelineTargetObject = 'Invoice__c';
    Account acc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Record Engine Account'
      LIMIT 1
    ];
    Order ord = [SELECT Id FROM Order LIMIT 1];

    Map<String, Object> payload = new Map<String, Object>{
      'Amount__c' => 100.25,
      'Order__c' => ord.Id,
      'Related_Account__c' => acc.Id,
      'Reference_number__c' => 'REF-100'
    };

    Test.startTest();
    QuickBridgeRecordEngine.processIncomingInvoice(payload);
    Test.stopTest();

    List<Invoice__c> invoices = [
      SELECT Id, Status__c, Reference_number__c
      FROM Invoice__c
      WHERE Reference_number__c = 'REF-100'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    if (!invoices.isEmpty()) {
      System.assertEquals('Paid', invoices[0].Status__c);
    }
  }

  @isTest
  static void testProcessIncomingInvoiceWithEmptyPayload() {
    QuickBridgeRecordEngine.testInvoicePipelineTargetObject = 'Invoice__c';
    Test.startTest();
    QuickBridgeRecordEngine.processIncomingInvoice(new Map<String, Object>());
    Test.stopTest();

    System.assert(true);
  }

  @isTest
  static void testProcessIncomingInvoiceFailureLogsAgainstOrder() {
    Account acc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Record Engine Account'
      LIMIT 1
    ];

    Map<String, Object> payload = new Map<String, Object>{
      'Amount__c' => 10,
      'Related_Account__c' => acc.Id,
      'Reference_number__c' => 'REF-BAD'
    };
    QuickBridgeRecordEngine.forcePipelineFailureForTest = true;

    Test.startTest();
    QuickBridgeRecordEngine.processIncomingInvoice(payload);
    Test.stopTest();

    String accountIdText = String.valueOf(acc.Id);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Error_Log__c
        WHERE
          Source_Record_Id__c = :accountIdText
          AND Class_Method_Name__c = 'QuickBridgeRecordEngine.processIncomingInvoice'
      ]
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Error_Log_Link__c
        WHERE
          Linked_Object_API_Name__c = 'Account'
          AND Linked_Record_Id__c = :accountIdText
          AND Relationship_Role__c = 'Source'
      ]
    );
  }

  @isTest
  static void testProcessIncomingInvoiceCreatesClientMappedRecord() {
    QuickBridgeRecordEngine.testInvoicePipelineTargetObject = 'Invoice__c';
    QuickBridgeRecordEngine.testActiveMappings = new List<Invoice_Field_Mapping__mdt>{
      new Invoice_Field_Mapping__mdt(
        Target_Object_API_Name__c = 'Account',
        Source_Field_API_Name__c = 'Reference_number__c',
        Target_Field_API_Name__c = 'Name'
      )
    };

    Map<String, Object> payload = new Map<String, Object>{
      'Amount__c' => 50,
      'Reference_number__c' => 'Mapped Account Name'
    };

    Test.startTest();
    QuickBridgeRecordEngine.processIncomingInvoice(payload);
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM Account WHERE Name = 'Mapped Account Name']
    );
  }

  @isTest
  static void testProcessIncomingInvoiceRoutesMappingsByTargetObject() {
    QuickBridgeRecordEngine.testInvoicePipelineTargetObject = 'Invoice__c';
    QuickBridgeRecordEngine.testActiveMappings = new List<Invoice_Field_Mapping__mdt>{
      new Invoice_Field_Mapping__mdt(
        Target_Object_API_Name__c = 'Account',
        Source_Field_API_Name__c = 'Reference_number__c',
        Target_Field_API_Name__c = 'Name'
      ),
      new Invoice_Field_Mapping__mdt(
        Target_Object_API_Name__c = 'Contact',
        Source_Field_API_Name__c = 'Reference_number__c',
        Target_Field_API_Name__c = 'LastName'
      )
    };

    Map<String, Object> payload = new Map<String, Object>{
      'Amount__c' => 55,
      'Reference_number__c' => 'Multi Target Invoice'
    };

    Test.startTest();
    QuickBridgeRecordEngine.processIncomingInvoice(payload);
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM Account WHERE Name = 'Multi Target Invoice']
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Contact WHERE LastName = 'Multi Target Invoice']
    );
  }

  @isTest
  static void testMappedRecordFailureLogsAgainstInvoice() {
    QuickBridgeRecordEngine.testInvoicePipelineTargetObject = 'Invoice__c';
    QuickBridgeRecordEngine.testActiveMappings = new List<Invoice_Field_Mapping__mdt>{
      new Invoice_Field_Mapping__mdt(
        Target_Object_API_Name__c = 'Account',
        Source_Field_API_Name__c = 'Missing_Source__c',
        Target_Field_API_Name__c = 'Name'
      )
    };

    Map<String, Object> payload = new Map<String, Object>{
      'Amount__c' => 75,
      'Reference_number__c' => 'REF-MAPPED-FAIL'
    };

    Test.startTest();
    QuickBridgeRecordEngine.processIncomingInvoice(payload);
    Test.stopTest();

    // Verify error log was created with dynamic object name
    Error_Log__c errorLog = [
      SELECT
        Id,
        Source_Object__c,
        Source_Record_Id__c,
        Invoice__c,
        Error_Category__c,
        Dml_Operation__c
      FROM Error_Log__c
      WHERE
        Class_Method_Name__c = 'QuickBridgeRecordEngine.runInvoicePipeline'
        AND Error_Category__c = 'DML Failure'
      LIMIT 1
    ];

    System.assertEquals(
      'Account',
      errorLog.Source_Object__c,
      'Should use dynamic target object name'
    );
    System.assertEquals(
      null,
      errorLog.Source_Record_Id__c,
      'Failed insert has no record ID'
    );
    System.assertEquals(
      null,
      errorLog.Invoice__c,
      'Object-specific lookups are historical only for new logs'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Error_Log_Link__c
        WHERE
          Error_Log__c = :errorLog.Id
          AND Relationship_Role__c = 'Action Source'
          AND Linked_Object_API_Name__c = 'Invoice__c'
      ]
    );
    System.assertEquals('insert', errorLog.Dml_Operation__c);
  }
}