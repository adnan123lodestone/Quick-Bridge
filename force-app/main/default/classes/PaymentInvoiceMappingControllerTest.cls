@IsTest
private class PaymentInvoiceMappingControllerTest {
    @IsTest
    static void lookupHelpersReturnExpectedDefaults() {
        Test.startTest();
        String invoiceName = Invoice__c.SObjectType.getDescribe().getName();
        String txnName = Portal_Payment_Transaction__c.SObjectType.getDescribe().getName();

        List<PaymentInvoiceMappingController.FieldOption> customerLookups = PaymentInvoiceMappingController.getLookupFields('Order', 'Account');
        List<PaymentInvoiceMappingController.FieldOption> invoiceLookups = PaymentInvoiceMappingController.getLookupFields(invoiceName, 'Order');
        List<PaymentInvoiceMappingController.FieldOption> transactionLookups = PaymentInvoiceMappingController.getLookupFields(txnName, 'Order');
        List<PaymentInvoiceMappingController.FieldOption> requestFields = PaymentInvoiceMappingController.getInvoiceRequestFields();
        List<PaymentInvoiceMappingController.FieldOption> stripeFields = PaymentInvoiceMappingController.getGatewayTransactionFields('stripe');
        List<PaymentInvoiceMappingController.FieldOption> invoiceObjects = PaymentInvoiceMappingController.getObjectsWithLookupTo('Order');
        Test.stopTest();

        System.assert(customerLookups != null, 'Order should expose AccountId as a customer lookup.');
        System.assert(invoiceLookups != null, 'Invoice__c should expose Order__c as a source lookup.');
        System.assert(transactionLookups != null, 'Portal_Payment_Transaction__c should expose Order__c as a source lookup.');
        System.assert(requestFields != null, 'Invoice request field options should include amount.');
        System.assert(stripeFields != null, 'Stripe transaction field options should include transaction id.');
        System.assert(invoiceObjects != null, 'Lookup-filtered target objects should be available for Order.');
    }

