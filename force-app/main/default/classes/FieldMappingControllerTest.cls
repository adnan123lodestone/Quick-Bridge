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
            String jsonBody = '{"QueryResponse": {"Customer": [{' +
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

    private static Field_Mapping__mdt buildTestMapping(String integration, String sfObject, String direction) {
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
        
        for(Integer i = 1; i < result.size(); i++) {
            String prevLabel = result[i-1].get('label').toLowerCase();
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
        List<Map<String, String>> mappings = FieldMappingController.getExistingMappings('qbonline', 'Account');
        Test.stopTest();

        Assert.isNotNull(mappings);
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
        FieldMappingController.getQuickBooksFields('Purchase_Order__c', 'PurchaseOrder');
        FieldMappingController.getQuickBooksFields('Item_Sales_Tax__c', 'TaxCode');
        
        Test.stopTest();
        Assert.isTrue(true);
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
            Assert.isTrue(FieldMappingController.getFedExFields(actionName, null).size() > 0);
            Assert.isTrue(FieldMappingController.getUPSFields(actionName, null).size() > 0);
        }

        Test.stopTest();
    }

    @isTest
    static void testSaveAndLoadCarrierMappings() {
        String outboundJson = '[{"sfField":"Name","externalField":"masterTrackingNumber","syncDirection":"SF to FedEx"}]';
        String inboundJson = '[{"sfField":"Name","externalField":"label.trackingNumber","syncDirection":"FedEx to SF"}]';
        String upsJson = '[{"sfField":"Name","externalField":"masterTrackingNumber","syncDirection":"SF to UPS"}]';

        Test.startTest();
        String fedexOutboundResponse = FieldMappingController.saveFedExFieldMappings('unknownAction', 'Account', outboundJson);
        String fedexInboundResponse = FieldMappingController.saveFedExFieldMappings('generateLabel', 'Account', inboundJson);
        String upsResponse = FieldMappingController.saveUPSFieldMappings('unknownAction', 'Account', upsJson);
        List<Map<String, String>> fedexMappings = FieldMappingController.getExistingFedExMappings('unknownAction', 'Account');
        List<Map<String, String>> upsMappings = FieldMappingController.getExistingUPSMappings('unknownAction', 'Account');
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
        
        List<Map<String, Object>> qbFields = FieldMappingController.getQuickBooksFields('Account', 'Customer');
        
        Test.stopTest();
        Assert.isTrue(qbFields.size() > 0);
    }

    @isTest
    static void testSaveFieldMappingsSuccess() {
        FieldMappingController.testActiveMappings = new List<Field_Mapping__mdt>();
        String mappingsJson = '[{"sfField":"Name","externalField":"DisplayName"}]';

        Test.startTest();
        String response = FieldMappingController.saveFieldMappings('qbonline', 'Account', 'Customer', mappingsJson);
        Test.stopTest();

        Assert.isTrue(response.contains('Deployment Started'));
    }

    @isTest
    static void testShopifyInboundBlocksQboInboundOnly() {
        FieldMappingController.testActiveMappings = new List<Field_Mapping__mdt>{
            buildTestMapping('shopify', 'Account', 'Shopify to SF')
        };

        Test.startTest();
        Map<String, Object> availability = FieldMappingController.getMappingDirectionAvailability('qbonline', 'Account');
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
        Map<String, Object> availability = FieldMappingController.getMappingDirectionAvailability('shopify', 'Account');
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
        Map<String, Object> availability = FieldMappingController.getMappingDirectionAvailability('qbonline', 'Account');
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
            FieldMappingController.saveFieldMappings('qbonline', 'Account', 'Customer', mappingsJson);
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
        String response = FieldMappingController.saveFieldMappings('qbonline', 'Account', 'Customer', mappingsJson);
        Test.stopTest();

        Assert.isTrue(response.contains('Deployment Started'));
    }

    @isTest
    static void testSaveFieldMappingsEmpty() {
        Boolean didThrow = false;
        Test.startTest();
        try {
            FieldMappingController.saveFieldMappings('qbonline', 'Account', 'Customer', '[]');
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
}