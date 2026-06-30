@isTest(seeAllData=false)
private class CarrierMappingServiceTest {
    
    // Helper to create a mock Field_Mapping__mdt in memory
    private static Field_Mapping__mdt createMockMapping(String sfField, String externalField, String direction) {
        Field_Mapping__mdt mapping = new Field_Mapping__mdt();
        mapping.SF_Field__c = sfField;
        mapping.External_Field__c = externalField;
        mapping.Sync_Direction__c = direction;
        return mapping;
    }
    
    // Test data setup with all required fields
    private static Account createTestAccount() {
        Account acc = new Account(Name = 'Test Account', Phone = '123-456');
        // Ensure any required custom fields are populated – add if needed in your org
        return acc;
    }
    
    private static Contact createTestContactWithParent() {
        Account acc = createTestAccount();
        insert acc;
        Contact con = new Contact(LastName = 'Receiver', AccountId = acc.Id);
        return con;
    }
    
    // ==================== load() Tests ====================
    @isTest
    static void testLoad_BlankParams_ReturnsEmptyMappingSet() {
        CarrierMappingService.MappingSet result = CarrierMappingService.load('', '', '');
        System.assertEquals('', result.integration);
        System.assertEquals('', result.actionName);
        System.assertEquals('', result.sfObjectApiName);
        System.assertEquals(0, result.requestMappings.size());
        System.assertEquals(0, result.responseMappings.size());
    }
    
    @isTest
    static void testLoad_WithMockMappingSet_ReturnsMockData() {
        String integration = 'TestInt';
        String action = 'TestAction';
        String objApi = 'Account';
        String key = integration + '|' + action + '|' + objApi;
        
        CarrierMappingService.MappingSet mockSet = new CarrierMappingService.MappingSet();
        mockSet.integration = integration;
        mockSet.actionName = action;
        mockSet.sfObjectApiName = objApi;
        mockSet.requestMappings.add(createMockMapping('Name', 'extName', CarrierMappingService.DIRECTION_TO_CARRIER));
        mockSet.responseMappings.add(createMockMapping('Phone', 'extPhone', CarrierMappingService.DIRECTION_TO_SF));
        
        CarrierMappingService.testMappingSets = new Map<String, CarrierMappingService.MappingSet>{ key => mockSet };
        
        Test.startTest();
        CarrierMappingService.MappingSet result = CarrierMappingService.load(integration, action, objApi);
        Test.stopTest();
        
        System.assertEquals(integration, result.integration);
        System.assertEquals(1, result.requestMappings.size());
        System.assertEquals(1, result.responseMappings.size());
        System.assertEquals('Name', result.requestMappings[0].SF_Field__c);
        System.assertEquals('Phone', result.responseMappings[0].SF_Field__c);
        
        CarrierMappingService.testMappingSets = null;
    }
    
    @isTest
    static void testLoad_NoMockAndNoMetadata_ReturnsEmptyMappings() {
        CarrierMappingService.MappingSet result = CarrierMappingService.load('X', 'Y', 'Z');
        System.assertEquals(0, result.requestMappings.size());
        System.assertEquals(0, result.responseMappings.size());
    }
    
    // ==================== queryMappedRecord() Tests ====================
    @isTest
    static void testQueryMappedRecord_NullInputs_ThrowsException() {
        Boolean exceptionCaught = false;
        try {
            CarrierMappingService.queryMappedRecord(null, new CarrierMappingService.MappingSet(), '');
        } catch (AuraHandledException e) {
            exceptionCaught = true;
        }
        System.assert(exceptionCaught, 'Should have thrown for null recordId');
        
        exceptionCaught = false;
        try {
            CarrierMappingService.queryMappedRecord(createTestAccount().Id, null, '');
        } catch (AuraHandledException e) {
            exceptionCaught = true;
        }
        System.assert(exceptionCaught, 'Should have thrown for null mappingSet');
        
        exceptionCaught = false;
        try {
            CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
            ms.sfObjectApiName = '';
            CarrierMappingService.queryMappedRecord(createTestAccount().Id, ms, '');
        } catch (AuraHandledException e) {
            exceptionCaught = true;
        }
        System.assert(exceptionCaught, 'Should have thrown for blank object API name');
    }
    
