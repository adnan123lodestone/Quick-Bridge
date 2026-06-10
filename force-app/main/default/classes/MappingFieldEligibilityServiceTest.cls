@isTest
private class MappingFieldEligibilityServiceTest {

    @isTest
    static void blockedFieldsReturnFalse() {
        List<String> blocked = new List<String>{
            'OwnerId', 'CreatedDate', 'CreatedById',
            'LastModifiedDate', 'LastModifiedById', 'SystemModstamp',
            'IsDeleted', 'RecordTypeId', 'CurrencyIsoCode',
            'LastViewedDate', 'LastReferencedDate'
        };
        Test.startTest();
        for (String f : blocked) {
            Assert.isFalse(
                MappingFieldEligibilityService.isSalesforceFieldAllowed(f),
                f + ' should be blocked'
            );
            // Case-insensitive
            Assert.isFalse(
                MappingFieldEligibilityService.isSalesforceFieldAllowed(f.toLowerCase()),
                f.toLowerCase() + ' should be blocked (lowercase)'
            );
        }
        Test.stopTest();
    }

    @isTest
    static void allowedFieldsReturnTrue() {
        List<String> allowed = new List<String>{
            'Id', 'AccountId', 'ContactId', 'Product2Id', 'Pricebook2Id',
            'Name', 'OrderNumber', 'TotalAmount',
            'QuickbookID__c', 'External_Id__c', 'Shopify_ID__c',
            'Stripe_Customer_Id__c', 'Order__c'
        };
        Test.startTest();
        for (String f : allowed) {
            Assert.isTrue(
                MappingFieldEligibilityService.isSalesforceFieldAllowed(f),
                f + ' should be allowed'
            );
        }
        Test.stopTest();
    }

    @isTest
    static void nullAndBlankAreAllowed() {
        Test.startTest();
        Assert.isTrue(MappingFieldEligibilityService.isSalesforceFieldAllowed(null));
        Assert.isTrue(MappingFieldEligibilityService.isSalesforceFieldAllowed(''));
        Assert.isTrue(MappingFieldEligibilityService.isSalesforceFieldAllowed('   '));
        Test.stopTest();
    }

    @isTest
    static void assertThrowsForBlockedField() {
        Test.startTest();
        Boolean threw = false;
        try {
            MappingFieldEligibilityService.assertNoBlockedSalesforceFields(
                new List<String>{ 'Name', 'OwnerId', 'AccountId' }
            );
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('OwnerId'), 'Exception message should name the blocked field');
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Expected AuraHandledException for blocked field OwnerId');
    }

    @isTest
    static void assertPassesForAllowedFields() {
        Test.startTest();
        // Should not throw
        MappingFieldEligibilityService.assertNoBlockedSalesforceFields(
            new List<String>{ 'Id', 'Name', 'AccountId', 'QuickbookID__c' }
        );
        MappingFieldEligibilityService.assertNoBlockedSalesforceFields(null);
        MappingFieldEligibilityService.assertNoBlockedSalesforceFields(new List<String>());
        Test.stopTest();
        Assert.isTrue(true, 'No exception expected for allowed fields');
    }

    @isTest
    static void assertSkipsBlankEntriesInList() {
        Test.startTest();
        // blank entries in the list should not trigger an error
        MappingFieldEligibilityService.assertNoBlockedSalesforceFields(
            new List<String>{ 'Name', '', null, 'AccountId' }
        );
        Test.stopTest();
        Assert.isTrue(true, 'Blank/null entries should be skipped');
    }
}