@RestResource(urlMapping='/payment-method-admin/*')
global without sharing class PaymentMethodAdminRestResource {
    @HttpPost
    global static String deactivatePaymentMethods() {
        RestResponse restResponse = RestContext.response;
        restResponse.addHeader('Content-Type', 'application/json');

        try {
            String requestBody = RestContext.request == null || RestContext.request.requestBody == null
                ? null
                : RestContext.request.requestBody.toString();

            if (String.isBlank(requestBody)) {
                throw new PaymentMethodAdminService.PaymentMethodAdminException(
                    'The request body must include payment method states.'
                );
            }

            PaymentMethodAdminService.DeactivateRequest request =
                (PaymentMethodAdminService.DeactivateRequest) JSON.deserialize(
                    requestBody,
                    PaymentMethodAdminService.DeactivateRequest.class
                );

            PaymentMethodAdminService.DeactivateResponse response =
                PaymentMethodAdminService.deactivatePaymentMethods(request);
            restResponse.statusCode = 202;
            return JSON.serialize(response);
        } catch (PaymentMethodAdminService.PaymentMethodAdminException e) {
            restResponse.statusCode = 400;
            ErrorLogUtility.logException(
                'QuickBridge',
                'PaymentMethodAdminRestResource.deactivatePaymentMethods',
                e,
                null,
                null
            );
            return JSON.serialize(buildErrorResponse(e.getMessage()));
        } catch (JSONException e) {
            restResponse.statusCode = 400;
            ErrorLogUtility.logException(
                'QuickBridge',
                'PaymentMethodAdminRestResource.deactivatePaymentMethods.parse',
                e,
                null,
                null
            );
            return JSON.serialize(buildErrorResponse('The request body could not be parsed.'));
        } catch (Exception e) {
            restResponse.statusCode = 500;
            ErrorLogUtility.logException(
                'QuickBridge',
                'PaymentMethodAdminRestResource.deactivatePaymentMethods.unexpected',
                e,
                null,
                null
            );
            return JSON.serialize(
                buildErrorResponse('Payment method sync failed: ' + e.getMessage())
            );
        }
    }

    private static PaymentMethodAdminService.DeactivateResponse buildErrorResponse(String message) {
        PaymentMethodAdminService.DeactivateResponse response =
            new PaymentMethodAdminService.DeactivateResponse();
        response.success = false;
        response.message = message;
        response.acceptedMethods = new List<String>();
        response.unsupportedMethods = new List<String>();
        response.deploymentId = null;
        return response;
    }
}