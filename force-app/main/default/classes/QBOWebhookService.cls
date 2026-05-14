@RestResource(urlMapping='/qbo/webhook/*')
global without sharing class QBOWebhookService {
    
    @HttpPost
    global static void handleIncomingWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            // Get the payload and signature from the incoming request
            String requestBody = req.requestBody.toString();
            String intuitSignature = req.headers.get('intuit-signature');
            
            // Fetch Verifier Token dynamically from Custom Metadata
            List<Quickbridge_Config__mdt> configs = [SELECT QuickBooks_Verifier_Token__c FROM Quickbridge_Config__mdt WHERE Label = 'QuickBooks' LIMIT 1];
            String verifierToken = configs.isEmpty() ? '' : configs[0].QuickBooks_Verifier_Token__c;
            
            // SECURITY CHECK: Verify Intuit Signature
            if (String.isNotBlank(verifierToken)) {
                Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(requestBody), Blob.valueOf(verifierToken));
                String expectedSignature = EncodingUtil.base64Encode(mac);
                
                if (intuitSignature != expectedSignature) {
                    System.debug('SECURITY ALERT: Invalid Webhook Signature Detected!');
                    ErrorLogUtility.logCalloutFailure(
                        'QuickBooks',
                        'QBOWebhookService.handleIncomingWebhook',
                        'Invalid QuickBooks webhook signature.',
                        401,
                        null,
                        null
                    );
                    res.statusCode = 401; // Unauthorized Request (Rejecting the fake payload)
                    return;
                }
            } else {
                System.debug('WARNING: Verifier Token not found in Metadata. Proceeding without verification.');
            }
            
            // Parse the JSON Payload to extract Event Notifications
            Map<String, Object> payload = (Map<String, Object>)JSON.deserializeUntyped(requestBody);
            List<Object> eventNotifications = (List<Object>)payload.get('eventNotifications');
            
            Set<String> invoiceIdsToFetch = new Set<String>();
            
            if (eventNotifications != null) {
                for (Object notifObj : eventNotifications) {
                    Map<String, Object> notification = (Map<String, Object>)notifObj;
                    Map<String, Object> dataChangeEvent = (Map<String, Object>)notification.get('dataChangeEvent');
                    
                    if (dataChangeEvent != null && dataChangeEvent.containsKey('entities')) {
                        List<Object> entities = (List<Object>)dataChangeEvent.get('entities');
                        
                        // Loop through entities and grab IDs for 'Invoice' Creates/Updates
                        for (Object entityObj : entities) {
                            Map<String, Object> entity = (Map<String, Object>)entityObj;
                            String entityName = (String)entity.get('name');
                            String operation = (String)entity.get('operation');
                            String entityId = (String)entity.get('id');
                            
                            // Check if the event is for an Invoice
                            if (entityName == 'Invoice' && (operation == 'Create' || operation == 'Update')) {
                                invoiceIdsToFetch.add(entityId);
                            }
                        }
                    }
                }
            }
            
            // Send the collected IDs to the Background Queueable Job
            if (!invoiceIdsToFetch.isEmpty()) {
                System.enqueueJob(new QBOInvoiceSyncQueueable(invoiceIdsToFetch));
            }
            
            // Return 200 OK immediately so QBO knows we received the webhook successfully
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('Success');
            
        } catch (Exception e) {
            System.debug('Webhook Error: ' + e.getMessage() + ' at Line ' + e.getLineNumber());
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBOWebhookService.handleIncomingWebhook',
                e,
                null,
                null
            );
            res.statusCode = 500;
        }
    }
}