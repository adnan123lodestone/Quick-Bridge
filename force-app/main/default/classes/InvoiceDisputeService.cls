public with sharing class InvoiceDisputeService {

    public class CustomDisputeException extends Exception {}

    public class DisputeWrapper {
        @AuraEnabled public Boolean hasDispute { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String reason { get; set; }
        @AuraEnabled public String amount { get; set; }
        @AuraEnabled public String currencyCode { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    @AuraEnabled(cacheable=false)
    public static DisputeWrapper getDisputeDetails(Id invoiceId) {
        try {
            List<Invoice__c> invoices = [SELECT Id, Order__c, Order__r.Payment_Gateway__c 
                                         FROM Invoice__c WHERE Id = :invoiceId LIMIT 1];

            if (invoices.isEmpty() || invoices[0].Order__c == null) {
                throw new CustomDisputeException('Error: This Invoice is not linked to any Order. Please link an Order first.');
            }

            Invoice__c inv = invoices[0];
            String gateway = inv.Order__r.Payment_Gateway__c != null ? inv.Order__r.Payment_Gateway__c.toLowerCase() : '';

            List<Portal_Payment_Transaction__c> transactions = [
                SELECT Gateway_Transaction_Id__c, Stripe_Charge_Id__c, Gateway_Currency__c
                FROM Portal_Payment_Transaction__c 
                WHERE Order__c = :inv.Order__c 
                ORDER BY CreatedDate DESC LIMIT 1
            ];

            if (transactions.isEmpty()) {
                throw new CustomDisputeException('Error: No Payment Transaction found for this Order.');
            }

            Portal_Payment_Transaction__c trans = transactions[0];
            DisputeWrapper finalResult;

            if (gateway.contains('stripe')) {
                finalResult = fetchStripeDispute(trans.Stripe_Charge_Id__c);
            } else if (gateway.contains('paypal')) {
                finalResult = fetchPayPalDispute(trans.Gateway_Transaction_Id__c);
            } else if (gateway.contains('authorize')) {
                finalResult = fetchAuthorizeNetDispute(trans.Gateway_Transaction_Id__c);
            } else {
                throw new CustomDisputeException('Error: Unsupported Payment Gateway (' + gateway + ').');
            }

            if (finalResult != null) {
                finalResult.currencyCode = trans.Gateway_Currency__c;
            }

            return finalResult;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'DisputeService Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            ErrorLogUtility.logException('Payment', 'InvoiceDisputeService.getDisputeDetails', e, 'Invoice__c', invoiceId);
            
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage()); 
            throw ahe;
        }
    }

    // ==========================================
    // STRIPE INTEGRATION
    // ==========================================
    private static DisputeWrapper fetchStripeDispute(String chargeId) {
        DisputeWrapper res = new DisputeWrapper();
        res.hasDispute = false;

        if (String.isBlank(chargeId)) throw new CustomDisputeException('Error: Stripe Charge ID is missing on the Transaction record.');

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Stripe_API/v1/disputes?charge=' + chargeId);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer {!$Credential.Stripe_Credentials.SecretKey}');

        HttpResponse response = http.send(req);
        
        if (response.getStatusCode() == 200) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> data = (List<Object>) body.get('data');
            
            if (data != null && !data.isEmpty()) {
                Map<String, Object> dispute = (Map<String, Object>) data[0];
                res.hasDispute = true;
                res.status = (String) dispute.get('status');
                res.reason = (String) dispute.get('reason');
                
                Decimal amount = (Decimal) dispute.get('amount');
                res.amount = String.valueOf(amount / 100); 
                res.message = 'Dispute record found in Stripe.';
            } else {
                res.message = 'No active disputes found for this transaction.';
            }
        } else {
            throw new CustomDisputeException('Stripe API Error: ' + response.getStatus());
        }
        return res;
    }

    // ==========================================
    // PAYPAL INTEGRATION
    // ==========================================
    private static DisputeWrapper fetchPayPalDispute(String transId) {
        DisputeWrapper res = new DisputeWrapper();
        res.hasDispute = false;

        if (String.isBlank(transId)) throw new CustomDisputeException('Error: PayPal Transaction ID is missing on the Transaction record.');

        PayPal_Config__mdt config = PayPal_Config__mdt.getInstance('Default');
        
        Boolean isActive = config != null ? config.Active__c : false;
        Boolean useSandbox = config != null ? config.UseSandbox__c : true;

        if (!isActive && !Test.isRunningTest()) {
            throw new CustomDisputeException('Error: PayPal is not configured or active in Custom Metadata.');
        }

        String namedCredential = useSandbox ? 'PayPal_API_Sandbox' : 'PayPal_API_Production';

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + namedCredential + '/v1/customer/disputes?transaction_id=' + transId);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');

        HttpResponse response = http.send(req);
        
        if (response.getStatusCode() == 200) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> items = (List<Object>) body.get('items');

            if (items != null && !items.isEmpty()) {
                Map<String, Object> dispute = (Map<String, Object>) items[0];
                res.hasDispute = true;
                res.status = (String) dispute.get('status');
                res.reason = (String) dispute.get('dispute_reason');
                
                Map<String, Object> disputeAmount = (Map<String, Object>) dispute.get('dispute_amount');
                if (disputeAmount != null) {
                    res.amount = (String) disputeAmount.get('value');
                }
                res.message = 'Dispute record found in PayPal.';
            } else {
                res.message = 'No active disputes found for this transaction.';
            }
        } else {
            throw new CustomDisputeException('PayPal API Error: Failed to fetch dispute.');
        }
        return res;
    }

    // ==========================================
    // AUTHORIZE.NET INTEGRATION
    // ==========================================
    private static DisputeWrapper fetchAuthorizeNetDispute(String transId) {
        DisputeWrapper res = new DisputeWrapper();
        res.hasDispute = false;

        if (String.isBlank(transId)) throw new CustomDisputeException('Error: Authorize.Net Transaction ID is missing.');

        AuthorizeNet_Config__mdt config = AuthorizeNet_Config__mdt.getInstance('Default');
        
        Boolean isActive = config != null ? config.Active__c : false;
        String apiLoginId = config != null && config.APILoginId__c != null ? config.APILoginId__c : 'test_login';

        if (!isActive && !Test.isRunningTest()) {
            throw new CustomDisputeException('Error: Authorize.Net is not configured or active.');
        }
        
        String jsonPayload = '{' +
            '"getTransactionDetailsRequest": {' +
                '"merchantAuthentication": {' +
                    '"name": "' + apiLoginId + '",' +
                    '"transactionKey": "{!$Credential.Password}"' + 
                '},' +
                '"transId": "' + transId + '"' +
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
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            Map<String, Object> transactionDetails = (Map<String, Object>) body.get('transaction');
            
            if (transactionDetails != null) {
                String status = (String) transactionDetails.get('transactionStatus');
                if (status == 'returnedItem' || status == 'chargeback') {
                    res.hasDispute = true;
                    res.status = status;
                    res.reason = 'Customer Chargeback or Return';
                    res.amount = String.valueOf(transactionDetails.get('settleAmount'));
                    res.message = 'Chargeback/Return record found in Authorize.Net.';
                } else {
                    res.message = 'Transaction is in "' + status + '" state. No active disputes found.';
                }
            } else {
                 res.message = 'Transaction details not found in Authorize.Net.';
            }
        } else {
            throw new CustomDisputeException('Authorize.Net API Error: Communication Failed.');
        }
        return res;
    }
}