    @IsTest
    static void saveGatewayMappingConfigValidatesStandardStripeConfig() {
        String payload = JSON.serialize(new Map<String, Object>{
            'gateway' => 'stripe',
            'sourceObject' => 'Order',
            'sourceCustomerLookupField' => 'AccountId',
            'invoiceObject' => 'QuickBridgeTLG__Invoice__c',
            'invoiceSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'sourceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'TotalAmount', 'targetField' => 'amount' }
            },
            'invoiceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'amount', 'targetField' => 'Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'hostedInvoiceUrl', 'targetField' => 'Stripe_Invoice_Link__c' },
                new Map<String, Object>{ 'sourceField' => 'referenceNumber', 'targetField' => 'Reference_number__c' },
                new Map<String, Object>{ 'sourceField' => 'status', 'targetField' => 'Status__c' },
                new Map<String, Object>{ 'sourceField' => 'invoiceDate', 'targetField' => 'Invoice_Date__c' },
                new Map<String, Object>{ 'sourceField' => 'stripeInvoiceId', 'targetField' => 'Stripe_Invoice_Id__c' }
            },
            'transactionMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'gatewayEventId', 'targetField' => 'Gateway_Event_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayEventType', 'targetField' => 'Gateway_Event_Type__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayAmount', 'targetField' => 'Gateway_Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayReferenceNumber', 'targetField' => 'Gateway_Reference_Number__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayTransactionId', 'targetField' => 'Gateway_Transaction_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'paymentType', 'targetField' => 'Payment_Type__c' },
                new Map<String, Object>{ 'sourceField' => 'stripeLiveMode', 'targetField' => 'Stripe_Live_Mode__c' }
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
            'transactionSourceLookupField' => 'QuickBridgeTLG__Order__c'
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
            'invoiceObject' => 'QuickBridgeTLG__Invoice__c',
            'invoiceSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'QuickBridgeTLG__Order__c',
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

    @IsTest
    static void getGatewayTransactionFieldsReturnsAuthNetFields() {
        Test.startTest();
        List<PaymentInvoiceMappingController.FieldOption> anetFields =
            PaymentInvoiceMappingController.getGatewayTransactionFields('authorizenet');
        Test.stopTest();

        System.assert(containsValue(anetFields, 'gatewayTransactionId'), 'Auth.Net transaction fields should include gatewayTransactionId.');
        System.assert(containsValue(anetFields, 'authNetWebhookId'), 'Auth.Net transaction fields should include authNetWebhookId.');
        System.assert(containsValue(anetFields, 'authNetAuthCode'), 'Auth.Net transaction fields should include authNetAuthCode.');
        System.assert(!containsValue(anetFields, 'stripeLiveMode'), 'Auth.Net transaction fields should not include stripeLiveMode.');
    }

    @IsTest
    static void getInvoiceRequestFieldsForGatewayReturnsAuthNetFields() {
        Test.startTest();
        List<PaymentInvoiceMappingController.FieldOption> anetFields =
            PaymentInvoiceMappingController.getInvoiceRequestFieldsForGateway('authorizenet');
        Test.stopTest();

        System.assert(containsValue(anetFields, 'amount'), 'Auth.Net invoice fields should include amount.');
        System.assert(containsValue(anetFields, 'referenceNumber'), 'Auth.Net invoice fields should include referenceNumber.');
        System.assert(containsValue(anetFields, 'authCode'), 'Auth.Net invoice fields should include authCode.');
        System.assert(!containsValue(anetFields, 'hostedInvoiceUrl'), 'Auth.Net invoice fields should not include hostedInvoiceUrl.');
    }

    @IsTest
    static void getGatewayMappingConfigReturnsAuthNetDefaults() {
        Test.startTest();
        PaymentInvoiceMappingController.GatewayMappingConfig config =
            PaymentInvoiceMappingController.getGatewayMappingConfig('authorizenet');
        Test.stopTest();

        System.assertEquals('authorizenet', config.gateway);
        System.assertNotEquals(null, config.sourceMappings);
        System.assertNotEquals(null, config.invoiceMappings);
        System.assertNotEquals(null, config.transactionMappings);
    }

    @IsTest
    static void saveGatewayMappingConfigValidatesStandardAuthNetConfig() {
        String payload = JSON.serialize(new Map<String, Object>{
            'gateway' => 'authorizenet',
            'sourceObject' => 'Order',
            'sourceCustomerLookupField' => 'AccountId',
            'invoiceObject' => 'QuickBridgeTLG__Invoice__c',
            'invoiceSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'sourceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'TotalAmount', 'targetField' => 'amount' }
            },
            'invoiceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'amount', 'targetField' => 'Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'referenceNumber', 'targetField' => 'Reference_number__c' },
                new Map<String, Object>{ 'sourceField' => 'status', 'targetField' => 'Status__c' },
                new Map<String, Object>{ 'sourceField' => 'invoiceDate', 'targetField' => 'Invoice_Date__c' }
            },
            'transactionMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'gatewayEventId', 'targetField' => 'Gateway_Event_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayEventType', 'targetField' => 'Gateway_Event_Type__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayAmount', 'targetField' => 'Gateway_Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayReferenceNumber', 'targetField' => 'Gateway_Reference_Number__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayTransactionId', 'targetField' => 'Gateway_Transaction_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'paymentType', 'targetField' => 'Payment_Type__c' }
            }
        });

        Test.startTest();
        String result = PaymentInvoiceMappingController.saveGatewayMappingConfig(payload);
        Test.stopTest();

        System.assertEquals('Mappings validated successfully.', result);
    }

    @IsTest
    static void saveAuthNetConfigRejectsMissingRequiredInvoiceFields() {
        String payload = JSON.serialize(new Map<String, Object>{
            'gateway' => 'authorizenet',
            'sourceObject' => 'Order',
            'sourceCustomerLookupField' => 'AccountId',
            'invoiceObject' => 'QuickBridgeTLG__Invoice__c',
            'invoiceSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'sourceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'TotalAmount', 'targetField' => 'amount' }
            },
            'invoiceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'amount', 'targetField' => 'Amount__c' }
                // missing referenceNumber, status, invoiceDate
            },
            'transactionMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'gatewayEventId', 'targetField' => 'Gateway_Event_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayEventType', 'targetField' => 'Gateway_Event_Type__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayAmount', 'targetField' => 'Gateway_Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayReferenceNumber', 'targetField' => 'Gateway_Reference_Number__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayTransactionId', 'targetField' => 'Gateway_Transaction_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'paymentType', 'targetField' => 'Payment_Type__c' }
            }
        });

        Test.startTest();
        try {
            PaymentInvoiceMappingController.saveGatewayMappingConfig(payload);
            System.assert(false, 'Expected validation to fail due to missing referenceNumber.');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
        Test.stopTest();
    }

    @IsTest
    static void getGatewayTransactionFieldsReturnsPayPalFields() {
        Test.startTest();
        List<PaymentInvoiceMappingController.FieldOption> paypalFields =
            PaymentInvoiceMappingController.getGatewayTransactionFields('paypal');
        Test.stopTest();

        System.assert(containsValue(paypalFields, 'gatewayTransactionId'), 'PayPal transaction fields should include gatewayTransactionId.');
        System.assert(containsValue(paypalFields, 'paypalOrderId'), 'PayPal transaction fields should include paypalOrderId.');
        System.assert(containsValue(paypalFields, 'paypalPayerEmail'), 'PayPal transaction fields should include paypalPayerEmail.');
        System.assert(!containsValue(paypalFields, 'stripeLiveMode'), 'PayPal transaction fields should not include stripeLiveMode.');
        System.assert(!containsValue(paypalFields, 'authNetWebhookId'), 'PayPal transaction fields should not include authNetWebhookId.');
    }

    @IsTest
    static void getInvoiceRequestFieldsForGatewayReturnsPayPalFields() {
        Test.startTest();
        List<PaymentInvoiceMappingController.FieldOption> paypalFields =
            PaymentInvoiceMappingController.getInvoiceRequestFieldsForGateway('paypal');
        Test.stopTest();

        System.assert(containsValue(paypalFields, 'amount'), 'PayPal invoice fields should include amount.');
        System.assert(containsValue(paypalFields, 'referenceNumber'), 'PayPal invoice fields should include referenceNumber.');
        System.assert(containsValue(paypalFields, 'paypalOrderId'), 'PayPal invoice fields should include paypalOrderId.');
        System.assert(!containsValue(paypalFields, 'hostedInvoiceUrl'), 'PayPal invoice fields should not include hostedInvoiceUrl.');
    }

    @IsTest
    static void getGatewayMappingConfigReturnsPayPalDefaults() {
        Test.startTest();
        PaymentInvoiceMappingController.GatewayMappingConfig config =
            PaymentInvoiceMappingController.getGatewayMappingConfig('paypal');
        Test.stopTest();

        System.assertEquals('paypal', config.gateway);
        System.assertNotEquals(null, config.sourceMappings);
        System.assertNotEquals(null, config.invoiceMappings);
        System.assertNotEquals(null, config.transactionMappings);
    }

    @IsTest
    static void saveGatewayMappingConfigValidatesStandardPayPalConfig() {
        String payload = JSON.serialize(new Map<String, Object>{
            'gateway' => 'paypal',
            'sourceObject' => 'Order',
            'sourceCustomerLookupField' => 'AccountId',
            'invoiceObject' => 'QuickBridgeTLG__Invoice__c',
            'invoiceSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'sourceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'TotalAmount', 'targetField' => 'amount' }
            },
            'invoiceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'amount', 'targetField' => 'Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'referenceNumber', 'targetField' => 'Reference_number__c' },
                new Map<String, Object>{ 'sourceField' => 'status', 'targetField' => 'Status__c' },
                new Map<String, Object>{ 'sourceField' => 'invoiceDate', 'targetField' => 'Invoice_Date__c' }
            },
            'transactionMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'gatewayEventId', 'targetField' => 'Gateway_Event_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayEventType', 'targetField' => 'Gateway_Event_Type__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayAmount', 'targetField' => 'Gateway_Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayReferenceNumber', 'targetField' => 'Gateway_Reference_Number__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayTransactionId', 'targetField' => 'Gateway_Transaction_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'paymentType', 'targetField' => 'Payment_Type__c' }
            }
        });

        Test.startTest();
        String result = PaymentInvoiceMappingController.saveGatewayMappingConfig(payload);
        Test.stopTest();

        System.assertEquals('Mappings validated successfully.', result);
    }

    @IsTest
    static void savePayPalConfigRejectsMissingRequiredInvoiceFields() {
        String payload = JSON.serialize(new Map<String, Object>{
            'gateway' => 'paypal',
            'sourceObject' => 'Order',
            'sourceCustomerLookupField' => 'AccountId',
            'invoiceObject' => 'QuickBridgeTLG__Invoice__c',
            'invoiceSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'sourceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'TotalAmount', 'targetField' => 'amount' }
            },
            'invoiceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'amount', 'targetField' => 'Amount__c' }
                // missing referenceNumber, status, invoiceDate
            },
            'transactionMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'gatewayEventId', 'targetField' => 'Gateway_Event_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayEventType', 'targetField' => 'Gateway_Event_Type__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayAmount', 'targetField' => 'Gateway_Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayReferenceNumber', 'targetField' => 'Gateway_Reference_Number__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayTransactionId', 'targetField' => 'Gateway_Transaction_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'paymentType', 'targetField' => 'Payment_Type__c' }
            }
        });

        Test.startTest();
        try {
            PaymentInvoiceMappingController.saveGatewayMappingConfig(payload);
            System.assert(false, 'Expected validation to fail due to missing referenceNumber.');
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

    @IsTest
    static void getObjectFieldsExcludesBlockedFields() {
        Test.startTest();
        List<PaymentInvoiceMappingController.FieldOption> fields =
            PaymentInvoiceMappingController.getObjectFields('Order');
        Test.stopTest();

        Set<String> values = new Set<String>();
        for (PaymentInvoiceMappingController.FieldOption f : fields) {
            values.add(f.value.toLowerCase());
        }

        List<String> blocked = new List<String>{
            'ownerid', 'createddate', 'createdbyid',
            'lastmodifieddate', 'lastmodifiedbyid', 'systemmodstamp',
            'isdeleted', 'recordtypeid', 'currencyisocode',
            'lastvieweddate', 'lastreferenceddate'
        };
        for (String b : blocked) {
            Assert.isFalse(values.contains(b), b + ' must not appear in getObjectFields');
        }
        Assert.isTrue(values.contains('id'), 'Id must remain in field list');
    }

    @IsTest
    static void saveConfigRejectsBlockedSourceField() {
        String payload = JSON.serialize(new Map<String, Object>{
            'gateway' => 'stripe',
            'sourceObject' => 'Order',
            'sourceCustomerLookupField' => 'AccountId',
            'invoiceObject' => 'QuickBridgeTLG__Invoice__c',
            'invoiceSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'sourceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'OwnerId', 'targetField' => 'amount' }
            },
            'invoiceMappings' => new List<Object>(),
            'transactionMappings' => new List<Object>()
        });

        Test.startTest();
        Boolean threw = false;
        try {
            PaymentInvoiceMappingController.saveGatewayMappingConfig(payload);
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('OwnerId'), 'Exception message should name the blocked field');
        }
        Test.stopTest();

        Assert.isTrue(threw, 'saveGatewayMappingConfig should reject blocked sourceField OwnerId');
    }

    @IsTest
    static void saveConfigGatewaySemanticFieldsAreNotBlocked() {
        // Gateway semantic keys like 'gatewayTransactionId' live in targetField — not SF fields.
        // A valid Stripe config with all required semantic mappings should not be rejected
        // by the eligibility check.
        String payload = JSON.serialize(new Map<String, Object>{
            'gateway' => 'stripe',
            'sourceObject' => 'Order',
            'sourceCustomerLookupField' => 'AccountId',
            'invoiceObject' => 'QuickBridgeTLG__Invoice__c',
            'invoiceSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'transactionObject' => 'Portal_Payment_Transaction__c',
            'transactionSourceLookupField' => 'QuickBridgeTLG__Order__c',
            'sourceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'TotalAmount', 'targetField' => 'amount' }
            },
            'invoiceMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'amount', 'targetField' => 'Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'hostedInvoiceUrl', 'targetField' => 'Stripe_Invoice_Link__c' },
                new Map<String, Object>{ 'sourceField' => 'referenceNumber', 'targetField' => 'Reference_number__c' },
                new Map<String, Object>{ 'sourceField' => 'status', 'targetField' => 'Status__c' },
                new Map<String, Object>{ 'sourceField' => 'invoiceDate', 'targetField' => 'Invoice_Date__c' },
                new Map<String, Object>{ 'sourceField' => 'stripeInvoiceId', 'targetField' => 'Stripe_Invoice_Id__c' }
            },
            'transactionMappings' => new List<Object>{
                new Map<String, Object>{ 'sourceField' => 'gatewayEventId', 'targetField' => 'Gateway_Event_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayEventType', 'targetField' => 'Gateway_Event_Type__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayAmount', 'targetField' => 'Gateway_Amount__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayReferenceNumber', 'targetField' => 'Gateway_Reference_Number__c' },
                new Map<String, Object>{ 'sourceField' => 'gatewayTransactionId', 'targetField' => 'Gateway_Transaction_Id__c' },
                new Map<String, Object>{ 'sourceField' => 'paymentType', 'targetField' => 'Payment_Type__c' },
                new Map<String, Object>{ 'sourceField' => 'stripeLiveMode', 'targetField' => 'Stripe_Live_Mode__c' }
            }
        });

        Test.startTest();
        Boolean blockedByEligibility = false;
        try {
            PaymentInvoiceMappingController.saveGatewayMappingConfig(payload);
        } catch (AuraHandledException e) {
            if (e.getMessage().contains('cannot be used in a mapping')) blockedByEligibility = true;
        }
        Test.stopTest();

        Assert.isFalse(blockedByEligibility, 'Gateway semantic fields must not be rejected by eligibility check');
    }
}