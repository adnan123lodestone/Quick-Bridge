@RestResource(urlMapping='/meta-webhook/*')
global without sharing class MetaWebhookController {
    global class MetaWebhookResponse {
        public Boolean success;
        public String message;
        public Id workItemId;
    }

    @HttpGet
    global static String verify() {
        RestRequest request = RestContext.request;
        String mode = request == null ? null : request.params.get('hub.mode');
        String token = request == null ? null : request.params.get('hub.verify_token');
        String challenge = request == null ? null : request.params.get('hub.challenge');
        try {
            if (RestContext.response == null) {
                RestContext.response = new RestResponse();
            }
            RestContext.response.statusCode = 200;
            return MetaWebhookVerifier.verifyChallenge(mode, token, challenge);
        } catch (Exception e) {
            if (RestContext.response == null) {
                RestContext.response = new RestResponse();
            }
            RestContext.response.statusCode = 403;
            return 'Forbidden';
        }
    }

    @HttpPost
    global static MetaWebhookResponse receive() {
        MetaWebhookResponse response = new MetaWebhookResponse();
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }
        try {
            RestRequest request = RestContext.request;
            String body = request == null || request.requestBody == null ? null : request.requestBody.toString();
            if (String.isBlank(body)) {
                RestContext.response.statusCode = 400;
                response.success = false;
                response.message = 'Meta webhook payload is required.';
                return response;
            }
            MetaWebhookVerifier.requireValidSignature(body, request);
            IntegrationWorkRequest workRequest = new IntegrationWorkRequest();
            workRequest.integration = 'Meta';
            workRequest.operation = 'WebhookEvent';
            workRequest.sourceObject = 'MetaWebhook';
            workRequest.sourceRecordId = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(body)));
            workRequest.lockKey = 'MetaWebhook:' + workRequest.sourceRecordId;
            workRequest.payloadJson = body;
            response.workItemId = IntegrationWorkService.enqueue(workRequest);
            response.success = true;
            response.message = 'Meta webhook accepted.';
            RestContext.response.statusCode = 200;
            return response;
        } catch (MetaWebhookVerifier.MetaWebhookVerificationException e) {
            RestContext.response.statusCode = 401;
            response.success = false;
            response.message = e.getMessage();
            return response;
        } catch (Exception e) {
            RestContext.response.statusCode = 500;
            response.success = false;
            response.message = 'Meta webhook could not be accepted.';
            ErrorLogUtility.logException('Meta', 'MetaWebhookController.receive', e, null, null);
            return response;
        }
    }
}