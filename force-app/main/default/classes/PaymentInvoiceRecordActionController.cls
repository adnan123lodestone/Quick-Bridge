public with sharing class PaymentInvoiceRecordActionController {
    private static final String CONTEXT_PAYMENT_INVOICE = 'PaymentInvoice';
    private static final String ACTION_CREATE_INVOICE = 'createInvoice';
    private static final String SETUP_MARKER = '__setup__';
    private static final String GATEWAY_STRIPE = 'stripe';
    private static final String STRIPE_LABEL = 'Stripe';
    private static final String STRIPE_CUSTOMERS_ENDPOINT = 'callout:Stripe_API/v1/customers';
    private static final String STRIPE_INVOICE_ITEMS_ENDPOINT = 'callout:Stripe_API/v1/invoiceitems';
    private static final String STRIPE_INVOICES_ENDPOINT = 'callout:Stripe_API/v1/invoices';
    private static final String STRIPE_SECRET_KEY_MERGE_FIELD = '{!$Credential.Stripe_Credentials.SecretKey}';

    private class InvoiceException extends Exception {}

    @TestVisible private static List<Field_Mapping__mdt> testMappingRows;

    public class PaymentOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    public class PanelData {
        @AuraEnabled public List<PaymentOption> paymentOptions { get; set; }
        @AuraEnabled public String selectedGateway { get; set; }
        @AuraEnabled public String message { get; set; }

        public PanelData() {
            paymentOptions = new List<PaymentOption>();
        }
    }

    public class CreateInvoiceResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Id invoiceRecordId { get; set; }
        @AuraEnabled public String invoiceObjectApiName { get; set; }
        @AuraEnabled public String hostedInvoiceUrl { get; set; }
        @AuraEnabled public String stripeInvoiceId { get; set; }
        @AuraEnabled public String qrFileId { get; set; }
        @AuraEnabled public Boolean emailSent { get; set; }
    }

    private class MappingRow {
        String sourceField;
        String targetField;
    }

    private class MappingConfig {
        String gateway;
        String sourceObject;
        String sourceCustomerLookupField;
        String sourceCustomerTargetObject;
        String invoiceObject;
        String invoiceSourceLookupField;
        String transactionObject;
        String transactionSourceLookupField;
        List<MappingRow> sourceMappings = new List<MappingRow>();
        List<MappingRow> invoiceMappings = new List<MappingRow>();
        List<MappingRow> transactionMappings = new List<MappingRow>();
    }

    private class SourceContext {
        SObject sourceRecord;
        Id sourceRecordId;
        String sourceObjectApiName;
        Id customerId;
        String customerObjectApiName;
        String customerLookupFieldOnSource;
        String customerName;
        String customerEmail;
        String stripeCustomerId;
        Boolean stripeCustomerIdAlreadyExisted = false;
        Map<String, Object> invoiceInputs = new Map<String, Object>();
    }

    private class StripeInvoiceResult {
        String stripeInvoiceId;
        String hostedInvoiceUrl;
        String status;
        String customerId;
    }

    @AuraEnabled(cacheable=false)
    public static PanelData getPanelData(Id recordId, String objectApiName) {
        try {
            validateRecordContext(recordId, objectApiName);

            PanelData data = new PanelData();
            if (isStripeActive() && hasConfiguredMapping(GATEWAY_STRIPE, objectApiName)) {
                PaymentOption option = new PaymentOption();
                option.label = STRIPE_LABEL;
                option.value = GATEWAY_STRIPE;
                data.paymentOptions.add(option);
                data.selectedGateway = GATEWAY_STRIPE;
            }

            if (data.paymentOptions.isEmpty()) {
                data.message = 'No active payment integrations have invoice mappings configured for this object.';
            }
            return data;
        } catch (Exception e) {
            String msg = (e instanceof InvoiceException || !(e instanceof AuraHandledException))
                ? e.getMessage()
                : 'An unexpected error occurred. Check setup and try again.';
            throw new AuraHandledException(msg);
        }
    }

    @AuraEnabled
    public static CreateInvoiceResult createInvoice(Id recordId, String objectApiName, String gateway) {
        CreateInvoiceResult result = new CreateInvoiceResult();
        result.success = false;
        result.emailSent = false;

        try {
            validateRecordContext(recordId, objectApiName);
            String normalizedGateway = normalizeGateway(gateway);
            if (normalizedGateway != GATEWAY_STRIPE) {
                throw new InvoiceException('Only Stripe invoice creation is currently implemented.');
            }
            if (!isStripeActive()) {
                throw new InvoiceException('Stripe is not active in QuickBridge settings.');
            }

            IntegrationUsageService.assertCanConsumeTask(STRIPE_LABEL, 1);

            MappingConfig mappingConfig = loadMappingConfig(normalizedGateway, objectApiName);
            validateExecutableMapping(mappingConfig, objectApiName);

            SourceContext sourceContext = loadSourceContext(mappingConfig, recordId);
            validateSourceInputs(sourceContext);

            String authorizationHeader = 'Bearer ' + STRIPE_SECRET_KEY_MERGE_FIELD;
            String stripeCustomerId = resolveStripeCustomer(sourceContext, authorizationHeader);
            StripeInvoiceResult stripeResult = createStripeInvoice(mappingConfig, sourceContext, stripeCustomerId, authorizationHeader);

            // All callouts are done — now safe to do DML.
            // Write the Stripe customer ID back to Account/Contact if it was newly created.
            if (!sourceContext.stripeCustomerIdAlreadyExisted) {
                writeStripeCustomerIdToCustomer(sourceContext, stripeCustomerId);
            }

            Id invoiceId = insertMappedInvoice(mappingConfig, sourceContext, stripeResult);
            String qrFileId = InvoiceQRService.saveQRCodeFileForUrl(invoiceId, stripeResult.hostedInvoiceUrl, STRIPE_LABEL + ' Invoice QR Code');

            if (String.isNotBlank(sourceContext.customerEmail)) {
                sendInvoiceEmail(sourceContext, stripeResult.hostedInvoiceUrl);
                result.emailSent = true;
            }

            IntegrationUsageService.recordSuccessfulPaymentTask(STRIPE_LABEL);

            result.success = true;
            result.invoiceRecordId = invoiceId;
            result.invoiceObjectApiName = mappingConfig.invoiceObject;
            result.hostedInvoiceUrl = stripeResult.hostedInvoiceUrl;
            result.stripeInvoiceId = stripeResult.stripeInvoiceId;
            result.qrFileId = qrFileId;
            result.message = result.emailSent
                ? 'Stripe invoice created and emailed to ' + sourceContext.customerEmail + '.'
                : 'Stripe invoice created. No email was sent because no email is available on the customer record.';
            return result;
        } catch (Exception e) {
            result.success = false;
            String errMsg = e.getMessage();
            if (e instanceof AuraHandledException || String.isBlank(errMsg) || errMsg == 'Script-thrown exception') {
                errMsg = 'An unexpected error occurred: ' + e.getTypeName() + '. Check setup and try again.';
            }
            result.message = errMsg;
            ErrorLogUtility.logException('Stripe', 'PaymentInvoiceRecordActionController.createInvoice', e, objectApiName, recordId);
            return result;
        }
    }

    private static void validateRecordContext(Id recordId, String objectApiName) {
        if (recordId == null) {
            throw new InvoiceException('Record Id is required.');
        }
        if (String.isBlank(objectApiName)) {
            throw new InvoiceException('Object API name is required.');
        }
        getObjectTypeOrThrow(objectApiName);
    }

    private static Boolean hasConfiguredMapping(String gateway, String objectApiName) {
        try {
            MappingConfig config = loadMappingConfig(gateway, objectApiName);
            validateExecutableMapping(config, objectApiName);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static MappingConfig loadMappingConfig(String gateway, String objectApiName) {
        String normalizedGateway = normalizeGateway(gateway);
        String resolvedObjectApiName = resolveObjectApiName(objectApiName);
        MappingConfig config = new MappingConfig();
        config.gateway = normalizedGateway;
        config.sourceObject = resolvedObjectApiName;

        List<Field_Mapping__mdt> rows = Test.isRunningTest() && testMappingRows != null
            ? testMappingRows
            : [
                SELECT DeveloperName, SF_Object__c, SF_Field__c, External_Field__c, Mapping_Step__c,
                    Target_Object_API_Name__c, Target_Field_API_Name__c,
                    Source_Customer_Lookup_Field__c, Source_Customer_Target_Object__c,
                    Source_Email_Field_API_Name__c, Source_Lookup_On_Target_Field__c
                FROM Field_Mapping__mdt
                WHERE Integration__c = :normalizedGateway
                AND Action__c = :ACTION_CREATE_INVOICE
                AND Mapping_Context__c = :CONTEXT_PAYMENT_INVOICE
                AND SF_Object__c = :resolvedObjectApiName
                AND Is_Active__c = true
                ORDER BY Mapping_Step__c, DeveloperName
            ];

        if (Test.isRunningTest() && testMappingRows != null) {
            List<Field_Mapping__mdt> filteredRows = new List<Field_Mapping__mdt>();
            for (Field_Mapping__mdt row : rows) {
                if (row.Integration__c == normalizedGateway &&
                    row.Action__c == ACTION_CREATE_INVOICE &&
                    row.Mapping_Context__c == CONTEXT_PAYMENT_INVOICE &&
                    row.SF_Object__c == resolvedObjectApiName &&
                    row.Is_Active__c == true) {
                    filteredRows.add(row);
                }
            }
            rows = filteredRows;
        }

        for (Field_Mapping__mdt row : rows) {
            String step = normalizeStep(row.Mapping_Step__c);
            Boolean isSetup = row.SF_Field__c == SETUP_MARKER;
            if (step == 'Source') {
                if (isSetup) {
                    config.sourceCustomerLookupField = row.Source_Customer_Lookup_Field__c;
                    config.sourceCustomerTargetObject = row.Source_Customer_Target_Object__c;
                } else {
                    config.sourceMappings.add(toMappingRow(row, true));
                }
            } else if (step == 'Invoice') {
                if (String.isNotBlank(row.Target_Object_API_Name__c)) {
                    config.invoiceObject = resolveObjectApiName(row.Target_Object_API_Name__c);
                }
                if (isSetup) {
                    config.invoiceSourceLookupField = row.Source_Lookup_On_Target_Field__c;
                } else {
                    config.invoiceMappings.add(toMappingRow(row, false));
                }
            } else if (step == 'Transaction') {
                if (String.isNotBlank(row.Target_Object_API_Name__c)) {
                    config.transactionObject = resolveObjectApiName(row.Target_Object_API_Name__c);
                }
                if (isSetup) {
                    config.transactionSourceLookupField = row.Source_Lookup_On_Target_Field__c;
                } else {
                    config.transactionMappings.add(toMappingRow(row, false));
                }
            }
        }

        return config;
    }

    private static MappingRow toMappingRow(Field_Mapping__mdt row, Boolean useExternalFieldAsTarget) {
        MappingRow mappingRow = new MappingRow();
        mappingRow.sourceField = row.SF_Field__c;
        mappingRow.targetField = String.isNotBlank(row.Target_Field_API_Name__c)
            ? row.Target_Field_API_Name__c
            : (useExternalFieldAsTarget ? row.External_Field__c : null);
        return mappingRow;
    }

    private static void validateExecutableMapping(MappingConfig config, String objectApiName) {
        if (config == null) {
            throw new InvoiceException('Invoice mapping is not configured.');
        }
        String resolvedObjectApiName = resolveObjectApiName(objectApiName);
        if (config.sourceObject != resolvedObjectApiName) {
            throw new InvoiceException('Invoice mapping is not configured for ' + objectApiName + '.');
        }
        if (String.isBlank(config.sourceCustomerLookupField)) {
            throw new InvoiceException('Invoice mapping is missing the source customer lookup.');
        }
        if (String.isBlank(config.invoiceObject) || String.isBlank(config.invoiceSourceLookupField)) {
            throw new InvoiceException('Invoice object mapping is incomplete.');
        }
        if (String.isBlank(config.transactionObject) || String.isBlank(config.transactionSourceLookupField)) {
            throw new InvoiceException('Payment transaction mapping is incomplete.');
        }
        requireSemantic(config.sourceMappings, new Set<String>{ 'amount' }, true, 'source invoice request');
        requireSemantic(config.invoiceMappings, new Set<String>{ 'amount', 'hostedInvoiceUrl', 'referenceNumber', 'status', 'invoiceDate', 'stripeInvoiceId' }, false, 'invoice record');
        requireSemantic(config.transactionMappings, new Set<String>{ 'gatewayEventId', 'gatewayEventType', 'gatewayAmount', 'gatewayReferenceNumber', 'gatewayTransactionId', 'paymentType', 'stripeLiveMode' }, false, 'payment transaction');
    }

    private static void requireSemantic(List<MappingRow> rows, Set<String> requiredFields, Boolean matchTargetField, String label) {
        Set<String> mapped = new Set<String>();
        for (MappingRow row : rows == null ? new List<MappingRow>() : rows) {
            if (row == null || String.isBlank(row.sourceField) || String.isBlank(row.targetField)) {
                continue;
            }
            mapped.add(matchTargetField ? row.targetField : row.sourceField);
        }

        List<String> missing = new List<String>();
        for (String requiredField : requiredFields) {
            if (!mapped.contains(requiredField)) {
                missing.add(requiredField);
            }
        }
        if (!missing.isEmpty()) {
            missing.sort();
            throw new InvoiceException('Configured ' + label + ' mapping is missing: ' + String.join(missing, ', ') + '.');
        }
    }

    private static SourceContext loadSourceContext(MappingConfig config, Id recordId) {
        SourceContext context = new SourceContext();
        context.sourceRecordId = recordId;
        context.sourceObjectApiName = config.sourceObject;

        Map<String, Schema.SObjectField> sourceFieldMap = getFieldMap(config.sourceObject);
        String resolvedCustomerLookupField = resolveFieldApiName(sourceFieldMap, config.sourceCustomerLookupField);

        // Discover all Account and Contact lookup fields on the source object so we can prefer Account
        String accountLookupField = null;
        String contactLookupField = null;
        for (Schema.SObjectField fieldToken : sourceFieldMap.values()) {
            Schema.DescribeFieldResult fd = fieldToken.getDescribe();
            if (fd.getType() != Schema.DisplayType.Reference || !fd.isAccessible()) continue;
            for (Schema.SObjectType ref : fd.getReferenceTo()) {
                String refName = ref.getDescribe().getName();
                if (refName == 'Account' && accountLookupField == null) accountLookupField = fd.getName();
                if (refName == 'Contact' && contactLookupField == null) contactLookupField = fd.getName();
            }
        }

        Set<String> selectFields = new Set<String>{ 'Id' };
        if (String.isNotBlank(resolvedCustomerLookupField)) selectFields.add(resolvedCustomerLookupField);
        if (String.isNotBlank(accountLookupField)) selectFields.add(accountLookupField);
        if (String.isNotBlank(contactLookupField)) selectFields.add(contactLookupField);
        for (MappingRow row : config.sourceMappings) {
            addSelectableField(selectFields, row.sourceField);
        }
        SObject sourceRecord = Database.query(
            'SELECT ' + String.join(new List<String>(selectFields), ', ') +
            ' FROM ' + config.sourceObject +
            ' WHERE Id = :recordId LIMIT 1'
        );
        context.sourceRecord = sourceRecord;

        // Prefer Account over Contact when both lookups are present on the source record
        Id accountIdValue = String.isNotBlank(accountLookupField) ? (Id) sourceRecord.get(accountLookupField) : null;
        Id contactIdValue = String.isNotBlank(contactLookupField) ? (Id) sourceRecord.get(contactLookupField) : null;

        if (accountIdValue != null) {
            context.customerId = accountIdValue;
            context.customerObjectApiName = 'Account';
            context.customerLookupFieldOnSource = accountLookupField;
        } else if (contactIdValue != null) {
            context.customerId = contactIdValue;
            context.customerObjectApiName = 'Contact';
            context.customerLookupFieldOnSource = contactLookupField;
        } else if (String.isNotBlank(resolvedCustomerLookupField)) {
            // Fall back to whatever the configured mapping field holds
            Id configuredValue = (Id) sourceRecord.get(resolvedCustomerLookupField);
            if (configuredValue != null) {
                context.customerId = configuredValue;
                context.customerObjectApiName = configuredValue.getSObjectType().getDescribe().getName();
                context.customerLookupFieldOnSource = resolvedCustomerLookupField;
            }
        }

        for (MappingRow row : config.sourceMappings) {
            context.invoiceInputs.put(row.targetField, readPath(sourceRecord, row.sourceField));
        }
        loadCustomerDetails(context);

        if (String.isBlank(valueAsString(context.invoiceInputs.get('referenceNumber')))) {
            context.invoiceInputs.put('referenceNumber', String.valueOf(recordId));
        }
        if (String.isBlank(valueAsString(context.invoiceInputs.get('currency')))) {
            context.invoiceInputs.put('currency', 'usd');
        }
        if (String.isBlank(valueAsString(context.invoiceInputs.get('customerName'))) && String.isNotBlank(context.customerName)) {
            context.invoiceInputs.put('customerName', context.customerName);
        }
        if (String.isBlank(valueAsString(context.invoiceInputs.get('description')))) {
            context.invoiceInputs.put('description', 'Invoice for ' + String.valueOf(recordId));
        }

        return context;
    }

    private static void addSelectableField(Set<String> selectFields, String fieldPath) {
        if (String.isBlank(fieldPath)) return;
        selectFields.add(fieldPath);
    }

    private static void addResolvedField(Set<String> selectFields, Map<String, Schema.SObjectField> fieldMap, String fieldName) {
        String resolved = resolveFieldApiName(fieldMap, fieldName);
        if (String.isNotBlank(resolved) && fieldMap.containsKey(resolved.toLowerCase())) {
            selectFields.add(resolved);
        }
    }

    private static void loadCustomerDetails(SourceContext context) {
        if (context.customerId == null || String.isBlank(context.customerObjectApiName)) {
            return;
        }

        Map<String, Schema.SObjectField> customerFields = getFieldMap(context.customerObjectApiName);
        Set<String> selectFields = new Set<String>{ 'Id' };
        addResolvedField(selectFields, customerFields, 'Name');
        addResolvedField(selectFields, customerFields, 'Email');
        addResolvedField(selectFields, customerFields, 'PersonEmail');

        String stripeCustomerField = resolveFieldApiName(customerFields, 'Stripe_Customer_Id__c');
        if (String.isNotBlank(stripeCustomerField) && customerFields.containsKey(stripeCustomerField.toLowerCase())) {
            selectFields.add(stripeCustomerField);
        }

        Id customerId = context.customerId;
        SObject customerRecord = Database.query(
            'SELECT ' + String.join(new List<String>(selectFields), ', ') +
            ' FROM ' + context.customerObjectApiName +
            ' WHERE Id = :customerId LIMIT 1'
        );

        context.customerName = valueAsString(customerRecord.get('Name'));
        context.customerEmail = firstNonBlank(
            getOptionalFieldAsString(customerRecord, customerFields, 'Email'),
            getOptionalFieldAsString(customerRecord, customerFields, 'PersonEmail')
        );
        if (String.isNotBlank(stripeCustomerField) && customerFields.containsKey(stripeCustomerField.toLowerCase())) {
            String existing = valueAsString(customerRecord.get(stripeCustomerField));
            context.stripeCustomerId = existing;
            context.stripeCustomerIdAlreadyExisted = String.isNotBlank(existing);
        }
    }

    private static String getOptionalFieldAsString(SObject record, Map<String, Schema.SObjectField> fieldMap, String fieldName) {
        String resolved = resolveFieldApiName(fieldMap, fieldName);
        if (String.isBlank(resolved) || !fieldMap.containsKey(resolved.toLowerCase())) {
            return null;
        }
        return valueAsString(record.get(resolved));
    }

    private static void validateSourceInputs(SourceContext context) {
        if (context.customerId == null) {
            throw new InvoiceException(
                'Cannot create a Stripe customer: no Account or Contact is assigned to this record. ' +
                'Please assign an Account or Contact and try again.'
            );
        }
        Decimal amount = toDecimal(context.invoiceInputs.get('amount'));
        if (amount == null || amount <= 0) {
            throw new InvoiceException('Mapped invoice amount must be greater than zero.');
        }
    }

    private static String resolveStripeCustomer(SourceContext context, String authorizationHeader) {
        if (String.isNotBlank(context.stripeCustomerId)) {
            return context.stripeCustomerId;
        }

        List<String> params = new List<String>();
        addFormParam(params, 'name', firstNonBlank(context.customerName, valueAsString(context.invoiceInputs.get('customerName'))));
        addFormParam(params, 'email', context.customerEmail);
        addFormParam(params, 'metadata[source_record_id]', String.valueOf(context.sourceRecordId));
        addFormParam(params, 'metadata[source_object]', context.sourceObjectApiName);
        addFormParam(params, 'metadata[salesforce_customer_id]', context.customerId == null ? null : String.valueOf(context.customerId));

        HttpResponse response = sendStripePost(STRIPE_CUSTOMERS_ENDPOINT, String.join(params, '&'), authorizationHeader);
        Map<String, Object> parsed = parseStripeResponse(response, 'Stripe returned an invalid response when creating the customer.', 'Stripe customer creation failed with HTTP ');
        String stripeCustomerId = parsed.containsKey('id') ? String.valueOf(parsed.get('id')) : null;
        if (String.isBlank(stripeCustomerId)) {
            throw new InvoiceException('Stripe customer creation returned no customer id.');
        }
        return stripeCustomerId;
    }

    private static void writeStripeCustomerIdToCustomer(SourceContext context, String stripeCustomerId) {
        if (context.customerId == null || String.isBlank(stripeCustomerId)) return;

        String objectName = context.customerObjectApiName;
        if (String.isBlank(objectName) || (objectName != 'Account' && objectName != 'Contact')) return;

        Map<String, Schema.SObjectField> customerFields = getFieldMap(objectName);
        String stripeFieldName = resolveFieldApiName(customerFields, 'Stripe_Customer_Id__c');
        if (String.isBlank(stripeFieldName) || !customerFields.containsKey(stripeFieldName.toLowerCase())) return;

        Schema.DescribeFieldResult fd = customerFields.get(stripeFieldName.toLowerCase()).getDescribe();
        if (!fd.isUpdateable()) return;

        SObject customerUpdate = Schema.getGlobalDescribe().get(objectName).newSObject(context.customerId);
        customerUpdate.put(stripeFieldName, stripeCustomerId);
        update customerUpdate;
    }

    private static StripeInvoiceResult createStripeInvoice(
        MappingConfig mappingConfig,
        SourceContext sourceContext,
        String stripeCustomerId,
        String authorizationHeader
    ) {
        HttpResponse invoiceResponse = sendStripePost(
            STRIPE_INVOICES_ENDPOINT,
            buildStripeInvoiceBody(sourceContext, stripeCustomerId),
            authorizationHeader
        );
        Map<String, Object> createdInvoice = parseStripeResponse(invoiceResponse, 'Stripe returned an invalid response when creating the invoice.', 'Stripe invoice creation failed with HTTP ');
        String stripeInvoiceId = createdInvoice.containsKey('id') ? String.valueOf(createdInvoice.get('id')) : null;
        if (String.isBlank(stripeInvoiceId)) {
            throw new InvoiceException('Stripe invoice creation returned no invoice id.');
        }

        HttpResponse invoiceItemResponse = sendStripePost(
            STRIPE_INVOICE_ITEMS_ENDPOINT,
            buildStripeInvoiceItemBody(sourceContext, stripeCustomerId, stripeInvoiceId),
            authorizationHeader
        );
        parseStripeResponse(invoiceItemResponse, 'Stripe returned an invalid response when creating the invoice item.', 'Stripe invoice item creation failed with HTTP ');

        HttpResponse finalizeResponse = sendStripePost(
            STRIPE_INVOICES_ENDPOINT + '/' + stripeInvoiceId + '/finalize',
            '',
            authorizationHeader
        );
        Map<String, Object> finalizedInvoice = parseStripeResponse(finalizeResponse, 'Stripe returned an invalid response when finalizing the invoice.', 'Stripe invoice finalization failed with HTTP ');
        String hostedInvoiceUrl = finalizedInvoice.containsKey('hosted_invoice_url')
            ? String.valueOf(finalizedInvoice.get('hosted_invoice_url'))
            : null;
        if (String.isBlank(hostedInvoiceUrl)) {
            throw new InvoiceException('Stripe invoice was created but no hosted invoice URL was returned.');
        }

        StripeInvoiceResult result = new StripeInvoiceResult();
        result.stripeInvoiceId = stripeInvoiceId;
        result.hostedInvoiceUrl = hostedInvoiceUrl;
        result.customerId = stripeCustomerId;
        result.status = finalizedInvoice.containsKey('status') ? String.valueOf(finalizedInvoice.get('status')) : 'open';
        return result;
    }

    private static String buildStripeInvoiceBody(SourceContext context, String stripeCustomerId) {
        Boolean hasEmail = String.isNotBlank(context.customerEmail);
        List<String> params = new List<String>();
        addFormParam(params, 'customer', stripeCustomerId);
        addFormParam(params, 'collection_method', hasEmail ? 'send_invoice' : 'charge_automatically');
        addFormParam(params, 'auto_advance', 'false');
        if (hasEmail) {
            addFormParam(params, 'days_until_due', String.valueOf(getDaysUntilDue(toDate(context.invoiceInputs.get('dueDate')))));
        }
        addFormParam(params, 'description', valueAsString(context.invoiceInputs.get('description')));
        addFormParam(params, 'metadata[source_record_id]', String.valueOf(context.sourceRecordId));
        addFormParam(params, 'metadata[source_object]', context.sourceObjectApiName);
        addFormParam(params, 'metadata[reference_number]', String.valueOf(context.sourceRecordId));
        addFormParam(params, 'metadata[order_id]', context.sourceObjectApiName == 'Order' ? String.valueOf(context.sourceRecordId) : null);
        return String.join(params, '&');
    }

    private static String buildStripeInvoiceItemBody(SourceContext context, String stripeCustomerId, String stripeInvoiceId) {
        List<String> params = new List<String>();
        addFormParam(params, 'customer', stripeCustomerId);
        addFormParam(params, 'invoice', stripeInvoiceId);
        addFormParam(params, 'currency', normalizeCurrency(valueAsString(context.invoiceInputs.get('currency'))));
        addFormParam(params, 'amount', String.valueOf((toDecimal(context.invoiceInputs.get('amount')) * 100).setScale(0)));
        addFormParam(params, 'description', valueAsString(context.invoiceInputs.get('description')));
        addFormParam(params, 'metadata[source_record_id]', String.valueOf(context.sourceRecordId));
        addFormParam(params, 'metadata[source_object]', context.sourceObjectApiName);
        addFormParam(params, 'metadata[reference_number]', String.valueOf(context.sourceRecordId));
        addFormParam(params, 'metadata[order_id]', context.sourceObjectApiName == 'Order' ? String.valueOf(context.sourceRecordId) : null);
        return String.join(params, '&');
    }

    private static Id insertMappedInvoice(MappingConfig config, SourceContext sourceContext, StripeInvoiceResult stripeResult) {
        Schema.SObjectType invoiceType = getObjectTypeOrThrow(config.invoiceObject);
        Map<String, Schema.SObjectField> invoiceFields = invoiceType.getDescribe().fields.getMap();
        SObject invoiceRecord = invoiceType.newSObject();

        Map<String, Object> invoiceValues = new Map<String, Object>{
            'amount' => toDecimal(sourceContext.invoiceInputs.get('amount')),
            'hostedInvoiceUrl' => stripeResult.hostedInvoiceUrl,
            'referenceNumber' => String.valueOf(sourceContext.sourceRecordId),
            'status' => toInvoiceStatus(stripeResult.status),
            'invoiceDate' => Date.today(),
            'dueDate' => toDate(sourceContext.invoiceInputs.get('dueDate')),
            'customerEmail' => sourceContext.customerEmail,
            'stripeInvoiceId' => stripeResult.stripeInvoiceId,
            'paymentQrCode' => buildQrImageTag(stripeResult.hostedInvoiceUrl)
        };

        for (MappingRow row : config.invoiceMappings) {
            if (row == null || String.isBlank(row.sourceField) || String.isBlank(row.targetField) || !invoiceValues.containsKey(row.sourceField)) {
                continue;
            }
            putIfCreateable(invoiceRecord, invoiceFields, row.targetField, invoiceValues.get(row.sourceField));
        }

        putIfCreateable(invoiceRecord, invoiceFields, config.invoiceSourceLookupField, sourceContext.sourceRecordId);

        insert invoiceRecord;
        return (Id) invoiceRecord.get('Id');
    }

    private static void putIfCreateable(SObject record, Map<String, Schema.SObjectField> fields, String fieldName, Object value) {
        if (record == null || fields == null || String.isBlank(fieldName) || value == null) {
            return;
        }
        String resolvedField = resolveFieldApiName(fields, fieldName);
        if (String.isBlank(resolvedField) || !fields.containsKey(resolvedField.toLowerCase())) {
            return;
        }
        Schema.DescribeFieldResult fieldDescribe = fields.get(resolvedField.toLowerCase()).getDescribe();
        if (!fieldDescribe.isCreateable()) {
            return;
        }
        record.put(resolvedField, coerceValue(value, fieldDescribe));
    }



    public static Id insertStripeWebhookTransaction(Map<String, Object> payload) {
        if (payload == null) {
            throw new InvoiceException('Stripe webhook payload is required.');
        }

        Map<String, Object> dataPayload  = getNestedMap(payload, 'data');
        Map<String, Object> objectPayload = getNestedMap(dataPayload, 'object');
        Map<String, Object> metadata      = getNestedMap(objectPayload, 'metadata');
        Map<String, Object> requestPayload = getNestedMap(payload, 'request');

        // Resolve the source record from the ID stored in Stripe metadata at invoice creation time.
        String sourceRecordIdStr = getStrPayload(metadata, 'source_record_id');
        if (String.isBlank(sourceRecordIdStr)) {
            throw new InvoiceException('Stripe webhook payload does not contain metadata.source_record_id. Cannot link transaction to a source record.');
        }

        Id sourceRecordId;
        try {
            sourceRecordId = Id.valueOf(sourceRecordIdStr.trim());
        } catch (Exception e) {
            throw new InvoiceException('metadata.source_record_id is not a valid Salesforce record Id: ' + sourceRecordIdStr);
        }

        String sourceObjectApiName = sourceRecordId.getSObjectType().getDescribe().getName();
        MappingConfig config = loadMappingConfig(GATEWAY_STRIPE, sourceObjectApiName);

        // Build the semantic values map — keys match getGatewayTransactionFields() in PaymentInvoiceMappingController.
        Decimal centsAmount = getDecPayload(objectPayload, 'amount_received');
        if (centsAmount == null) centsAmount = getDecPayload(objectPayload, 'amount_paid');
        if (centsAmount == null) centsAmount = getDecPayload(objectPayload, 'amount_due');
        if (centsAmount == null) centsAmount = getDecPayload(objectPayload, 'amount');
        Decimal gatewayAmount = centsAmount == null ? null : (centsAmount / 100);

        Long createdTimestamp = getLngPayload(payload, 'created');
        Datetime gatewayEventDate = createdTimestamp == null ? null :
            Datetime.newInstanceGmt(1970, 1, 1, 0, 0, 0).addSeconds(Integer.valueOf(String.valueOf(createdTimestamp)));

        Boolean liveMode = false;
        Object liveModeRaw = objectPayload != null ? objectPayload.get('livemode') : null;
        if (liveModeRaw instanceof Boolean) liveMode = (Boolean) liveModeRaw;
        else if (liveModeRaw != null) liveMode = String.valueOf(liveModeRaw).equalsIgnoreCase('true');

        Map<String, Object> txnValues = new Map<String, Object>{
            'gatewayEventId'          => getStrPayload(payload, 'id'),
            'gatewayEventType'        => getStrPayload(payload, 'type'),
            'gatewayEventDate'        => gatewayEventDate,
            'gatewayAmount'           => gatewayAmount,
            'gatewayCurrency'         => getStrPayload(objectPayload, 'currency'),
            'gatewayReferenceNumber'  => firstNonBlank(getStrPayload(metadata, 'reference_number'), getStrPayload(metadata, 'source_record_id')),
            'gatewayTransactionId'    => getStrPayload(objectPayload, 'id'),
            'paymentType'             => 'Stripe',
            'stripeLiveMode'          => liveMode,
            'stripeStatus'            => getStrPayload(objectPayload, 'status'),
            'stripeCustomerId'        => getStrPayload(objectPayload, 'customer'),
            'stripeInvoicePdfUrl'     => getStrPayload(objectPayload, 'invoice_pdf'),
            'stripePaymentMethodId'   => getStrPayload(objectPayload, 'payment_method')
        };

        Schema.SObjectType txnType = getObjectTypeOrThrow(config.transactionObject);
        Map<String, Schema.SObjectField> txnFields = txnType.getDescribe().fields.getMap();
        SObject txnRecord = txnType.newSObject();

        for (MappingRow row : config.transactionMappings) {
            if (row == null || String.isBlank(row.sourceField) || String.isBlank(row.targetField) || !txnValues.containsKey(row.sourceField)) {
                continue;
            }
            putIfCreateable(txnRecord, txnFields, row.targetField, txnValues.get(row.sourceField));
        }

        // Always write the lookup back to the source record — this is the join key.
        // Use direct put so managed-package field permissions don't block it.
        String resolvedTxnLookup = resolveFieldApiName(txnFields, config.transactionSourceLookupField);
        if (String.isNotBlank(resolvedTxnLookup)) {
            try { txnRecord.put(resolvedTxnLookup, sourceRecordId); } catch (Exception e) { }
        }

        insert txnRecord;

        // Update the SF invoice record status to Paid using mappings.
        updateInvoiceStatusToPaid(config, objectPayload);

        return (Id) txnRecord.get('Id');
    }

    private static void updateInvoiceStatusToPaid(MappingConfig config, Map<String, Object> objectPayload) {
        if (String.isBlank(config.invoiceObject) || config.invoiceMappings == null || config.invoiceMappings.isEmpty()) {
            return;
        }

        // Find which SF field stores the Stripe invoice ID and which stores the status.
        String stripeInvoiceIdField = null;
        String statusField = null;
        for (MappingRow row : config.invoiceMappings) {
            if (row == null || String.isBlank(row.sourceField) || String.isBlank(row.targetField)) continue;
            if (row.sourceField == 'stripeInvoiceId') stripeInvoiceIdField = row.targetField;
            if (row.sourceField == 'status') statusField = row.targetField;
        }

        if (String.isBlank(stripeInvoiceIdField) || String.isBlank(statusField)) {
            return;
        }

        String stripeInvoiceId = getStrPayload(objectPayload, 'id');
        if (String.isBlank(stripeInvoiceId)) {
            return;
        }

        Schema.SObjectType invoiceType = Schema.getGlobalDescribe().get(resolveObjectApiName(config.invoiceObject));
        if (invoiceType == null) return;

        Map<String, Schema.SObjectField> invoiceFields = invoiceType.getDescribe().fields.getMap();
        String resolvedStripeIdField = resolveFieldApiName(invoiceFields, stripeInvoiceIdField);
        String resolvedStatusField   = resolveFieldApiName(invoiceFields, statusField);

        if (String.isBlank(resolvedStripeIdField) || !invoiceFields.containsKey(resolvedStripeIdField.toLowerCase())) return;
        if (String.isBlank(resolvedStatusField)   || !invoiceFields.containsKey(resolvedStatusField.toLowerCase()))   return;

        List<SObject> invoiceRecords = Database.query(
            'SELECT Id, ' + resolvedStatusField +
            ' FROM ' + config.invoiceObject +
            ' WHERE ' + resolvedStripeIdField + ' = :stripeInvoiceId LIMIT 1'
        );

        if (invoiceRecords.isEmpty()) return;

        SObject invoiceRecord = invoiceRecords[0];
        try { invoiceRecord.put(resolvedStatusField, 'Paid'); } catch (Exception e) { return; }
        update invoiceRecord;
    }

    private static Map<String, Object> getNestedMap(Map<String, Object> m, String key) {
        if (m == null || !m.containsKey(key) || m.get(key) == null) return null;
        try { return (Map<String, Object>) m.get(key); } catch (Exception e) { return null; }
    }

    private static String getStrPayload(Map<String, Object> m, String key) {
        if (m == null || !m.containsKey(key) || m.get(key) == null) return null;
        return String.valueOf(m.get(key));
    }

    private static Decimal getDecPayload(Map<String, Object> m, String key) {
        if (m == null || !m.containsKey(key) || m.get(key) == null) return null;
        try { return Decimal.valueOf(String.valueOf(m.get(key))); } catch (Exception e) { return null; }
    }

    private static Long getLngPayload(Map<String, Object> m, String key) {
        if (m == null || !m.containsKey(key) || m.get(key) == null) return null;
        try { return Long.valueOf(String.valueOf(m.get(key))); } catch (Exception e) { return null; }
    }

    private static void sendInvoiceEmail(SourceContext sourceContext, String hostedInvoiceUrl) {
        if (String.isBlank(sourceContext.customerEmail)) {
            return;
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ sourceContext.customerEmail });
        email.setSaveAsActivity(false);
        email.setSubject('Your invoice is ready for payment');
        email.setHtmlBody(buildInvoiceEmailBody(sourceContext, hostedInvoiceUrl));

        if (!Test.isRunningTest()) {
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email }, false);
        }
    }

    private static String buildInvoiceEmailBody(SourceContext sourceContext, String hostedInvoiceUrl) {
        String customerName = String.isBlank(sourceContext.customerName) ? 'Customer' : sourceContext.customerName.escapeHtml4();
        String amount = sourceContext.invoiceInputs.get('amount') == null ? '' : String.valueOf(toDecimal(sourceContext.invoiceInputs.get('amount')).setScale(2));
        String qrUrl = InvoiceQRService.buildQRCodeImageUrl(hostedInvoiceUrl);
        return '<p>Hello ' + customerName + ',</p>' +
            '<p>Your invoice is ready for payment.</p>' +
            (String.isBlank(amount) ? '' : '<p><strong>Amount:</strong> ' + amount.escapeHtml4() + '</p>') +
            '<p><a href="' + hostedInvoiceUrl.escapeHtml4() + '">Pay invoice securely</a></p>' +
            '<p><img src="' + qrUrl.escapeHtml4() + '" alt="Payment QR Code" width="180" height="180"/></p>' +
            '<p>Thank you.</p>';
    }

    private static HttpResponse sendStripePost(String endpoint, String requestBody, String authorizationHeader) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setHeader('Authorization', authorizationHeader);
        request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        request.setTimeout(20000);
        request.setBody(requestBody);
        return new Http().send(request);
    }

    private static Map<String, Object> parseStripeResponse(HttpResponse response, String invalidBodyMessage, String httpErrorPrefix) {
        String body = response == null ? null : response.getBody();
        String sanitized = String.isBlank(body) ? null : body.trim().replaceFirst('^\\uFEFF', '');
        if (String.isBlank(sanitized) || (!sanitized.startsWith('{') && !sanitized.startsWith('['))) {
            throw new InvoiceException(invalidBodyMessage);
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(sanitized);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300 || parsed.containsKey('error')) {
            String message = extractStripeError(parsed);
            throw new InvoiceException(String.isBlank(message) ? httpErrorPrefix + response.getStatusCode() + '.' : message);
        }
        return parsed;
    }

    private static String extractStripeError(Map<String, Object> parsed) {
        if (parsed == null || !parsed.containsKey('error')) {
            return null;
        }
        try {
            Map<String, Object> error = (Map<String, Object>) parsed.get('error');
            return error == null || !error.containsKey('message') ? null : String.valueOf(error.get('message'));
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean isStripeActive() {
        if (Test.isRunningTest()) {
            return true;
        }
        Quickbridge_Config__mdt config;
        try {
            config = Quickbridge_Config__mdt.getInstance('Stripe');
        } catch (Exception e) {
            config = null;
        }
        if (config == null) return false;
        if (config.Stripe_Active__c == false) return false;
        Date today = Date.today();
        if (config.Stripe_Start_Date__c != null && config.Stripe_Start_Date__c > today) return false;
        if (config.Stripe_End_Date__c != null && config.Stripe_End_Date__c < today) return false;
        return true;
    }

    private static String normalizeGateway(String gateway) {
        String normalized = String.isBlank(gateway) ? GATEWAY_STRIPE : gateway.trim().toLowerCase();
        if (normalized != GATEWAY_STRIPE) {
            throw new InvoiceException('Unsupported invoice gateway: ' + gateway);
        }
        return normalized;
    }

    private static String normalizeStep(String step) {
        if (String.isBlank(step)) return '';
        if (step.equalsIgnoreCase('source')) return 'Source';
        if (step.equalsIgnoreCase('invoice')) return 'Invoice';
        if (step.equalsIgnoreCase('transaction')) return 'Transaction';
        return step;
    }

    private static String normalizeCurrency(String currencyCode) {
        return String.isBlank(currencyCode) ? 'usd' : currencyCode.trim().toLowerCase();
    }

    private static Integer getDaysUntilDue(Date dueDate) {
        if (dueDate == null) return 30;
        Integer days = Date.today().daysBetween(dueDate);
        return days <= 0 ? 1 : days;
    }

    private static String toInvoiceStatus(String stripeStatus) {
        if (String.isBlank(stripeStatus)) return 'Open';
        if (stripeStatus.equalsIgnoreCase('paid')) return 'Paid';
        if (stripeStatus.equalsIgnoreCase('void') || stripeStatus.equalsIgnoreCase('uncollectible')) return 'Cancelled';
        if (stripeStatus.equalsIgnoreCase('draft')) return 'Draft';
        return 'Open';
    }

    private static String buildQrImageTag(String hostedInvoiceUrl) {
        if (String.isBlank(hostedInvoiceUrl)) return null;
        String qrUrl = InvoiceQRService.buildQRCodeImageUrl(hostedInvoiceUrl);
        if (String.isBlank(qrUrl)) return null;
        return '<img src="' + qrUrl.escapeHtml4() + '" alt="Payment QR Code" width="200" height="200" />';
    }

    private static Object readPath(SObject record, String fieldPath) {
        if (record == null || String.isBlank(fieldPath)) return null;
        if (!fieldPath.contains('.')) {
            return record.get(fieldPath);
        }

        List<String> parts = fieldPath.split('\\.');
        SObject currentRecord = record;
        for (Integer index = 0; index < parts.size() - 1; index++) {
            currentRecord = currentRecord == null ? null : currentRecord.getSObject(parts[index]);
            if (currentRecord == null) return null;
        }
        return currentRecord.get(parts[parts.size() - 1]);
    }

    private static Object coerceValue(Object value, Schema.DescribeFieldResult fieldDescribe) {
        if (value == null || fieldDescribe == null) return value;
        Schema.DisplayType fieldType = fieldDescribe.getType();
        if (fieldType == Schema.DisplayType.Currency || fieldType == Schema.DisplayType.Double || fieldType == Schema.DisplayType.Percent) {
            return toDecimal(value);
        }
        if (fieldType == Schema.DisplayType.Integer) {
            Decimal decimalValue = toDecimal(value);
            return decimalValue == null ? null : Integer.valueOf(decimalValue);
        }
        if (fieldType == Schema.DisplayType.Date) {
            return toDate(value);
        }
        if (fieldType == Schema.DisplayType.DateTime) {
            if (value instanceof Datetime) return value;
            Date dateValue = toDate(value);
            return dateValue == null ? null : Datetime.newInstance(dateValue, Time.newInstance(0, 0, 0, 0));
        }
        if (fieldType == Schema.DisplayType.Boolean) {
            if (value instanceof Boolean) return value;
            return String.valueOf(value).equalsIgnoreCase('true');
        }
        if (fieldType == Schema.DisplayType.Reference) {
            return value instanceof Id ? value : Id.valueOf(String.valueOf(value));
        }
        return valueAsString(value);
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) return null;
        if (value instanceof Decimal) return (Decimal) value;
        if (value instanceof Integer) return Decimal.valueOf((Integer) value);
        if (value instanceof Long) return Decimal.valueOf((Long) value);
        if (value instanceof Double) return Decimal.valueOf(String.valueOf(value));
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static Date toDate(Object value) {
        if (value == null) return null;
        if (value instanceof Date) return (Date) value;
        if (value instanceof Datetime) return ((Datetime) value).date();
        try {
            return Date.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static String valueAsString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isBlank(firstValue) ? secondValue : firstValue;
    }

    private static void addFormParam(List<String> params, String key, String value) {
        if (String.isBlank(key) || value == null) return;
        params.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(value, 'UTF-8'));
    }

    private static Schema.SObjectType getObjectTypeOrThrow(String objectApiName) {
        String resolvedName = resolveObjectApiName(objectApiName);
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(resolvedName);
        if (objectType == null) {
            throw new InvoiceException('Object not found: ' + objectApiName);
        }
        return objectType;
    }

    private static Map<String, Schema.SObjectField> getFieldMap(String objectApiName) {
        return getObjectTypeOrThrow(objectApiName).getDescribe().fields.getMap();
    }

    private static Schema.DescribeFieldResult getFieldDescribeOrThrow(String objectApiName, String fieldName) {
        Map<String, Schema.SObjectField> fields = getFieldMap(objectApiName);
        String resolvedFieldName = resolveFieldApiName(fields, fieldName);
        if (String.isBlank(resolvedFieldName) || !fields.containsKey(resolvedFieldName.toLowerCase())) {
            throw new InvoiceException('Field not found: ' + objectApiName + '.' + fieldName);
        }
        return fields.get(resolvedFieldName.toLowerCase()).getDescribe();
    }

    private static String resolveObjectApiName(String objectApiName) {
        if (String.isBlank(objectApiName)) return objectApiName;
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (globalDescribe.containsKey(objectApiName)) return objectApiName;
        if (objectApiName.endsWith('__c')) {
            String namespacePrefix = getNamespacePrefix();
            if (String.isNotBlank(namespacePrefix) && !objectApiName.startsWith(namespacePrefix)) {
                String namespacedName = namespacePrefix + objectApiName;
                if (globalDescribe.containsKey(namespacedName)) return namespacedName;
            }
        }
        return objectApiName;
    }

    private static String resolveFieldApiName(Map<String, Schema.SObjectField> fields, String fieldName) {
        if (String.isBlank(fieldName) || fields == null) return fieldName;
        if (fields.containsKey(fieldName.toLowerCase())) return fieldName;
        if (fieldName.endsWith('__c')) {
            String namespacePrefix = getNamespacePrefix();
            if (String.isNotBlank(namespacePrefix) && !fieldName.startsWith(namespacePrefix)) {
                String namespacedField = namespacePrefix + fieldName;
                if (fields.containsKey(namespacedField.toLowerCase())) return namespacedField;
            }
        }
        return fieldName;
    }

    private static String getNamespacePrefix() {
        String className = PaymentInvoiceRecordActionController.class.getName();
        return className.contains('.') ? className.substringBefore('.') + '__' : '';
    }

    private static List<String> referenceNames(Schema.DescribeFieldResult fieldDescribe) {
        List<String> names = new List<String>();
        if (fieldDescribe == null) return names;
        for (Schema.SObjectType referenceType : fieldDescribe.getReferenceTo()) {
            names.add(referenceType.getDescribe().getName());
        }
        return names;
    }
}