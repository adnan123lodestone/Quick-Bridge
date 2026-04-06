@IsTest
private class PaymentMethodAdminRestResourceTest {
    private class FakeUpdater implements PaymentMethodAdminService.MetadataUpdater {
        public String upsertProviderStates(Map<String, Boolean> providerStates) {
            return '0AfREST000000001';
        }
    }

    @IsTest
    static void deactivatePaymentMethods_returnsAcceptedResponse() {
        PaymentMethodAdminService.testUpdater = new FakeUpdater();

        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/payment-method-admin';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(
            '{"clientOrgName":"Quickbridge","paymentMethodStates":[{"apiName":"authorizenet","active":true},{"apiName":"stripe","active":false}]}'
        );

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        String responseBody = PaymentMethodAdminRestResource.deactivatePaymentMethods();
        Test.stopTest();

        PaymentMethodAdminService.DeactivateResponse response =
            (PaymentMethodAdminService.DeactivateResponse) JSON.deserialize(
                responseBody,
                PaymentMethodAdminService.DeactivateResponse.class
            );

        System.assertEquals(202, RestContext.response.statusCode);
        System.assertEquals(true, response.success);
        System.assertEquals('0AfREST000000001', response.deploymentId);
        System.assertEquals(2, response.acceptedMethods.size());
    }

    @IsTest
    static void deactivatePaymentMethods_returnsBadRequestForEmptyPayload() {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/payment-method-admin';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{}');

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        String responseBody = PaymentMethodAdminRestResource.deactivatePaymentMethods();
        Test.stopTest();

        PaymentMethodAdminService.DeactivateResponse response =
            (PaymentMethodAdminService.DeactivateResponse) JSON.deserialize(
                responseBody,
                PaymentMethodAdminService.DeactivateResponse.class
            );

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals('At least one payment method state must be provided.', response.message);
    }

    @IsTest
    static void deactivatePaymentMethods_returnsBadRequestForMalformedJson() {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/payment-method-admin';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{"paymentMethodStates":[');

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        String responseBody = PaymentMethodAdminRestResource.deactivatePaymentMethods();
        Test.stopTest();

        PaymentMethodAdminService.DeactivateResponse response =
            (PaymentMethodAdminService.DeactivateResponse) JSON.deserialize(
                responseBody,
                PaymentMethodAdminService.DeactivateResponse.class
            );

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals('The request body could not be parsed.', response.message);
    }

    @IsTest
    static void deactivatePaymentMethods_requiresRequestBody() {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/payment-method-admin';
        request.httpMethod = 'POST';

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        String responseBody = PaymentMethodAdminRestResource.deactivatePaymentMethods();
        Test.stopTest();

        PaymentMethodAdminService.DeactivateResponse response =
            (PaymentMethodAdminService.DeactivateResponse) JSON.deserialize(
                responseBody,
                PaymentMethodAdminService.DeactivateResponse.class
            );

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals('The request body must include payment method states.', response.message);
    }
}