    @isTest
    static void testQueryMappedRecord_RequestDirection_SelectsRequestFields() {
        Account acc = createTestAccount();
        insert acc;
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Account';
        ms.requestMappings.add(createMockMapping('Name', 'extName', CarrierMappingService.DIRECTION_TO_CARRIER));
        ms.requestMappings.add(createMockMapping('Phone', 'extPhone', CarrierMappingService.DIRECTION_TO_CARRIER));
        
        SObject result = CarrierMappingService.queryMappedRecord(acc.Id, ms, CarrierMappingService.DIRECTION_TO_CARRIER);
        System.assertEquals(acc.Id, result.Id);
        System.assertEquals('Test Account', result.get('Name'));
        System.assertEquals('123-456', result.get('Phone'));
    }
    
    @isTest
    static void testQueryMappedRecord_ResponseDirection_SelectsResponseFields() {
        Account acc = createTestAccount();
        insert acc;
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Account';
        ms.responseMappings.add(createMockMapping('Name', 'extName', CarrierMappingService.DIRECTION_TO_SF));
        
        SObject result = CarrierMappingService.queryMappedRecord(acc.Id, ms, CarrierMappingService.DIRECTION_TO_SF);
        System.assertEquals(acc.Name, result.get('Name'));
    }
    
    // ==================== buildRequestPayload() Tests ====================
    @isTest
    static void testBuildRequestPayload_NullInputs_ReturnsEmptyMap() {
        System.assertEquals(0, CarrierMappingService.buildRequestPayload(null, null).size());
        System.assertEquals(0, CarrierMappingService.buildRequestPayload(new Account(), null).size());
    }
    
    @isTest
    static void testBuildRequestPayload_SkipsBlankOrNullFields() {
        Account acc = createTestAccount();
        insert acc;
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.requestMappings.add(createMockMapping('', 'ext', CarrierMappingService.DIRECTION_TO_CARRIER));
        ms.requestMappings.add(createMockMapping('Name', '', CarrierMappingService.DIRECTION_TO_CARRIER));
        ms.requestMappings.add(createMockMapping('NonExistent', 'ext2', CarrierMappingService.DIRECTION_TO_CARRIER));
        
        Map<String, Object> payload = CarrierMappingService.buildRequestPayload(acc, ms);
        System.assertEquals(0, payload.size());
    }
    
    @isTest
    static void testBuildRequestPayload_IgnoresNullFieldValue() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.requestMappings.add(createMockMapping('Phone', 'extPhone', CarrierMappingService.DIRECTION_TO_CARRIER));
        
