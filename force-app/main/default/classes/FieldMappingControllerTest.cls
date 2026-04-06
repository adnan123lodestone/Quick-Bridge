@isTest
public class FieldMappingControllerTest {
    
    @isTest
    static void testGetOrderFields() {
        Test.startTest();
        List<Map<String, String>> result = FieldMappingController.getOrderFields();
        Test.stopTest();
        
        // Verify we got some fields back
        Assert.isTrue(result.size() > 0, 'Should return Order fields');
        
        // Verify each field has label and value
        for (Map<String, String> field : result) {
            Assert.isNotNull(field.get('label'), 'Field should have a label');
            Assert.isNotNull(field.get('value'), 'Field should have a value');
        }
        
        // Verify fields are sorted alphabetically
        List<String> labels = new List<String>();
        for (Map<String, String> field : result) {
            labels.add(field.get('label'));
        }
        
        List<String> sortedLabels = new List<String>(labels);
        sortedLabels.sort();
        
        Assert.areEqual(sortedLabels, labels, 'Fields should be sorted alphabetically by label');
    }
    
    @isTest
    static void testOrderFieldsContainsCommonFields() {
        Test.startTest();
        List<Map<String, String>> result = FieldMappingController.getOrderFields();
        Test.stopTest();
        
        // Verify some common Order fields are present
        Set<String> fieldValues = new Set<String>();
        for (Map<String, String> field : result) {
            fieldValues.add(field.get('value'));
        }
        
        // Check for common Order fields
        Assert.isTrue(fieldValues.contains('Id'), 'Should contain Id field');
        Assert.isTrue(fieldValues.contains('OrderNumber'), 'Should contain OrderNumber field');
        Assert.isTrue(fieldValues.contains('TotalAmount'), 'Should contain TotalAmount field');
        Assert.isTrue(fieldValues.contains('Status'), 'Should contain Status field');
    }
}