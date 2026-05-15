public with sharing class PaymentInvoiceMappingController {
    private static final String CONTEXT_PAYMENT_INVOICE = 'PaymentInvoice';
    private static final String ACTION_CREATE_INVOICE = 'createInvoice';
    private static final String SETUP_MARKER = '__setup__';
    private static final Set<String> SUPPORTED_GATEWAYS = new Set<String>{ 'stripe' };
    private static final Set<String> CUSTOMER_OBJECTS = new Set<String>{ 'Account', 'Contact' };
    private static final Set<String> IGNORED_FIELD_NAMES = new Set<String>{
        'ownerid', 'recordtypeid', 'currencyisocode', 'createdbyid', 'lastmodifiedbyid', 'systemmodstamp'
    };

    public class FieldOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String referenceTo { get; set; }
    }

    public class MappingRow {
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String sourceField { get; set; }
        @AuraEnabled public String targetField { get; set; }
        @AuraEnabled public Boolean isRequired { get; set; }
    }

    public class GatewayMappingConfig {
        @AuraEnabled public String gateway { get; set; }
        @AuraEnabled public String sourceObject { get; set; }
        @AuraEnabled public String sourceCustomerLookupField { get; set; }
        @AuraEnabled public String sourceCustomerTargetObject { get; set; }
        @AuraEnabled public String sourceEmailField { get; set; }
        @AuraEnabled public String invoiceObject { get; set; }
        @AuraEnabled public String invoiceSourceLookupField { get; set; }
        @AuraEnabled public String transactionObject { get; set; }
        @AuraEnabled public String transactionSourceLookupField { get; set; }
        @AuraEnabled public List<MappingRow> sourceMappings { get; set; }
        @AuraEnabled public List<MappingRow> invoiceMappings { get; set; }
        @AuraEnabled public List<MappingRow> transactionMappings { get; set; }

        public GatewayMappingConfig() {
            sourceObject = 'Order';
            invoiceObject = 'Invoice__c';
            transactionObject = 'Portal_Payment_Transaction__c';
            sourceMappings = new List<MappingRow>();
            invoiceMappings = new List<MappingRow>();
            transactionMappings = new List<MappingRow>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static GatewayMappingConfig getGatewayMappingConfig(String gateway) {
        String normalizedGateway = normalizeGateway(gateway);
        GatewayMappingConfig config = new GatewayMappingConfig();
        config.gateway = normalizedGateway;
        config.invoiceObject = resolveObjectApiName(config.invoiceObject);
        config.transactionObject = resolveObjectApiName(config.transactionObject);

        List<Field_Mapping__mdt> rows = [
            SELECT DeveloperName, SF_Object__c, SF_Field__c, External_Field__c, Mapping_Step__c,
                Target_Object_API_Name__c, Target_Field_API_Name__c,
                Source_Customer_Lookup_Field__c, Source_Customer_Target_Object__c,
                Source_Email_Field_API_Name__c, Source_Lookup_On_Target_Field__c
            FROM Field_Mapping__mdt
            WHERE Integration__c = :normalizedGateway
            AND Action__c = :ACTION_CREATE_INVOICE
            AND Mapping_Context__c = :CONTEXT_PAYMENT_INVOICE
            AND Is_Active__c = true
            ORDER BY Mapping_Step__c, DeveloperName
        ];

        for (Field_Mapping__mdt row : rows) {
            String step = normalizeStep(row.Mapping_Step__c);
            Boolean isSetup = row.SF_Field__c == SETUP_MARKER;

            if (step == 'Source') {
                if (String.isNotBlank(row.SF_Object__c)) config.sourceObject = row.SF_Object__c;
                if (isSetup) {
                    config.sourceCustomerLookupField = row.Source_Customer_Lookup_Field__c;
                    config.sourceCustomerTargetObject = row.Source_Customer_Target_Object__c;
                    config.sourceEmailField = row.Source_Email_Field_API_Name__c;
                } else {
                    config.sourceMappings.add(toMappingRow(row, true));
                }
            } else if (step == 'Invoice') {
                if (String.isNotBlank(row.Target_Object_API_Name__c)) config.invoiceObject = row.Target_Object_API_Name__c;
                if (isSetup) {
                    config.invoiceSourceLookupField = row.Source_Lookup_On_Target_Field__c;
                } else {
                    config.invoiceMappings.add(toMappingRow(row, false));
                }
            } else if (step == 'Transaction') {
                if (String.isNotBlank(row.Target_Object_API_Name__c)) config.transactionObject = row.Target_Object_API_Name__c;
                if (isSetup) {
                    config.transactionSourceLookupField = row.Source_Lookup_On_Target_Field__c;
                } else {
                    config.transactionMappings.add(toMappingRow(row, false));
                }
            }
        }

        return config;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getEligibleSourceObjects() {
        List<FieldOption> options = new List<FieldOption>();
        for (Schema.SObjectType objectType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult describeResult = objectType.getDescribe();
            if (!describeResult.isCustom() || !describeResult.isCreateable() || !hasCustomerLookup(describeResult)) {
                continue;
            }
            options.add(toObjectOption(describeResult));
        }
        options.sort(new FieldOptionLabelComparator());
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getCreateableObjects() {
        List<FieldOption> options = new List<FieldOption>();
        for (Schema.SObjectType objectType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult describeResult = objectType.getDescribe();
            if (!describeResult.isCreateable()) {
                continue;
            }
            if (!describeResult.isCustom() && describeResult.getName() != 'Order') {
                continue;
            }
            options.add(toObjectOption(describeResult));
        }
        options.sort(new FieldOptionLabelComparator());
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getObjectsWithLookupTo(String targetObjectApiName) {
        String resolvedTargetObjectApiName = resolveObjectApiName(targetObjectApiName);
        List<FieldOption> options = new List<FieldOption>();
        if (String.isBlank(resolvedTargetObjectApiName)) {
            return options;
        }

        for (Schema.SObjectType objectType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult describeResult = objectType.getDescribe();
            if (!describeResult.isCreateable()) {
                continue;
            }
            if (!describeResult.isCustom() &&
                describeResult.getName() != 'Order' &&
                !describeResult.getName().endsWith('__Invoice__c') &&
                !describeResult.getName().endsWith('__Portal_Payment_Transaction__c')) {
                continue;
            }
            if (hasLookupTo(describeResult, resolvedTargetObjectApiName)) {
                options.add(toObjectOption(describeResult));
            }
        }

        options.sort(new FieldOptionLabelComparator());
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getObjectFields(String objectApiName) {
        Schema.SObjectType objectType = getObjectTypeOrThrow(objectApiName);
        List<FieldOption> options = new List<FieldOption>();

        for (Schema.SObjectField fieldToken : objectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            String fieldName = fieldDescribe.getName();
            if (IGNORED_FIELD_NAMES.contains(fieldName.toLowerCase())) {
                continue;
            }
            if (!fieldDescribe.isAccessible()) {
                continue;
            }
            FieldOption option = new FieldOption();
            option.label = fieldDescribe.getLabel() + ' (' + fieldName + ')';
            option.value = fieldName;
            option.type = String.valueOf(fieldDescribe.getType());
            option.referenceTo = firstReferenceName(fieldDescribe);
            options.add(option);
        }

        options.sort(new FieldOptionLabelComparator());
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getEmailFieldOptions(String objectApiName, String customerLookupField) {
        Schema.SObjectType objectType = getObjectTypeOrThrow(objectApiName);
        List<FieldOption> options = new List<FieldOption>();
        Map<String, Schema.SObjectField> fieldsByName = objectType.getDescribe().fields.getMap();

        for (Schema.SObjectField fieldToken : fieldsByName.values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            String fieldName = fieldDescribe.getName();
            if (!fieldDescribe.isAccessible() || IGNORED_FIELD_NAMES.contains(fieldName.toLowerCase())) {
                continue;
            }
            Schema.DisplayType fieldType = fieldDescribe.getType();
            if (fieldType == Schema.DisplayType.Email || fieldType == Schema.DisplayType.String) {
                FieldOption option = new FieldOption();
                option.label = fieldDescribe.getLabel() + ' (' + fieldName + ')';
                option.value = fieldName;
                option.type = String.valueOf(fieldType);
                options.add(option);
            }
        }

        if (String.isNotBlank(customerLookupField) && fieldsByName.containsKey(customerLookupField.toLowerCase())) {
            Schema.DescribeFieldResult lookupDescribe = fieldsByName.get(customerLookupField.toLowerCase()).getDescribe();
            String relationshipName = lookupDescribe.getRelationshipName();
            String referencedObjectName = firstReferenceName(lookupDescribe);
            Schema.SObjectType referencedType = String.isBlank(referencedObjectName)
                ? null
                : Schema.getGlobalDescribe().get(referencedObjectName);

            if (!String.isBlank(relationshipName) && referencedType != null) {
                for (Schema.SObjectField relatedFieldToken : referencedType.getDescribe().fields.getMap().values()) {
                    Schema.DescribeFieldResult relatedFieldDescribe = relatedFieldToken.getDescribe();
                    Schema.DisplayType relatedFieldType = relatedFieldDescribe.getType();
                    if (!relatedFieldDescribe.isAccessible() ||
                        (relatedFieldType != Schema.DisplayType.Email && relatedFieldType != Schema.DisplayType.String)) {
                        continue;
                    }
                    FieldOption option = new FieldOption();
                    option.label = referencedType.getDescribe().getLabel() + ' ' + relatedFieldDescribe.getLabel() +
                        ' (' + relationshipName + '.' + relatedFieldDescribe.getName() + ')';
                    option.value = relationshipName + '.' + relatedFieldDescribe.getName();
                    option.type = String.valueOf(relatedFieldType);
                    options.add(option);
                }
            }
        }

        options.sort(new FieldOptionLabelComparator());
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getLookupFields(String objectApiName, String targetObjectApiName) {
        Schema.SObjectType objectType = getObjectTypeOrThrow(objectApiName);
        String resolvedTargetObjectApiName = String.isBlank(targetObjectApiName) ? null : resolveObjectApiName(targetObjectApiName);
        List<FieldOption> options = new List<FieldOption>();
        for (Schema.SObjectField fieldToken : objectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (fieldDescribe.getType() != Schema.DisplayType.Reference || !fieldDescribe.isAccessible()) {
                continue;
            }
            List<String> references = referenceNames(fieldDescribe);
            if (String.isNotBlank(resolvedTargetObjectApiName)) {
                Boolean matchesTarget = false;
                for (String referenceName : references) {
                    if (referenceName == resolvedTargetObjectApiName) {
                        matchesTarget = true;
                        break;
                    }
                }
                if (!matchesTarget) {
                    continue;
                }
            } else {
                Boolean matchesCustomer = false;
                for (String referenceName : references) {
                    if (CUSTOMER_OBJECTS.contains(referenceName)) {
                        matchesCustomer = true;
                        break;
                    }
                }
                if (!matchesCustomer) {
                    continue;
                }
            }

            FieldOption option = new FieldOption();
            option.label = fieldDescribe.getLabel() + ' (' + fieldDescribe.getName() + ')';
            option.value = fieldDescribe.getName();
            option.type = 'Reference';
            option.referenceTo = String.join(references, ',');
            options.add(option);
        }
        options.sort(new FieldOptionLabelComparator());
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getInvoiceRequestFields() {
        return new List<FieldOption>{
            fieldOption('Amount', 'amount', 'Currency'),
            fieldOption('Currency', 'currency', 'String'),
            fieldOption('Due Date', 'dueDate', 'Date'),
            fieldOption('Description', 'description', 'String'),
            fieldOption('Reference Number', 'referenceNumber', 'String'),
            fieldOption('Customer Name', 'customerName', 'String')
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getGatewayTransactionFields(String gateway) {
        normalizeGateway(gateway);
        return new List<FieldOption>{
            fieldOption('Gateway Event Id', 'gatewayEventId', 'String'),
            fieldOption('Gateway Event Type', 'gatewayEventType', 'String'),
            fieldOption('Gateway Event Date', 'gatewayEventDate', 'Datetime'),
            fieldOption('Gateway Amount', 'gatewayAmount', 'Currency'),
            fieldOption('Gateway Currency', 'gatewayCurrency', 'String'),
            fieldOption('Gateway Reference Number', 'gatewayReferenceNumber', 'String'),
            fieldOption('Gateway Transaction Id', 'gatewayTransactionId', 'String'),
            fieldOption('Payment Type', 'paymentType', 'String'),
            fieldOption('Stripe Live Mode', 'stripeLiveMode', 'Boolean'),
            fieldOption('Stripe Status', 'stripeStatus', 'String'),
            fieldOption('Stripe Customer Id', 'stripeCustomerId', 'String'),
            fieldOption('Stripe Invoice PDF Url', 'stripeInvoicePdfUrl', 'Url'),
            fieldOption('Stripe Payment Method Id', 'stripePaymentMethodId', 'String')
        };
    }

    @AuraEnabled
    public static String saveGatewayMappingConfig(String configJson) {
        GatewayMappingConfig config = parseConfig(configJson);
        validateConfig(config);

        // Build the set of DeveloperNames that will be written fresh this save.
        // These must NOT also appear as deactivation-only records — Salesforce rejects
        // duplicate fullNames in a single deploy container.
        Set<String> reusedNames = new Set<String>{
            'PI_Stripe_Source_Setup', 'PI_Stripe_Invoice_Setup', 'PI_Stripe_Transaction_Setup'
        };
        Integer srcCount  = config.sourceMappings  == null ? 0 : config.sourceMappings.size();
        Integer invCount  = config.invoiceMappings  == null ? 0 : config.invoiceMappings.size();
        Integer txnCount  = config.transactionMappings == null ? 0 : config.transactionMappings.size();
        for (Integer i = 1; i <= srcCount; i++)  reusedNames.add('PI_Stripe_Source_'  + String.valueOf(i).leftPad(3, '0'));
        for (Integer i = 1; i <= invCount; i++)  reusedNames.add('PI_Stripe_Invoice_' + String.valueOf(i).leftPad(3, '0'));
        for (Integer i = 1; i <= txnCount; i++)  reusedNames.add('PI_Stripe_Txn_'     + String.valueOf(i).leftPad(3, '0'));

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        for (Field_Mapping__mdt existing : [
            SELECT DeveloperName
            FROM Field_Mapping__mdt
            WHERE Integration__c = :config.gateway
            AND Action__c = :ACTION_CREATE_INVOICE
            AND Mapping_Context__c = :CONTEXT_PAYMENT_INVOICE
            AND Is_Active__c = true
        ]) {
            // Skip records that will be fully overwritten — adding them here too would
            // create duplicate fullNames in the container and fail deployment.
            if (reusedNames.contains(existing.DeveloperName)) continue;
            Metadata.CustomMetadata inactiveMetadata = new Metadata.CustomMetadata();
            inactiveMetadata.fullName = 'Field_Mapping__mdt.' + existing.DeveloperName;
            inactiveMetadata.label = existing.DeveloperName;
            addCustomMetadataValue(inactiveMetadata, 'Is_Active__c', false);
            container.addMetadata(inactiveMetadata);
        }

        addSetupRecord(container, config, 'Source', config.sourceObject, config.sourceObject, null, 'PI_Stripe_Source_Setup');
        addSetupRecord(container, config, 'Invoice', config.sourceObject, config.invoiceObject, config.invoiceSourceLookupField, 'PI_Stripe_Invoice_Setup');
        addSetupRecord(container, config, 'Transaction', config.sourceObject, config.transactionObject, config.transactionSourceLookupField, 'PI_Stripe_Transaction_Setup');
        addMappingRecords(container, config, 'Source', config.sourceObject, config.sourceObject, config.sourceMappings, 'PI_Stripe_Source_');
        addMappingRecords(container, config, 'Invoice', config.sourceObject, config.invoiceObject, config.invoiceMappings, 'PI_Stripe_Invoice_');
        addMappingRecords(container, config, 'Transaction', config.sourceObject, config.transactionObject, config.transactionMappings, 'PI_Stripe_Txn_');

        if (Test.isRunningTest()) {
            return 'Mappings validated successfully.';
        }

        Id jobId = Metadata.Operations.enqueueDeployment(container, null);
        return 'Mappings Deployment Started! Job ID: ' + jobId;
    }

    private static GatewayMappingConfig parseConfig(String configJson) {
        if (String.isBlank(configJson)) {
            throw new AuraHandledException('Mapping configuration is required.');
        }
        try {
            return (GatewayMappingConfig) JSON.deserialize(configJson, GatewayMappingConfig.class);
        } catch (Exception e) {
            throw new AuraHandledException('Mapping configuration could not be parsed.');
        }
    }

    private static void validateConfig(GatewayMappingConfig config) {
        if (config == null) {
            throw new AuraHandledException('Mapping configuration is required.');
        }
        config.gateway = normalizeGateway(config.gateway);
        if (String.isBlank(config.sourceObject)) throw new AuraHandledException('Select a source object.');
        if (String.isBlank(config.sourceCustomerLookupField)) throw new AuraHandledException('Select the source customer lookup field.');
        if (String.isBlank(config.invoiceObject)) throw new AuraHandledException('Select an invoice object.');
        if (String.isBlank(config.invoiceSourceLookupField)) throw new AuraHandledException('Select the invoice lookup to the source object.');
        if (String.isBlank(config.transactionObject)) throw new AuraHandledException('Select a payment transaction object.');
        if (String.isBlank(config.transactionSourceLookupField)) throw new AuraHandledException('Select the transaction lookup to the source object.');

        config.sourceObject = resolveObjectApiName(config.sourceObject);
        config.invoiceObject = resolveObjectApiName(config.invoiceObject);
        config.transactionObject = resolveObjectApiName(config.transactionObject);
        validateCustomerLookup(config.sourceObject, config.sourceCustomerLookupField, config);
        validateTargetLookup(config.invoiceObject, config.sourceObject, config.invoiceSourceLookupField, 'invoice');
        validateTargetLookup(config.transactionObject, config.sourceObject, config.transactionSourceLookupField, 'payment transaction');
        validateMappingRows(config.sourceMappings, 'source invoice request');
        validateMappingRows(config.invoiceMappings, 'invoice record');
        validateMappingRows(config.transactionMappings, 'payment transaction');
        validateRequiredSemanticMappings(config.sourceMappings, new Set<String>{ 'amount' }, 'source invoice request', true);
        validateRequiredSemanticMappings(config.invoiceMappings, new Set<String>{ 'amount', 'hostedInvoiceUrl', 'referenceNumber', 'status', 'invoiceDate', 'stripeInvoiceId' }, 'invoice record', false);
        validateRequiredSemanticMappings(config.transactionMappings, new Set<String>{ 'gatewayEventId', 'gatewayEventType', 'gatewayAmount', 'gatewayReferenceNumber', 'gatewayTransactionId', 'paymentType', 'stripeLiveMode' }, 'payment transaction', false);
    }

    private static void validateCustomerLookup(String objectApiName, String fieldName, GatewayMappingConfig config) {
        Schema.DescribeFieldResult fieldDescribe = getFieldDescribeOrThrow(objectApiName, fieldName);
        if (fieldDescribe.getType() != Schema.DisplayType.Reference) {
            throw new AuraHandledException('The selected customer field must be a lookup to Account or Contact.');
        }
        for (String referenceName : referenceNames(fieldDescribe)) {
            if (CUSTOMER_OBJECTS.contains(referenceName)) {
                config.sourceCustomerTargetObject = referenceName;
                return;
            }
        }
        throw new AuraHandledException('The selected customer field must be a lookup to Account or Contact.');
    }

    private static void validateTargetLookup(String targetObject, String sourceObject, String lookupField, String label) {
        Schema.DescribeFieldResult fieldDescribe = getFieldDescribeOrThrow(targetObject, lookupField);
        if (fieldDescribe.getType() != Schema.DisplayType.Reference || !referenceNames(fieldDescribe).contains(sourceObject)) {
            throw new AuraHandledException(
                'The selected ' + label + ' object must have a lookup field to ' + sourceObject + '. ' +
                'Add that lookup in Object Manager, then return here and select it.'
            );
        }
    }

    private static void validateMappingRows(List<MappingRow> rows, String label) {
        if (rows == null) return;
        Set<String> sourceFields = new Set<String>();
        Set<String> targetFields = new Set<String>();
        for (MappingRow row : rows) {
            if (row == null || String.isBlank(row.sourceField) || String.isBlank(row.targetField)) {
                continue;
            }
            if (sourceFields.contains(row.sourceField) || targetFields.contains(row.targetField)) {
                throw new AuraHandledException('Each ' + label + ' field can only be mapped once.');
            }
            sourceFields.add(row.sourceField);
            targetFields.add(row.targetField);
        }
    }

    private static void validateRequiredSemanticMappings(List<MappingRow> rows, Set<String> requiredFields, String label, Boolean matchTargetField) {
        Set<String> mappedFields = new Set<String>();
        if (rows != null) {
            for (MappingRow row : rows) {
                if (row != null && String.isNotBlank(row.sourceField) && String.isNotBlank(row.targetField)) {
                    mappedFields.add(matchTargetField ? row.targetField : row.sourceField);
                }
            }
        }

        List<String> missingFields = new List<String>();
        for (String requiredField : requiredFields) {
            if (!mappedFields.contains(requiredField)) {
                missingFields.add(requiredField);
            }
        }

        if (!missingFields.isEmpty()) {
            missingFields.sort();
            throw new AuraHandledException('Map every required ' + label + ' field before saving: ' + String.join(missingFields, ', ') + '.');
        }
    }

    private static void addSetupRecord(
        Metadata.DeployContainer container,
        GatewayMappingConfig config,
        String step,
        String sourceObject,
        String targetObject,
        String sourceLookupOnTarget,
        String developerName
    ) {
        Metadata.CustomMetadata record = baseMetadata(config, developerName, step + ' setup');
        addCustomMetadataValue(record, 'SF_Object__c', sourceObject);
        addCustomMetadataValue(record, 'SF_Field__c', SETUP_MARKER);
        addCustomMetadataValue(record, 'External_Field__c', SETUP_MARKER);
        addCustomMetadataValue(record, 'Mapping_Step__c', step);
        addCustomMetadataValue(record, 'Target_Object_API_Name__c', targetObject);
        addCustomMetadataValue(record, 'Target_Field_API_Name__c', null);
        addCustomMetadataValue(record, 'Source_Customer_Lookup_Field__c', step == 'Source' ? config.sourceCustomerLookupField : null);
        addCustomMetadataValue(record, 'Source_Customer_Target_Object__c', step == 'Source' ? config.sourceCustomerTargetObject : null);
        addCustomMetadataValue(record, 'Source_Email_Field_API_Name__c', step == 'Source' ? config.sourceEmailField : null);
        addCustomMetadataValue(record, 'Source_Lookup_On_Target_Field__c', sourceLookupOnTarget);
        container.addMetadata(record);
    }

    private static void addMappingRecords(
        Metadata.DeployContainer container,
        GatewayMappingConfig config,
        String step,
        String sourceObject,
        String targetObject,
        List<MappingRow> rows,
        String developerPrefix
    ) {
        if (rows == null) return;
        Integer index = 1;
        for (MappingRow row : rows) {
            if (row == null || String.isBlank(row.sourceField) || String.isBlank(row.targetField)) {
                continue;
            }
            String developerName = developerPrefix + String.valueOf(index).leftPad(3, '0');
            Metadata.CustomMetadata record = baseMetadata(config, developerName, step + ' mapping ' + index);
            addCustomMetadataValue(record, 'SF_Object__c', sourceObject);
            addCustomMetadataValue(record, 'SF_Field__c', row.sourceField);
            addCustomMetadataValue(record, 'External_Field__c', row.targetField);
            addCustomMetadataValue(record, 'Mapping_Step__c', step);
            addCustomMetadataValue(record, 'Target_Object_API_Name__c', targetObject);
            addCustomMetadataValue(record, 'Target_Field_API_Name__c', row.targetField);
            addCustomMetadataValue(record, 'Source_Customer_Lookup_Field__c', null);
            addCustomMetadataValue(record, 'Source_Customer_Target_Object__c', null);
            addCustomMetadataValue(record, 'Source_Email_Field_API_Name__c', null);
            addCustomMetadataValue(record, 'Source_Lookup_On_Target_Field__c', null);
            container.addMetadata(record);
            index++;
        }
    }

    private static Metadata.CustomMetadata baseMetadata(GatewayMappingConfig config, String developerName, String label) {
        Metadata.CustomMetadata record = new Metadata.CustomMetadata();
        record.fullName = 'Field_Mapping__mdt.' + developerName;
        record.label = label.length() > 40 ? label.substring(0, 40) : label;
        addCustomMetadataValue(record, 'Integration__c', config.gateway);
        addCustomMetadataValue(record, 'Action__c', ACTION_CREATE_INVOICE);
        addCustomMetadataValue(record, 'Mapping_Context__c', CONTEXT_PAYMENT_INVOICE);
        addCustomMetadataValue(record, 'Sync_Direction__c', 'Two-Way');
        addCustomMetadataValue(record, 'Is_Active__c', true);
        return record;
    }

    private static void addCustomMetadataValue(Metadata.CustomMetadata record, String fieldName, Object value) {
        Metadata.CustomMetadataValue metadataValue = new Metadata.CustomMetadataValue();
        metadataValue.field = fieldName;
        metadataValue.value = value;
        record.values.add(metadataValue);
    }

    private static MappingRow toMappingRow(Field_Mapping__mdt row, Boolean useExternalFieldAsTarget) {
        MappingRow mappingRow = new MappingRow();
        mappingRow.developerName = row.DeveloperName;
        mappingRow.sourceField = row.SF_Field__c;
        mappingRow.targetField = String.isNotBlank(row.Target_Field_API_Name__c)
            ? row.Target_Field_API_Name__c
            : (useExternalFieldAsTarget ? row.External_Field__c : null);
        return mappingRow;
    }

    private static FieldOption fieldOption(String label, String value, String typeName) {
        FieldOption option = new FieldOption();
        option.label = label;
        option.value = value;
        option.type = typeName;
        return option;
    }

    private static FieldOption toObjectOption(Schema.DescribeSObjectResult describeResult) {
        FieldOption option = new FieldOption();
        option.label = describeResult.getLabel() + ' (' + describeResult.getName() + ')';
        option.value = describeResult.getName();
        option.type = 'Object';
        return option;
    }

    private static Boolean hasCustomerLookup(Schema.DescribeSObjectResult describeResult) {
        for (Schema.SObjectField fieldToken : describeResult.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (fieldDescribe.getType() != Schema.DisplayType.Reference) {
                continue;
            }
            for (String referenceName : referenceNames(fieldDescribe)) {
                if (CUSTOMER_OBJECTS.contains(referenceName)) {
                    return true;
                }
            }
        }
        return false;
    }

    private static Boolean hasLookupTo(Schema.DescribeSObjectResult describeResult, String targetObjectApiName) {
        if (describeResult == null || String.isBlank(targetObjectApiName)) {
            return false;
        }
        for (Schema.SObjectField fieldToken : describeResult.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (fieldDescribe.getType() != Schema.DisplayType.Reference) {
                continue;
            }
            for (String referenceName : referenceNames(fieldDescribe)) {
                if (referenceName == targetObjectApiName) {
                    return true;
                }
            }
        }
        return false;
    }

    private static Schema.SObjectType getObjectTypeOrThrow(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required.');
        }
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(resolveObjectApiName(objectApiName));
        if (objectType == null) {
            throw new AuraHandledException('Object not found: ' + objectApiName);
        }
        return objectType;
    }

    private static String resolveObjectApiName(String objectApiName) {
        if (String.isBlank(objectApiName)) return objectApiName;
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (globalDescribe.containsKey(objectApiName)) {
            return objectApiName;
        }
        if (objectApiName.endsWith('__c')) {
            String namespacePrefix = getNamespacePrefix();
            if (String.isNotBlank(namespacePrefix) && !objectApiName.startsWith(namespacePrefix)) {
                String namespacedName = namespacePrefix + objectApiName;
                if (globalDescribe.containsKey(namespacedName)) {
                    return namespacedName;
                }
            }
        }
        return objectApiName;
    }

    private static String getNamespacePrefix() {
        String className = PaymentInvoiceMappingController.class.getName();
        if (className.contains('.')) {
            return className.substringBefore('.') + '__';
        }
        return '';
    }

    private static Schema.DescribeFieldResult getFieldDescribeOrThrow(String objectApiName, String fieldApiName) {
        Schema.SObjectType objectType = getObjectTypeOrThrow(objectApiName);
        Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
        String resolvedFieldApiName = resolveFieldApiName(fields, fieldApiName);
        if (String.isBlank(resolvedFieldApiName) || !fields.containsKey(resolvedFieldApiName.toLowerCase())) {
            throw new AuraHandledException('Field not found: ' + objectApiName + '.' + fieldApiName);
        }
        return fields.get(resolvedFieldApiName.toLowerCase()).getDescribe();
    }

    private static String resolveFieldApiName(Map<String, Schema.SObjectField> fields, String fieldApiName) {
        if (String.isBlank(fieldApiName) || fields == null) return fieldApiName;
        if (fields.containsKey(fieldApiName.toLowerCase())) {
            return fieldApiName;
        }
        if (fieldApiName.endsWith('__c')) {
            String namespacePrefix = getNamespacePrefix();
            if (String.isNotBlank(namespacePrefix) && !fieldApiName.startsWith(namespacePrefix)) {
                String namespacedField = namespacePrefix + fieldApiName;
                if (fields.containsKey(namespacedField.toLowerCase())) {
                    return namespacedField;
                }
            }
        }
        return fieldApiName;
    }

    private static String firstReferenceName(Schema.DescribeFieldResult fieldDescribe) {
        List<String> names = referenceNames(fieldDescribe);
        return names.isEmpty() ? null : names[0];
    }

    private static List<String> referenceNames(Schema.DescribeFieldResult fieldDescribe) {
        List<String> names = new List<String>();
        if (fieldDescribe == null) return names;
        for (Schema.SObjectType referenceType : fieldDescribe.getReferenceTo()) {
            names.add(referenceType.getDescribe().getName());
        }
        return names;
    }

    private static String normalizeGateway(String gateway) {
        String normalized = String.isBlank(gateway) ? 'stripe' : gateway.trim().toLowerCase();
        if (!SUPPORTED_GATEWAYS.contains(normalized)) {
            throw new AuraHandledException('Unsupported invoice mapping gateway: ' + gateway);
        }
        return normalized;
    }

    private static String normalizeStep(String step) {
        if (String.isBlank(step)) return '';
        String trimmed = step.trim();
        if (trimmed.equalsIgnoreCase('source')) return 'Source';
        if (trimmed.equalsIgnoreCase('invoice')) return 'Invoice';
        if (trimmed.equalsIgnoreCase('transaction')) return 'Transaction';
        return trimmed;
    }

    private class FieldOptionLabelComparator implements System.Comparator<FieldOption> {
        public Integer compare(FieldOption leftOption, FieldOption rightOption) {
            String leftLabel = leftOption == null || leftOption.label == null ? '' : leftOption.label.toLowerCase();
            String rightLabel = rightOption == null || rightOption.label == null ? '' : rightOption.label.toLowerCase();
            return leftLabel.compareTo(rightLabel);
        }
    }
}