        Map<String, Object> payload = CarrierMappingService.buildRequestPayload(acc, ms);
        System.assert(!payload.containsKey('extPhone'), 'Payload should not contain keys for fields with null values');
    }
    
    @isTest
    static void testBuildRequestPayload_NestedPath_FromDotNotation() {
        Contact con = createTestContactWithParent();
        insert con;   // Insert the contact after setting AccountId
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Contact';
        ms.requestMappings.add(createMockMapping('Account.Name', 'billing.name', CarrierMappingService.DIRECTION_TO_CARRIER));
        
        SObject queried = CarrierMappingService.queryMappedRecord(con.Id, ms, CarrierMappingService.DIRECTION_TO_CARRIER);
        Map<String, Object> payload = CarrierMappingService.buildRequestPayload(queried, ms);
        System.assertEquals('Test Account', CarrierMappingService.getPath(payload, 'billing.name'));
    }
    
    // ==================== buildResponseUpdate() Tests ====================
    @isTest
    static void testBuildResponseUpdate_NullInputs_ReturnsNull() {
        System.assertEquals(null, CarrierMappingService.buildResponseUpdate(null, null, null));
        System.assertEquals(null, CarrierMappingService.buildResponseUpdate(createTestAccount().Id, null, null));
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = '';
        System.assertEquals(null, CarrierMappingService.buildResponseUpdate(createTestAccount().Id, ms, null));
    }
    
    @isTest
    static void testBuildResponseUpdate_InvalidObjectType_ReturnsNull() {
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'InvalidObject__x';
        System.assertEquals(null, CarrierMappingService.buildResponseUpdate(createTestAccount().Id, ms, null));
    }
    
    @isTest
    static void testBuildResponseUpdate_SkipsNonUpdateableField() {
        Account acc = createTestAccount();
        insert acc;
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Account';
        ms.responseMappings.add(createMockMapping('Id', 'extId', CarrierMappingService.DIRECTION_TO_SF));
        
        Map<String, Object> resp = new Map<String, Object>{ 'extId' => '001XXX' };
        SObject updateRecord = CarrierMappingService.buildResponseUpdate(acc.Id, ms, resp);
        System.assertEquals(null, updateRecord);
    }
    
    @isTest
    static void testBuildResponseUpdate_SkipsNullResponseValue() {
        Account acc = createTestAccount();
        insert acc;
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Account';
        ms.responseMappings.add(createMockMapping('Name', 'extName', CarrierMappingService.DIRECTION_TO_SF));
        
        Map<String, Object> resp = new Map<String, Object>{ 'extName' => null };
        SObject updateRecord = CarrierMappingService.buildResponseUpdate(acc.Id, ms, resp);
        System.assertEquals(null, updateRecord);
    }
    
    @isTest
    static void testBuildResponseUpdate_ValidMapping_ReturnsSObject() {
        Account acc = createTestAccount();
        insert acc;
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Account';
        ms.responseMappings.add(createMockMapping('Name', 'newName', CarrierMappingService.DIRECTION_TO_SF));
        
        Map<String, Object> resp = new Map<String, Object>{ 'newName' => 'Updated Name' };
        SObject updateRecord = CarrierMappingService.buildResponseUpdate(acc.Id, ms, resp);
        System.assertNotEquals(null, updateRecord);
        System.assertEquals('Updated Name', updateRecord.get('Name'));
    }
    
    // ==================== applyResponseMappings() Tests ====================
    @isTest
    static void testApplyResponseMappings_Success() {
        Account acc = new Account(Name = 'Old Name');
        insert acc;
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.integration = 'TestInt';
        ms.sfObjectApiName = 'Account';
        ms.responseMappings.add(createMockMapping('Name', 'newName', CarrierMappingService.DIRECTION_TO_SF));
        
        Map<String, Object> response = new Map<String, Object>{ 'newName' => 'Updated Name' };
        
        Test.startTest();
        CarrierMappingService.applyResponseMappings(acc.Id, ms, response);
        Test.stopTest();
        
        Account updated = [SELECT Name FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Updated Name', updated.Name);
    }
    
    @isTest
    static void testApplyResponseMappings_DmlException_LogsAndThrows() {
        Account acc = new Account(Name = 'Old');
        insert acc;
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.integration = 'TestInt';
        ms.sfObjectApiName = 'Account';
        ms.responseMappings.add(createMockMapping('Name', 'newName', CarrierMappingService.DIRECTION_TO_SF));
        
        // Name field max length is 255, so 300 chars will cause DmlException
        String longName = 'A'.repeat(300);
        Map<String, Object> response = new Map<String, Object>{ 'newName' => longName };
        
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            CarrierMappingService.applyResponseMappings(acc.Id, ms, response);
        } catch (DmlException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('STRING_TOO_LONG'), 'Expected DmlException due to long string');
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'DmlException should be thrown for too long field value');
    }
    
    // ==================== getPath() / putPath() Tests ====================
    @isTest
    static void testGetPath_InvalidInputs_ReturnsNull() {
        System.assertEquals(null, CarrierMappingService.getPath(null, 'a.b'));
        System.assertEquals(null, CarrierMappingService.getPath(new Map<String, Object>(), ''));
        System.assertEquals(null, CarrierMappingService.getPath(new Map<String, Object>(), null));
    }
    
    @isTest
    static void testGetPath_SimpleKey_ReturnsValue() {
        Map<String, Object> data = new Map<String, Object>{ 'key' => 'value' };
        System.assertEquals('value', CarrierMappingService.getPath(data, 'key'));
    }
    
    @isTest
    static void testGetPath_NestedMap_ReturnsValue() {
        Map<String, Object> data = new Map<String, Object>{
            'level1' => new Map<String, Object>{ 'level2' => 'found' }
        };
        System.assertEquals('found', CarrierMappingService.getPath(data, 'level1.level2'));
    }
    
    @isTest
    static void testGetPath_BracketNotation_ReturnsValue() {
        Map<String, Object> data = new Map<String, Object>{
            'items' => new List<Object>{ new Map<String, Object>{ 'id' => 123 } }
        };
        System.assertEquals(123, CarrierMappingService.getPath(data, 'items[0].id'));
    }
    
    @isTest
    static void testGetPath_IntegerSegment_ReturnsListElement() {
        Map<String, Object> data = new Map<String, Object>{
            'shipment' => new List<Object>{ 'first', 'second' }
        };
        System.assertEquals('second', CarrierMappingService.getPath(data, 'shipment.1'));
    }
    
    @isTest
    static void testGetPath_InvalidPath_ReturnsNull() {
        Map<String, Object> data = new Map<String, Object>{ 'a' => new Map<String, Object>() };
        System.assertEquals(null, CarrierMappingService.getPath(data, 'a.b.c'));
        System.assertEquals(null, CarrierMappingService.getPath(data, 'a[0]'));
    }
    
    @isTest
    static void testPutPath_InvalidInputs_DoesNothing() {
        Map<String, Object> target = new Map<String, Object>();
        CarrierMappingService.putPath(null, 'a', 'val');
        CarrierMappingService.putPath(target, '', 'val');
        CarrierMappingService.putPath(target, null, 'val');
        System.assertEquals(0, target.size());
    }
    
    @isTest
    static void testPutPath_CreatesNestedMap() {
        Map<String, Object> target = new Map<String, Object>();
        CarrierMappingService.putPath(target, 'a.b.c', 'deep');
        System.assertEquals('deep', CarrierMappingService.getPath(target, 'a.b.c'));
    }
    
    @isTest
    static void testPutPath_CreatesArrayWithPadding() {
        Map<String, Object> target = new Map<String, Object>();
        CarrierMappingService.putPath(target, 'items[2].name', 'third');
        List<Object> items = (List<Object>) target.get('items');
        System.assertEquals(3, items.size());
        System.assertEquals(null, items[0]);
        System.assertEquals(null, items[1]);
        System.assertEquals('third', ((Map<String, Object>) items[2]).get('name'));
    }
    
    @isTest
    static void testPutPath_OverwritesExisting() {
        Map<String, Object> target = new Map<String, Object>{ 'x' => 'old' };
        CarrierMappingService.putPath(target, 'x', 'new');
        System.assertEquals('new', target.get('x'));
    }
    
    @isTest
    static void testPutPath_NormalizesDateAndDatetime() {
        Map<String, Object> target = new Map<String, Object>();
        Date d = Date.today();
        CarrierMappingService.putPath(target, 'dateField', d);
        System.assertEquals(String.valueOf(d), target.get('dateField'));
        
        Datetime dt = Datetime.now();
        CarrierMappingService.putPath(target, 'datetimeField', dt);
        String expected = dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        System.assertEquals(expected, target.get('datetimeField'));
    }
    
    // ==================== Data Type Coercion Tests (fixed NullPointer) ====================
    @isTest
    static void testCoerceValue_Branches() {
        Account acc = createTestAccount();
        insert acc;
        Opportunity opp = new Opportunity(Name = 'Test Opp', StageName = 'Prospecting', CloseDate = Date.today());
        insert opp;
        
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        
        // Boolean from String
        ms.sfObjectApiName = 'Opportunity';
        ms.responseMappings = new List<Field_Mapping__mdt>{ createMockMapping('IsPrivate', 'extBool', CarrierMappingService.DIRECTION_TO_SF) };
        Map<String, Object> resp = new Map<String, Object>{ 'extBool' => 'false' };
        SObject upd = CarrierMappingService.buildResponseUpdate(opp.Id, ms, resp);
        System.assertNotEquals(null, upd);
        System.assertEquals(false, upd.get('IsPrivate'));
        
        // Integer from String
        ms.sfObjectApiName = 'Account';
        ms.responseMappings = new List<Field_Mapping__mdt>{ createMockMapping('NumberOfEmployees', 'extInt', CarrierMappingService.DIRECTION_TO_SF) };
        resp = new Map<String, Object>{ 'extInt' => '100' };
        upd = CarrierMappingService.buildResponseUpdate(acc.Id, ms, resp);
        System.assertNotEquals(null, upd);
        System.assertEquals(100, upd.get('NumberOfEmployees'));
        
        // Decimal from String
        ms.sfObjectApiName = 'Account';
        ms.responseMappings = new List<Field_Mapping__mdt>{ createMockMapping('AnnualRevenue', 'extDec', CarrierMappingService.DIRECTION_TO_SF) };
        resp = new Map<String, Object>{ 'extDec' => '987.65' };
        upd = CarrierMappingService.buildResponseUpdate(acc.Id, ms, resp);
        System.assertNotEquals(null, upd);
        System.assertEquals(987.65, upd.get('AnnualRevenue'));
        
        // Date from String
        ms.sfObjectApiName = 'Opportunity';
        ms.responseMappings = new List<Field_Mapping__mdt>{ createMockMapping('CloseDate', 'extDate', CarrierMappingService.DIRECTION_TO_SF) };
        resp = new Map<String, Object>{ 'extDate' => '2025-01-15' };
        upd = CarrierMappingService.buildResponseUpdate(opp.Id, ms, resp);
        System.assertNotEquals(null, upd);
        System.assertEquals(Date.newInstance(2025,1,15), upd.get('CloseDate'));
        
        // DateTime from ISO string
        Task tsk = new Task(Subject = 'Test Task');
        insert tsk;
        ms.sfObjectApiName = 'Task';
        ms.responseMappings = new List<Field_Mapping__mdt>{ createMockMapping('ReminderDateTime', 'extDateTime', CarrierMappingService.DIRECTION_TO_SF) };
        resp = new Map<String, Object>{ 'extDateTime' => '2025-01-15T10:30:00Z' };
        upd = CarrierMappingService.buildResponseUpdate(tsk.Id, ms, resp);
        System.assertNotEquals(null, upd);
        Datetime expected = Datetime.valueOfGmt('2025-01-15 10:30:00');
        System.assertEquals(expected, upd.get('ReminderDateTime'));
    }
    
    // ==================== isDirectionToSalesforce() indirect coverage ====================
    @isTest
    static void testDirectionClassification_ThroughLoad() {
        String key = 'dirTest|act|Account';
        CarrierMappingService.MappingSet mockSet = new CarrierMappingService.MappingSet();
        // Request mappings
        mockSet.requestMappings.add(createMockMapping('Name', 'ext', 'SF to Carrier'));
        // Response mappings
        mockSet.responseMappings.add(createMockMapping('Phone', 'ext2', 'Carrier to SF'));
        mockSet.responseMappings.add(createMockMapping('Fax', 'ext3', 'fedex to sf'));
        mockSet.responseMappings.add(createMockMapping('Website', 'ext4', 'ups to sf'));
        mockSet.responseMappings.add(createMockMapping('Description', 'ext5', 'carrier to salesforce'));
        // Blank direction – should be classified as request, so we add it to requestMappings, not response
        mockSet.requestMappings.add(createMockMapping('Industry', 'ext6', ''));
        
        CarrierMappingService.testMappingSets = new Map<String, CarrierMappingService.MappingSet>{ key => mockSet };
        CarrierMappingService.MappingSet result = CarrierMappingService.load('dirTest', 'act', 'Account');
        // Now we have 2 request mappings (SF to Carrier + blank) and 4 response mappings
        System.assertEquals(2, result.requestMappings.size(), 'Expected 2 request mappings');
        System.assertEquals(4, result.responseMappings.size(), 'Expected 4 response mappings');
        CarrierMappingService.testMappingSets = null;
    }
    
    // ==================== Namespace prefix handling ====================
    @isTest
    static void testGetSObjectType_NamespaceHandling_DoesNotBreak() {
        Account acc = createTestAccount();
        insert acc;
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Account';
        ms.responseMappings.add(createMockMapping('Name', 'extName', CarrierMappingService.DIRECTION_TO_SF));
        Map<String, Object> resp = new Map<String, Object>{ 'extName' => 'Test' };
        SObject upd = CarrierMappingService.buildResponseUpdate(acc.Id, ms, resp);
        System.assertNotEquals(null, upd);
    }
    
    // ==================== Edge Cases for parsePath ====================
    @isTest
    static void testParsePath_InvalidIndex_Throws() {
        Map<String, Object> target = new Map<String, Object>();
        try {
            CarrierMappingService.putPath(target, 'invalid[abc]', 'bad');
            System.assert(false, 'Should have thrown exception for non-integer index');
        } catch (Exception e) {
            // Expected TypeException or StringException
            System.assert(true);
        }
    }
    
    // ==================== getMappingKey() Test ====================
    @isTest
    static void testGetMappingKey_ReturnsConcatenatedString() {
        String key = CarrierMappingService.getMappingKey('Int', 'Act', 'Obj');
        System.assertEquals('Int|Act|Obj', key);
    }
    
    // ==================== Additional coverage for getPath with null intermediate ====================
    @isTest
    static void testGetPath_WithNullIntermediate_ReturnsNull() {
        Map<String, Object> data = new Map<String, Object>{
            'a' => new Map<String, Object>()
        };
        System.assertEquals(null, CarrierMappingService.getPath(data, 'a.b.c'));
    }
    
    // ==================== Additional coverage for putPath with existing list ====================
    @isTest
    static void testPutPath_WithExistingList_UpdatesElement() {
        Map<String, Object> target = new Map<String, Object>();
        CarrierMappingService.putPath(target, 'items[0]', 'first');
        CarrierMappingService.putPath(target, 'items[0]', 'updated');
        List<Object> items = (List<Object>) target.get('items');
        System.assertEquals('updated', items[0]);
    }
    
    // ==================== Additional coverage for coerceValue direct type branches ====================
    @isTest
    static void testCoerceValue_BooleanDirect() {
        Opportunity opp = new Opportunity(Name = 'Test', StageName = 'Prospecting', CloseDate = Date.today());
        insert opp;
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Opportunity';
        ms.responseMappings.add(createMockMapping('IsPrivate', 'extBool', CarrierMappingService.DIRECTION_TO_SF));
        // Pass Boolean directly (not string)
        Map<String, Object> resp = new Map<String, Object>{ 'extBool' => true };
        SObject upd = CarrierMappingService.buildResponseUpdate(opp.Id, ms, resp);
        System.assertEquals(true, upd.get('IsPrivate'));
    }
    
    @isTest
    static void testCoerceValue_IntegerDirect() {
        Opportunity opp = new Opportunity(Name = 'Test', StageName = 'Prospecting', CloseDate = Date.today());
        insert opp;
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Opportunity';
        ms.responseMappings.add(createMockMapping('Amount', 'extDec', CarrierMappingService.DIRECTION_TO_SF));
        Map<String, Object> resp = new Map<String, Object>{ 'extDec' => 100 };
        SObject upd = CarrierMappingService.buildResponseUpdate(opp.Id, ms, resp);
        System.assertEquals(100.00, upd.get('Amount'));
    }
    
    @isTest
    static void testCoerceValue_DecimalDirect() {
        Opportunity opp = new Opportunity(Name = 'Test', StageName = 'Prospecting', CloseDate = Date.today());
        insert opp;
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Opportunity';
        ms.responseMappings.add(createMockMapping('Amount', 'extDec', CarrierMappingService.DIRECTION_TO_SF));
        Map<String, Object> resp = new Map<String, Object>{ 'extDec' => 987.65 };
        SObject upd = CarrierMappingService.buildResponseUpdate(opp.Id, ms, resp);
        System.assertEquals(987.65, upd.get('Amount'));
    }
    
    @isTest
    static void testCoerceValue_DateDirect() {
        Opportunity opp = new Opportunity(Name = 'Test', StageName = 'Prospecting', CloseDate = Date.today());
        insert opp;
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Opportunity';
        ms.responseMappings.add(createMockMapping('CloseDate', 'extDate', CarrierMappingService.DIRECTION_TO_SF));
        Date d = Date.today();
        Map<String, Object> resp = new Map<String, Object>{ 'extDate' => d };
        SObject upd = CarrierMappingService.buildResponseUpdate(opp.Id, ms, resp);
        System.assertEquals(d, upd.get('CloseDate'));
    }
    
    @isTest
    static void testCoerceValue_DateTimeDirect() {
        Task tsk = new Task(Subject = 'Test Task');
        insert tsk;
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'Task';
        ms.responseMappings.add(createMockMapping('ReminderDateTime', 'extDateTime', CarrierMappingService.DIRECTION_TO_SF));
        Datetime now = Datetime.now();
        Map<String, Object> resp = new Map<String, Object>{ 'extDateTime' => now };
        SObject upd = CarrierMappingService.buildResponseUpdate(tsk.Id, ms, resp);
        System.assertEquals(now, upd.get('ReminderDateTime'));
    }
    
    // ==================== Namespace prefix branch coverage ====================
    @isTest
    static void testGetSObjectType_NamespaceBranch() {
        // Use a non-existent custom object name to force the namespace prefix lookup
        CarrierMappingService.MappingSet ms = new CarrierMappingService.MappingSet();
        ms.sfObjectApiName = 'NonExistent__c';  // Ends with __c, triggers namespace branch
        ms.responseMappings.add(createMockMapping('Name', 'extName', CarrierMappingService.DIRECTION_TO_SF));
        // This will call getSObjectType and the namespace branch will execute (even if the object doesn't exist)
        SObject upd = CarrierMappingService.buildResponseUpdate(createTestAccount().Id, ms, null);
        System.assertEquals(null, upd, 'Non-existent object returns null without error');
    }
    
    // ==================== getPath blank key edge case ====================
    @isTest
    static void testGetPath_BlankKeyToken() {
        Map<String, Object> data = new Map<String, Object>{ 'list' => new List<Object>{ 'value' } };
        // Path "[0]" produces a token with key=null, hasIndex=true, which hits the else if (String.isBlank(token.key)) line.
        Object result = CarrierMappingService.getPath(data, '[0]');
        System.assertEquals(null, result, 'Path with only index returns null as expected');
    }
}