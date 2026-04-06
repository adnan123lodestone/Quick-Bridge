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