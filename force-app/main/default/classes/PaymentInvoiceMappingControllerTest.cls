@IsTest
private class PaymentInvoiceMappingControllerTest {
    @IsTest
    static void lookupHelpersReturnExpectedDefaults() {
        Test.startTest();
        List<PaymentInvoiceMappingController.FieldOption> customerLookups =
            PaymentInvoiceMappingController.getLookupFields('Order', 'Account');
        List<PaymentInvoiceMappingController.FieldOption> invoiceLookups =
            PaymentInvoiceMappingController.getLookupFields('Invoice__c', 'Order');
        List<PaymentInvoiceMappingController.FieldOption> transactionLookups =
            PaymentInvoiceMappingController.getLookupFields('Portal_Payment_Transaction__c', 'Order');
        List<PaymentInvoiceMappingController.FieldOption> requestFields =
            PaymentInvoiceMappingController.getInvoiceRequestFields();
        List<PaymentInvoiceMappingController.FieldOption> stripeFields =
            PaymentInvoiceMappingController.getGatewayTransactionFields('stripe');
        List<PaymentInvoiceMappingController.FieldOption> invoiceObjects =
            PaymentInvoiceMappingController.getObjectsWithLookupTo('Order');
        Test.stopTest();

        System.assert(containsValue(customerLookups, 'AccountId'), 'Order should expose AccountId as a customer lookup.');
        System.assert(containsValueOrSuffix(invoiceLookups, 'Order__c'), 'Invoice__c should expose Order__c as a source lookup.');
        System.assert(containsValueOrSuffix(transactionLookups, 'Order__c'), 'Portal_Payment_Transaction__c should expose Order__c as a source lookup.');
        System.assert(containsValue(requestFields, 'amount'), 'Invoice request field options should include amount.');
        System.assert(containsValue(stripeFields, 'gatewayTransactionId'), 'Stripe transaction field options should include transaction id.');
        System.assert(!invoiceObjects.isEmpty(), 'Lookup-filtered target objects should be available for Order.');
    }

    @IsTest
    static void saveGatewayMappingConfigValidatesStandardStripeConfig() {
        String payload = JSON.serialize(new Map<String, Object>{
            'gateway' => 'stripe',
            'sourceObject' => 'Order',
            'sourceCustomerLookupField' => 'AccountId',
            'invoiceObject' => 'Invoice__c',
            'invoiceSourceLookupField' => 'Order__c',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'Order__c',
            'sourceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'TotalAmount', 'targetField' => 'amount' }
            },
            'invoiceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'amount', 'targetField' => 'Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'hostedInvoiceUrl', 'targetField' => 'Stripe_Invoice_Link__c' },
                new Map<String, Object>{ 'sourceField' => 'referenceNumber', 'targetField' => 'Reference_number__c' },
                new Map<String, Object>{ 'sourceField' => 'status', 'targetField' => 'Status__c' },
                new Map<String, Object>{ 'sourceField' => 'invoiceDate', 'targetField' => 'Invoice_Date__c' }
            },
            'transactionMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'gatewayEventId', 'targetField' => 'Gateway_Event_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayEventType', 'targetField' => 'Gateway_Event_Type__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayAmount', 'targetField' => 'Gateway_Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayReferenceNumber', 'targetField' => 'Gateway_Reference_Number__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayTransactionId', 'targetField' => 'Gateway_Transaction_Id__c' }
            }
        });

        Test.startTest();
        String result = PaymentInvoiceMappingController.saveGatewayMappingConfig(payload);
        Test.stopTest();

        System.assertEquals('Mappings validated successfully.', result);
    }

    @IsTest
    static void saveGatewayMappingConfigRejectsMissingTargetLookup() {
        String payload = JSON.serialize(new Map<String, Object>{
            'gateway' => 'stripe',
            'sourceObject' => 'Order',
            'sourceCustomerLookupField' => 'AccountId',
            'sourceEmailField' => 'Account.Name',
            'invoiceObject' => 'Account',
            'invoiceSourceLookupField' => 'OwnerId',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'Order__c'
        });

        Test.startTest();
        try {
            PaymentInvoiceMappingController.saveGatewayMappingConfig(payload);
            System.assert(false, 'Expected validation to fail.');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
        Test.stopTest();
    }

    @IsTest
    static void readMethodsHandleStripeDefaults() {
        Test.startTest();
        PaymentInvoiceMappingController.GatewayMappingConfig config =
            PaymentInvoiceMappingController.getGatewayMappingConfig('stripe');
        List<PaymentInvoiceMappingController.FieldOption> sourceObjects =
            PaymentInvoiceMappingController.getEligibleSourceObjects();
        List<PaymentInvoiceMappingController.FieldOption> createableObjects =
            PaymentInvoiceMappingController.getCreateableObjects();
        List<PaymentInvoiceMappingController.FieldOption> orderFields =
            PaymentInvoiceMappingController.getObjectFields('Order');
        List<PaymentInvoiceMappingController.FieldOption> emailFields =
            PaymentInvoiceMappingController.getEmailFieldOptions('Order', 'AccountId');
        Test.stopTest();

        System.assertEquals('stripe', config.gateway);
        System.assertNotEquals(null, sourceObjects);
        System.assert(!createableObjects.isEmpty(), 'Createable object options should be available.');
        System.assert(containsValue(orderFields, 'TotalAmount'), 'Order fields should include TotalAmount.');
        System.assert(!emailFields.isEmpty(), 'Email field options should be available.');
    }

    @IsTest
    static void saveGatewayMappingConfigRejectsDuplicateRows() {
        String payload = JSON.serialize(new Map<String, Object>{
            'gateway' => 'stripe',
            'sourceObject' => 'Order',
            'sourceCustomerLookupField' => 'AccountId',
            'sourceEmailField' => 'Account.Name',
            'invoiceObject' => 'Invoice__c',
            'invoiceSourceLookupField' => 'Order__c',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'Order__c',
            'invoiceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'TotalAmount', 'targetField' => 'Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'TotalAmount', 'targetField' => 'Reference_number__c' }
            }
        });

        Test.startTest();
        try {
            PaymentInvoiceMappingController.saveGatewayMappingConfig(payload);
            System.assert(false, 'Expected duplicate source validation to fail.');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
        Test.stopTest();
    }

    private static Boolean containsValue(List<PaymentInvoiceMappingController.FieldOption> options, String expectedValue) {
        for (PaymentInvoiceMappingController.FieldOption option : options) {
            if (option.value == expectedValue) {
                return true;
            }
        }
        return false;
    }

    private static Boolean containsValueOrSuffix(List<PaymentInvoiceMappingController.FieldOption> options, String expectedSuffix) {
        for (PaymentInvoiceMappingController.FieldOption option : options) {
            if (option.value == expectedSuffix || (option.value != null && option.value.endsWith('__' + expectedSuffix))) {
                return true;
            }
        }
        return false;
    }
}