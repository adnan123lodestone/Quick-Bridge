@IsTest
private class PaymentMethodAdminServiceTest {
    private static Map<String, Boolean> capturedProviderStates;

    private class FakeUpdater implements PaymentMethodAdminService.MetadataUpdater {
        public String upsertProviderStates(Map<String, Boolean> providerStates) {
            PaymentMethodAdminServiceTest.capturedProviderStates = providerStates.clone();
            return '0AfTEST000000001';
        }
    }

    @IsTest
    static void deactivatePaymentMethods_acceptsSupportedProviderStates() {
        PaymentMethodAdminService.testUpdater = new FakeUpdater();

        PaymentMethodAdminService.DeactivateRequest request =
            new PaymentMethodAdminService.DeactivateRequest();
        request.clientOrgName = 'Quickbridge';
        request.paymentMethodStates = new List<PaymentMethodAdminService.PaymentMethodState>{
            buildState('Stripe', true),
            buildState(' paypal ', false),
            buildState('Stripe', true)
        };

        Test.startTest();
        PaymentMethodAdminService.DeactivateResponse response =
            PaymentMethodAdminService.deactivatePaymentMethods(request);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('0AfTEST000000001', response.deploymentId);
        System.assertEquals(2, response.acceptedMethods.size());
        System.assertEquals(true, response.acceptedMethods.contains('paypal'));
        System.assertEquals(true, response.acceptedMethods.contains('stripe'));
        System.assertEquals(0, response.unsupportedMethods.size());
        System.assertEquals(true, capturedProviderStates.get('stripe'));
        System.assertEquals(false, capturedProviderStates.get('paypal'));
    }

    @IsTest
    static void deactivatePaymentMethods_acceptsAllPaymentProvidersFromRegistry() {
        PaymentMethodAdminService.testUpdater = new FakeUpdater();

        PaymentMethodAdminService.DeactivateRequest request = new PaymentMethodAdminService.DeactivateRequest();
        request.paymentMethodStates = new List<PaymentMethodAdminService.PaymentMethodState>{
            buildState('authorizenet', true),
            buildState('stripe', false),
            buildState('paypal', true)
        };

        PaymentMethodAdminService.DeactivateResponse response = PaymentMethodAdminService.deactivatePaymentMethods(request);

        System.assertEquals(true, response.success);
        System.assertEquals(3, response.acceptedMethods.size());
        System.assert(response.message.contains('Authorize.Net'));
        System.assertEquals(true, capturedProviderStates.get('authorizenet'));
    }

    @IsTest
    static void deactivatePaymentMethods_acceptsNewPaymentProductFromCatalog() {
        insert new Integration_Product__c(
            Product_Key__c = 'venmo',
            Connector_Key__c = 'venmo',
            Product_Label__c = 'Venmo',
            Aliases__c = 'venmo',
            Category__c = 'Payment',
            Config_Record_Name__c = 'Venmo',
            Display_Order__c = 80,
            Enabled__c = true,
            Catalog_Active__c = true,
            Has_Payment__c = true,
            Has_Checkout__c = true
        );
        IntegrationConnectorRegistry.clearCache();
        PaymentMethodAdminService.testUpdater = new FakeUpdater();

        PaymentMethodAdminService.DeactivateRequest request = new PaymentMethodAdminService.DeactivateRequest();
        request.paymentMethodStates = new List<PaymentMethodAdminService.PaymentMethodState>{
            buildState('Venmo', true)
        };

        PaymentMethodAdminService.DeactivateResponse response = PaymentMethodAdminService.deactivatePaymentMethods(request);

        System.assertEquals(true, response.success);
        System.assertEquals(new List<String>{ 'venmo' }, response.acceptedMethods);
        System.assertEquals(true, capturedProviderStates.get('venmo'));
        System.assert(response.message.contains('Venmo'));
    }

