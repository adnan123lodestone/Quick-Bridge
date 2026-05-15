public with sharing class InvoiceQRService {
    
    public class QRWrapper {
        @AuraEnabled public String qrImageUrl { get; set; }
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
    }
    
    public class CustomQRException extends Exception {}

    public static String buildQRCodeImageUrl(String paymentUrl) {
        if (String.isBlank(paymentUrl)) {
            throw new CustomQRException('Payment URL is required to generate a QR code.');
        }
        return 'https://quickchart.io/qr?text=' + EncodingUtil.urlEncode(paymentUrl, 'UTF-8');
    }

    public static Id saveQRCodeFileForUrl(Id parentRecordId, String paymentUrl, String title) {
        if (parentRecordId == null) {
            throw new CustomQRException('A parent record is required to save the QR code file.');
        }
        String qrImageUrl = buildQRCodeImageUrl(paymentUrl);
        String fileTitle = String.isBlank(title) ? 'Payment QR Code' : title;
        String htmlBody =
            '<!doctype html><html><head><meta charset="UTF-8"><title>' + fileTitle.escapeHtml4() + '</title></head>' +
            '<body style="font-family: Arial, sans-serif; text-align: center; padding: 24px;">' +
            '<h1 style="font-size: 18px;">Payment QR Code</h1>' +
            '<p><img src="' + qrImageUrl.escapeHtml4() + '" alt="Payment QR Code" width="260" height="260"/></p>' +
            '<p><a href="' + paymentUrl.escapeHtml4() + '">Open payment invoice</a></p>' +
            '</body></html>';

        ContentVersion contentVersion = new ContentVersion(
            Title = fileTitle,
            PathOnClient = fileTitle.replaceAll('[^A-Za-z0-9_ -]', '') + '.html',
            VersionData = Blob.valueOf(htmlBody)
        );
        insert contentVersion;

        contentVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
            LIMIT 1
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = contentVersion.ContentDocumentId,
            LinkedEntityId = parentRecordId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        return contentVersion.ContentDocumentId;
    }
    
    @AuraEnabled(cacheable=false)
    public static QRWrapper generateAndSaveQRCode(Id invoiceId) {
        QRWrapper result = new QRWrapper();
        result.isSuccess = false;
        
        try {
            List<Invoice__c> invoices = [SELECT Id, Name, Order__c, Order__r.OrderNumber, Order__r.Payment_Gateway__c, Order__r.TotalAmount 
                                         FROM Invoice__c WHERE Id = :invoiceId LIMIT 1];
            
            if (invoices.isEmpty() || invoices[0].Order__c == null) {
                throw new CustomQRException('Error: This Invoice is not linked to an Order.');
            }
            
            Invoice__c inv = invoices[0];
            String gateway = inv.Order__r.Payment_Gateway__c != null ? inv.Order__r.Payment_Gateway__c.toLowerCase() : '';
            
            if (inv.Order__r.TotalAmount == null || inv.Order__r.TotalAmount <= 0) {
                throw new CustomQRException('Error: Order Total Amount is missing or invalid. Cannot generate payment link.');
            }
            Decimal amount = inv.Order__r.TotalAmount;
            String finalQrUrl = '';
            
            if (gateway.contains('stripe')) {
                finalQrUrl = generateStripeQR(inv.Order__r.OrderNumber, amount);
            }
            else if (gateway.contains('paypal')) {
                List<Portal_Payment_Transaction__c> trans = [SELECT Gateway_Transaction_Id__c FROM Portal_Payment_Transaction__c WHERE Order__c = :inv.Order__c ORDER BY CreatedDate DESC LIMIT 1];
                if(trans.isEmpty() || String.isBlank(trans[0].Gateway_Transaction_Id__c)){
                    throw new CustomQRException('Error: No PayPal Invoice ID found on Transactions.');
                }
                finalQrUrl = generatePayPalQR(trans[0].Gateway_Transaction_Id__c);
            }
            else if (gateway.contains('authorize')) {
                finalQrUrl = generateAuthorizeNetQR(amount);
            }
            else {
                throw new CustomQRException('Error: Unsupported Payment Gateway (' + gateway + ').');
            }
            
            String imageTag = '<img src="' + finalQrUrl + '" alt="Payment QR Code" width="200" height="200" />';
            inv.Payment_QR_Code__c = imageTag;
            update inv;
            
            result.qrImageUrl = finalQrUrl;
            result.isSuccess = true;
            result.message = 'Success! QR Code has been generated and saved to the Invoice record.';
            return result;
            
        } catch (Exception e) {
            System.debug('QR Generation Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            ErrorLogUtility.logException('Payment', 'InvoiceQRService.generateAndSaveQRCode', e, 'Invoice__c', invoiceId);
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }
    
    // ==========================================
    // STRIPE: Generate Checkout Link & Convert to QR
    // ==========================================
    private static String generateStripeQR(String orderNumber, Decimal amount) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Stripe_API/v1/checkout/sessions');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer {!$Credential.Stripe_Credentials.SecretKey}');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        Integer amountInCents = (Integer)(amount * 100);
        
        // Null check for Order Number
        String safeOrderName = String.isNotBlank(orderNumber) ? orderNumber : 'Payment';
        
        // Stripe Checkout payload (Quantity is REQUIRED)
        String body = 'mode=payment' +
            '&success_url=https://salesforce.com' +
            '&line_items[0][quantity]=1' +
            '&line_items[0][price_data][currency]=usd' +
            '&line_items[0][price_data][product_data][name]=Order+' + EncodingUtil.urlEncode(safeOrderName, 'UTF-8') +
            '&line_items[0][price_data][unit_amount]=' + amountInCents;
        req.setBody(body);
        
        HttpResponse response = http.send(req);
        if (response.getStatusCode() == 200) {
            Map<String, Object> resBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String paymentUrl = (String) resBody.get('url');
            
            // Convert Stripe URL to QR Image using secure API
            return 'https://quickchart.io/qr?text=' + EncodingUtil.urlEncode(paymentUrl, 'UTF-8');
        } else {
            System.debug('Stripe Error Response: ' + response.getBody());
            throw new CustomQRException('Stripe API Error: ' + response.getBody());
        }
    }
    
    // ==========================================
    // PAYPAL: Fetch Native QR Code Image (Base64)
    // ==========================================
    private static String generatePayPalQR(String paypalInvoiceId) {
        PayPal_Config__mdt config = PayPal_Config__mdt.getInstance('Default');
        String namedCredential = (config != null && config.UseSandbox__c) ? 'PayPal_API_Sandbox' : 'PayPal_API_Production';
        
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + namedCredential + '/v2/invoicing/invoices/' + paypalInvoiceId + '/qr-code');
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        
        HttpResponse response = http.send(req);
        if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
            Map<String, Object> resBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String base64Image = (String) resBody.get('image');
            return 'data:image/png;base64,' + base64Image;
        } else {
            throw new CustomQRException('PayPal API Error: Could not fetch QR Code.');
        }
    }
    
    // ==========================================
    // AUTHORIZE.NET: Generate Hosted Page Link & Convert to QR
    // ==========================================
    private static String generateAuthorizeNetQR(Decimal amount) {
        AuthorizeNet_Config__mdt config = AuthorizeNet_Config__mdt.getInstance('Default');
        String apiLoginId = (config != null && config.APILoginId__c != null) ? config.APILoginId__c : '';
        
        String jsonPayload = '{' +
            '"getHostedPaymentPageRequest": {' +
            '"merchantAuthentication": {' +
            '"name": "' + apiLoginId + '",' +
            '"transactionKey": "{!$Credential.Password}"' +
            '},' +
            '"transactionRequest": {' +
            '"transactionType": "authCaptureTransaction",' +
            '"amount": "' + amount + '"' +
            '},' +
            '"hostedPaymentSettings": {' +
            '"setting": [{' +
            '"settingName": "hostedPaymentReturnOptions",' +
            '"settingValue": "{\\"showReceipt\\": true, \\"url\\": \\"https://salesforce.com\\", \\"urlText\\": \\"Continue\\", \\"cancelUrl\\": \\"https://salesforce.com\\", \\"cancelUrlText\\": \\"Cancel\\"}"' +
        '}]' +
            '}' +
            '}' +
            '}';
        
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:AuthorizeNet/xml/v1/request.api');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonPayload);
        
        HttpResponse response = http.send(req);
        if (response.getStatusCode() == 200) {
            Map<String, Object> resBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            String token = (String) resBody.get('token');
            if(String.isNotBlank(token)) {
                String authNetUrl = 'https://accept.authorize.net/payment/payment?token=' + token;
                return 'https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=' + EncodingUtil.urlEncode(authNetUrl, 'UTF-8');
            }
        }
        throw new CustomQRException('Authorize.Net Error: Could not generate payment link.');
    }
}