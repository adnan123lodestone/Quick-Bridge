@IsTest
private class ConnectorAdapterAllowlistTest {

    @IsTest
    static void testAssertAllowedWithBlankOrNullInputs() {
        Test.startTest();
        try {
            ConnectorAdapterAllowlist.assertAllowed(null);
            ConnectorAdapterAllowlist.assertAllowed('');
            ConnectorAdapterAllowlist.assertAllowed('   ');
            System.assert(true, 'Blank and null inputs must return early without throwing.');
        } catch (Exception e) {
            System.assert(false, 'Early return failed: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testAssertAllowedWithApprovedClasses() {
        Test.startTest();
        try {
            ConnectorAdapterAllowlist.assertAllowed('StripePaymentAdapter');
            ConnectorAdapterAllowlist.assertAllowed('QuickBridge_Int.FedExCarrierAdapter');
            ConnectorAdapterAllowlist.assertAllowed('c.ShopifyScheduledOperationAdapter');
            
            System.assert(true, 'Approved classes must execute without throwing errors.');
        } catch (Exception e) {
            System.assert(false, 'Approved class threw an unexpected exception: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testAssertAllowedThrowsExceptionForUnapprovedClass() {
        String unapprovedClass = 'MaliciousMalwareAdapter';
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ConnectorAdapterAllowlist.assertAllowed(unapprovedClass);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception type caught: ' + e.getTypeName());
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Unapproved adapter class must throw an AuraHandledException.');
    }

    @IsTest
    static void testAssertAllowedWithUnapprovedClassContainingNamespace() {
        String unapprovedClassWithNamespace = 'QuickBridge_Int.InvalidCustomWorker';
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ConnectorAdapterAllowlist.assertAllowed(unapprovedClassWithNamespace);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Unapproved class with namespace must be rejected.');
    }
}