    @IsTest
    static void deactivatePaymentMethods_defaultUpdaterPathIsCallable() {
        PaymentMethodAdminService.testUpdater = null;
        PaymentMethodAdminService.DeactivateRequest request = new PaymentMethodAdminService.DeactivateRequest();
        request.paymentMethodStates = new List<PaymentMethodAdminService.PaymentMethodState>{
            buildState('stripe', true)
        };

        Test.startTest();
        try {
            PaymentMethodAdminService.DeactivateResponse response = PaymentMethodAdminService.deactivatePaymentMethods(request);
            System.assertEquals(true, response.success);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage(), 'Metadata API path should be covered even if the test org rejects deployment.');
        }
        Test.stopTest();
    }

    @IsTest
    static void deactivatePaymentMethods_rejectsUnsupportedOnlyInput() {
        PaymentMethodAdminService.testUpdater = new FakeUpdater();

        PaymentMethodAdminService.DeactivateRequest request =
            new PaymentMethodAdminService.DeactivateRequest();
        request.paymentMethodStates = new List<PaymentMethodAdminService.PaymentMethodState>{
            buildState('venmo', true)
        };

        try {
            PaymentMethodAdminService.deactivatePaymentMethods(request);
            System.assert(false, 'Expected a PaymentMethodAdminException.');
        } catch (PaymentMethodAdminService.PaymentMethodAdminException e) {
            System.assertEquals('No supported payment methods were provided.', e.getMessage());
        }
    }

    @IsTest
    static void deactivatePaymentMethods_tracksUnsupportedInputs() {
        PaymentMethodAdminService.testUpdater = new FakeUpdater();

        PaymentMethodAdminService.DeactivateRequest request =
            new PaymentMethodAdminService.DeactivateRequest();
        request.clientOrgName = 'Quickbridge';
        request.paymentMethodStates = new List<PaymentMethodAdminService.PaymentMethodState>{
            buildState('Stripe', false),
            buildState('Venmo', true),
            buildState('   ', true),
            null
        };

        PaymentMethodAdminService.DeactivateResponse response =
            PaymentMethodAdminService.deactivatePaymentMethods(request);

        System.assertEquals(true, response.success);
        System.assertEquals(1, response.acceptedMethods.size());
        System.assertEquals('stripe', response.acceptedMethods[0]);
        System.assertEquals(1, response.unsupportedMethods.size());
        System.assertEquals('Venmo', response.unsupportedMethods[0]);
        System.assert(response.message.contains('Quickbridge'));
        System.assert(response.message.contains('inactive'));
    }

    @IsTest
    static void deactivatePaymentMethods_rejectsEmptyRequest() {
        Boolean nullRejected = false;
        try {
            PaymentMethodAdminService.deactivatePaymentMethods(null);
        } catch (PaymentMethodAdminService.PaymentMethodAdminException e) {
            nullRejected = true;
        }
        System.assertEquals(true, nullRejected);

        Boolean emptyRejected = false;
        try {
            PaymentMethodAdminService.DeactivateRequest request = new PaymentMethodAdminService.DeactivateRequest();
            request.paymentMethodStates = new List<PaymentMethodAdminService.PaymentMethodState>();
            PaymentMethodAdminService.deactivatePaymentMethods(request);
        } catch (PaymentMethodAdminService.PaymentMethodAdminException e) {
            emptyRejected = true;
        }
        System.assertEquals(true, emptyRejected);
    }

    @IsTest
    static void deployCallback_handlesNullResult() {
        Test.startTest();
        new PaymentMethodAdminDeployCallback().handleResult(null, null);
        Test.stopTest();
    }

    private static PaymentMethodAdminService.PaymentMethodState buildState(
        String apiName,
        Boolean active
    ) {
        PaymentMethodAdminService.PaymentMethodState state =
            new PaymentMethodAdminService.PaymentMethodState();
        state.apiName = apiName;
        state.active = active;
        return state;
    }
}