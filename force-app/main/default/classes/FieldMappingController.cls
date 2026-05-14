/**
 * FieldMappingController - Handles field mapping between Salesforce and external systems (QB Online, Klaviyo)
 *
 * QB API Integration Setup:
 * 1. Create Named Credentials in Salesforce:
 *    - Set Name: "QuickBooksOnline"
 *    - Set URL: https://quickbooks.api.intuit.com
 *    - Use OAuth 2.0 for authentication
 *    - Add scope: com.intuit.quickbooks.accounting
 */
public with sharing class FieldMappingController {

    private static final String QB_API_ENDPOINT = 'callout:QuickBooksOnline';
    private static final String INTEGRATION_QBO = 'qbonline';
    private static final String INTEGRATION_SHOPIFY = 'shopify';
    private static final String DIRECTION_TWO_WAY = 'Two-Way';
    private static final String DIRECTION_SF_TO_QBO = 'SF to QBO';
    private static final String DIRECTION_QBO_TO_SF = 'QBO to SF';
    private static final String DIRECTION_SF_TO_SHOPIFY = 'SF to Shopify';
    private static final String DIRECTION_SHOPIFY_TO_SF = 'Shopify to SF';
    private static final Set<String> EXCLUSIVE_INTEGRATIONS = new Set<String>{
        INTEGRATION_QBO,
        INTEGRATION_SHOPIFY
    };
    @TestVisible private static List<Field_Mapping__mdt> testActiveMappings;
    private static final Set<String> VALID_QB_ENTITIES = new Set<String>{
        'Customer', 'Vendor', 'Item', 'Invoice', 'CreditMemo', 'PurchaseOrder', 'TaxCode'
    };
    private static final Map<String, String> SF_TO_QB_ENTITY = new Map<String, String>{
        'Account' => 'Customer',
        'Contact' => 'Customer',
        'Product2' => 'Item',
        'Order' => 'Invoice',
        'Invoice__c' => 'Invoice',
        'Credit_Memo__c' => 'CreditMemo',
        'Purchase_Order__c' => 'PurchaseOrder',
        'Item_Sales_Tax__c' => 'TaxCode'
    };

    private static final Set<String> VALID_SHOPIFY_ENTITIES = new Set<String>{
        'Customer', 'Order', 'Product', 'LineItem'
    };
    private static final Map<String, String> SF_TO_SHOPIFY_ENTITY = new Map<String, String>{
        'Account'   => 'Customer',
        'Order'     => 'Order',
        'Product2'  => 'Product',
        'OrderItem' => 'LineItem'
    };

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getOrderFields() {
        return getObjectFields('Order');
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getObjectFields(String objectName) {
        List<FieldWrapper> fields = new List<FieldWrapper>();
        try {
            if (String.isBlank(objectName)) {
                throw new IllegalArgumentException('Object name is required');
            }

            if (objectName != null && objectName.endsWith('Invoice__c')) {
                String actualInvoiceObject = InvoiceMappingController.getCustomInvoiceObjectName(); 
                if (String.isNotBlank(actualInvoiceObject)) {
                    objectName = actualInvoiceObject;
                }
            }
            
            Schema.SObjectType sObjectType = getSObjectType(objectName);
            if (sObjectType == null) {
                throw new IllegalArgumentException('Invalid object name: ' + objectName);
            }

            Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                if (fieldDescribe.isAccessible()) {
                    fields.add(new FieldWrapper(
                        fieldDescribe.getLabel(),
                        fieldDescribe.getName(),
                        mapSalesforceType(fieldDescribe.getType())
                    ));
                }
            }

            fields.sort();

            List<Map<String, String>> result = new List<Map<String, String>>();
            for (FieldWrapper field : fields) {
                Map<String, String> fieldData = new Map<String, String>();
                fieldData.put('label', field.label);
                fieldData.put('value', field.value);
                fieldData.put('type', field.type);
                result.add(fieldData);
            }
            return result;
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBridge', 'FieldMappingController.getObjectFields', e, null, null);
            throw new AuraHandledException('Unable to retrieve fields: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getShopifyFields(String sfObject, String shopifyObject) {
        String shopifyEntity = resolveShopifyEntity(sfObject, shopifyObject);
        return convertQBFieldDefinitions(getFallbackShopifyFieldDefinitions(shopifyEntity));
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getFedExFields(String actionName, String direction) {
        return convertQBFieldDefinitions(getFedExFieldDefinitions(actionName, direction));
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getExistingFedExMappings(String actionName, String sfObject) {
        return getCarrierMappings('fedex', actionName, sfObject);
    }

    @AuraEnabled
    public static String saveFedExFieldMappings(String actionName, String sfObject, String mappingsJson) {
        return saveCarrierFieldMappings('fedex', actionName, sfObject, mappingsJson);
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getUPSFields(String actionName, String direction) {
        return convertQBFieldDefinitions(getUPSFieldDefinitions(actionName, direction));
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getExistingUPSMappings(String actionName, String sfObject) {
        return getCarrierMappings('ups', actionName, sfObject);
    }

    @AuraEnabled
    public static String saveUPSFieldMappings(String actionName, String sfObject, String mappingsJson) {
        return saveCarrierFieldMappings('ups', actionName, sfObject, mappingsJson);
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getQuickBooksFields(String sfObject, String qbObject) {
        String qbEntity = resolveQBEntity(sfObject, qbObject);

        try {
            Map<String, QBFieldDefinition> fieldDefinitions = fetchQBFieldDefinitions(qbEntity);
            return convertQBFieldDefinitions(fieldDefinitions);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'QB schema lookup failed for ' + qbEntity + ': ' + e.getMessage());
            ErrorLogUtility.logException('QuickBooks', 'FieldMappingController.getQuickBooksFields', e, null, null);
            return convertQBFieldDefinitions(getFallbackQBFieldDefinitions(qbEntity));
        }
    }

    @AuraEnabled
    public static Map<String, Object> getMappingDirectionAvailability(String integration, String sfObject) {
        return buildMappingDirectionAvailability(integration, sfObject);
    }

    @AuraEnabled
    public static String saveFieldMappings(String integration, String sfObject, String qbObject, String mappingsJson) {
        try {
            if (integration == INTEGRATION_QBO && (sfObject == 'Order' || sfObject.endsWith('Invoice__c'))) {
                String ns = getNamespacePrefix();
                String otherObject = (sfObject == 'Order') ? (ns + 'Invoice__c') : 'Order';
                List<Field_Mapping__mdt> existingConflict = [
                    SELECT Id
                    FROM Field_Mapping__mdt
                    WHERE Integration__c = 'qbonline' AND SF_Object__c = :otherObject AND Is_Active__c = true
                    LIMIT 1
                ];
                if (!existingConflict.isEmpty()) {
                    throw new AuraHandledException(
                        'Conflict Error: You cannot map both Order and ' + otherObject +
                        ' to QuickBooks Invoice. Please clear ' + otherObject + ' mappings first.'
                    );
                }
            }

            List<Object> rawList = String.isBlank(mappingsJson)
                ? new List<Object>()
                : (List<Object>) JSON.deserializeUntyped(mappingsJson);
            List<MappingRow> requestedMappings = new List<MappingRow>();
            Set<String> requestedExternalFields = new Set<String>();

            for (Object objRow : rawList) {
                Map<String, Object> row = (Map<String, Object>) objRow;
                String sfField = (String) row.get('sfField');
                String extField = (String) row.get('externalField');
                String syncDirection = normalizeMappingDirection(integration, (String) row.get('syncDirection'));

                if (String.isBlank(sfField) || String.isBlank(extField)) {
                    continue;
                }
                if (requestedExternalFields.contains(extField)) {
                    String integrationLabel = integration == INTEGRATION_SHOPIFY ? 'Shopify' : 'QuickBooks';
                    throw new AuraHandledException('Each ' + integrationLabel + ' field can only be mapped once.');
                }
                requestedMappings.add(new MappingRow(sfField, extField, syncDirection));
                requestedExternalFields.add(extField);
            }

            validateObjectDirectionAvailability(integration, sfObject, requestedMappings);
            validateRequiredMappings(integration, sfObject, qbObject, requestedMappings);
            validateDataTypes(integration, sfObject, qbObject, requestedMappings);

            List<Field_Mapping__mdt> existingMappings = [
                SELECT DeveloperName, External_Field__c, Is_Active__c
                FROM Field_Mapping__mdt
                WHERE Integration__c = :integration AND SF_Object__c = :sfObject
            ];

            List<String> recordsToDeactivate = new List<String>();
            for (Field_Mapping__mdt existingRecord : existingMappings) {
                if (existingRecord.Is_Active__c && !requestedExternalFields.contains(existingRecord.External_Field__c)) {
                    recordsToDeactivate.add(existingRecord.DeveloperName);
                }
            }

            String nsPrefix = getNamespacePrefix();
            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            for (String developerName : recordsToDeactivate) {
                Metadata.CustomMetadata inactiveMetadata = new Metadata.CustomMetadata();
                inactiveMetadata.fullName = nsPrefix + 'Field_Mapping__mdt.' + developerName;
                inactiveMetadata.label = developerName;
                addCustomMetadataValue(inactiveMetadata, 'Is_Active__c', false);
                mdContainer.addMetadata(inactiveMetadata);
            }

            for (MappingRow row : requestedMappings) {
                Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
                customMetadata.fullName = nsPrefix + 'Field_Mapping__mdt.' + buildRecordName(integration, sfObject, row.externalField);
                String label = sfObject + ' ' + row.sfField;
                customMetadata.label = label.length() > 40 ? label.substring(0, 40) : label;

                addCustomMetadataValue(customMetadata, 'Integration__c', integration);
                addCustomMetadataValue(customMetadata, 'SF_Object__c', sfObject);
                addCustomMetadataValue(customMetadata, 'SF_Field__c', row.sfField);
                addCustomMetadataValue(customMetadata, 'External_Field__c', row.externalField);
                addCustomMetadataValue(customMetadata, 'Sync_Direction__c', row.syncDirection);
                addCustomMetadataValue(customMetadata, 'Is_Active__c', true);

                mdContainer.addMetadata(customMetadata);
            }

            if (Test.isRunningTest()) {
                return 'Mappings Deployment Started! Job ID: 0Af000000000000';
            }

            if (requestedMappings.isEmpty() && recordsToDeactivate.isEmpty()) {
                return 'Mappings updated successfully.';
            }

            Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, null);
            return 'Mappings Deployment Started! Job ID: ' + jobId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            ErrorLogUtility.logException(
                integration == INTEGRATION_SHOPIFY ? 'Shopify' : 'QuickBooks',
                'FieldMappingController.saveFieldMappings',
                e,
                null,
                null
            );
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getSalesforceObjects() {
        List<Map<String, String>> objects = new List<Map<String, String>>();
        List<String> allowedObjects = new List<String>{
            'Account', 'Contact', 'Order', 'OrderItem', 'Invoice__c',
            'Product2', 'Credit_Memo__c', 'Purchase_Order__c',
            'Stocking_Location__c', 'Item_Sales_Tax__c',
            'Case', 'ReturnOrder', 'Shipment',
            'Carrier_Shipment__c', 'Carrier_Package__c',
            'Carrier_Rate_Quote__c', 'Carrier_Tracking_Event__c'
        };

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (String objApiName : allowedObjects) {
            try {
                Schema.SObjectType sType = getSObjectType(objApiName);
                if (sType == null) continue;

                Schema.DescribeSObjectResult describe = sType.getDescribe();
                Map<String, String> objectData = new Map<String, String>();
                objectData.put('label', describe.getLabel());
                objectData.put('value', describe.getName());
                objects.add(objectData);
            } catch (Exception e) {
                System.debug('Object not found: ' + objApiName);
            }
        }
        return objects;
    }

    private static String getNamespacePrefix() {
        String className = FieldMappingController.class.getName();
        if (className.contains('.')) {
            return className.substringBefore('.') + '__';
        }
        return '';
    }

    /**
     * Helper to resolve SObjectType while accounting for package namespaces
     */
    private static Schema.SObjectType getSObjectType(String objApiName) {
        if (String.isBlank(objApiName)) return null;

        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        Schema.SObjectType sType = gd.get(objApiName);

        // If not found and looks like a custom object, try prepending the current namespace
        if (sType == null && objApiName.endsWith('__c')) {
            String nsPrefix = getNamespacePrefix();
            if (String.isNotBlank(nsPrefix) && !objApiName.startsWith(nsPrefix)) {
                sType = gd.get(nsPrefix + objApiName);
            }
        }
        return sType;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getExistingMappings(String integration, String sfObject) {
        List<Map<String, String>> savedMappings = new List<Map<String, String>>();
        try {
            List<Field_Mapping__mdt> records = [
                SELECT DeveloperName, SF_Field__c, External_Field__c, Sync_Direction__c
                FROM Field_Mapping__mdt
                WHERE Integration__c = :integration AND SF_Object__c = :sfObject AND Is_Active__c = true
            ];

            for (Field_Mapping__mdt record : records) {
                if (String.isBlank(record.SF_Field__c) || String.isBlank(record.External_Field__c)) {
                    continue;
                }
                Map<String, String> mapping = new Map<String, String>();
                mapping.put('developerName', record.DeveloperName);
                mapping.put('sfField', record.SF_Field__c);
                mapping.put('externalField', record.External_Field__c);
                mapping.put('syncDirection', String.isNotBlank(record.Sync_Direction__c) ? record.Sync_Direction__c : 'Two-Way');
                savedMappings.add(mapping);
            }
        } catch (Exception e) {
            System.debug('Error loading metadata: ' + e.getMessage());
            ErrorLogUtility.logException(
                integration == INTEGRATION_SHOPIFY ? 'Shopify' : 'QuickBooks',
                'FieldMappingController.getExistingMappings',
                e,
                null,
                null
            );
        }
        return savedMappings;
    }

    private static void validateRequiredMappings(String sfObject, String qbObject, List<MappingRow> requestedMappings) {
        String qbEntity = resolveQBEntity(sfObject, qbObject);
        Map<String, QBFieldDefinition> qbFields = fetchQBFieldDefinitionsSafe(qbEntity);
        Set<String> mappedExternalFields = new Set<String>();
        for (MappingRow row : requestedMappings) {
            mappedExternalFields.add(row.externalField);
        }

        for (QBFieldDefinition fieldDef : qbFields.values()) {
            if (fieldDef.required && !mappedExternalFields.contains(fieldDef.value)) {
                throw new AuraHandledException('Map every required QuickBooks field before saving.');
            }
        }
    }

    private static void validateRequiredMappings(String integration, String sfObject, String extObject, List<MappingRow> requestedMappings) {
        Map<String, QBFieldDefinition> fieldDefs;
        String integrationLabel;
        if (integration == INTEGRATION_SHOPIFY) {
            String shopifyEntity = resolveShopifyEntity(sfObject, extObject);
            fieldDefs = getFallbackShopifyFieldDefinitions(shopifyEntity);
            integrationLabel = 'Shopify';
        } else {
            String qbEntity = resolveQBEntity(sfObject, extObject);
            fieldDefs = fetchQBFieldDefinitionsSafe(qbEntity);
            integrationLabel = 'QuickBooks';
        }

        Set<String> mappedExternalFields = new Set<String>();
        for (MappingRow row : requestedMappings) {
            mappedExternalFields.add(row.externalField);
        }

        for (QBFieldDefinition fieldDef : fieldDefs.values()) {
            if (fieldDef.required && !mappedExternalFields.contains(fieldDef.value)) {
                throw new AuraHandledException('Map every required ' + integrationLabel + ' field before saving.');
            }
        }
    }

    private static void validateDataTypes(String sfObject, String qbObject, List<MappingRow> requestedMappings) {
        validateDataTypes(null, sfObject, qbObject, requestedMappings);
    }

    private static void validateDataTypes(String integration, String sfObject, String extObject, List<MappingRow> requestedMappings) {
        Map<String, String> sfFieldTypes = new Map<String, String>();
        for (Map<String, String> sfField : getObjectFields(sfObject)) {
            sfFieldTypes.put(sfField.get('value'), sfField.get('type'));
        }

        Map<String, QBFieldDefinition> extFields;
        String integrationLabel;
        if (integration == INTEGRATION_SHOPIFY) {
            String shopifyEntity = resolveShopifyEntity(sfObject, extObject);
            extFields = getFallbackShopifyFieldDefinitions(shopifyEntity);
            integrationLabel = 'Shopify';
        } else {
            extFields = fetchQBFieldDefinitionsSafe(resolveQBEntity(sfObject, extObject));
            integrationLabel = 'QuickBooks';
        }

        for (MappingRow row : requestedMappings) {
            if (!sfFieldTypes.containsKey(row.sfField) || !extFields.containsKey(row.externalField)) {
                continue;
            }

            String sfType = sfFieldTypes.get(row.sfField);
            String extType = extFields.get(row.externalField).type;
            if (!isTypeMatch(sfType, extType)) {
                throw new AuraHandledException(
                    'Field type mismatch for ' + integrationLabel + ' field ' + row.externalField + '.'
                );
            }
        }
    }

    private static Boolean isTypeMatch(String sfType, String qbType) {
        String normalizedSfType = normalizeType(sfType);
        String normalizedQbType = normalizeType(qbType);
        return normalizedQbType == null || normalizedSfType == normalizedQbType;
    }

    private static String normalizeType(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String upperValue = value.trim().toUpperCase();
        if (upperValue == 'CURRENCY' || upperValue == 'DOUBLE' || upperValue == 'INTEGER' ||
            upperValue == 'PERCENT' || upperValue == 'DECIMAL' || upperValue == 'LONG' || upperValue == 'NUMBER') {
            return 'NUMBER';
        }
        if (upperValue == 'DATE' || upperValue == 'DATETIME') {
            return 'DATE';
        }
        if (upperValue == 'BOOLEAN') {
            return 'BOOLEAN';
        }
        return 'STRING';
    }

    private static Map<String, Object> buildMappingDirectionAvailability(String integration, String sfObject) {
        Map<String, Object> result = new Map<String, Object>();
        String normalizedIntegration = normalizeIntegration(integration);
        String otherIntegration = getPeerIntegration(normalizedIntegration);
        String otherLabel = getIntegrationLabel(otherIntegration);

        Boolean inboundAllowed = true;
        Boolean outboundAllowed = true;
        String inboundConflictDirection;
        String outboundConflictDirection;

        if (otherIntegration != null && String.isNotBlank(sfObject)) {
            for (Field_Mapping__mdt mapping : getActiveMappingsForAvailability(otherIntegration, sfObject)) {
                if (directionTouchesInbound(mapping.Sync_Direction__c)) {
                    inboundAllowed = false;
                    if (String.isBlank(inboundConflictDirection)) {
                        inboundConflictDirection = String.isBlank(mapping.Sync_Direction__c)
                            ? DIRECTION_TWO_WAY
                            : mapping.Sync_Direction__c;
                    }
                }
                if (directionTouchesOutbound(mapping.Sync_Direction__c)) {
                    outboundAllowed = false;
                    if (String.isBlank(outboundConflictDirection)) {
                        outboundConflictDirection = String.isBlank(mapping.Sync_Direction__c)
                            ? DIRECTION_TWO_WAY
                            : mapping.Sync_Direction__c;
                    }
                }
            }
        }

        Boolean twoWayAllowed = inboundAllowed && outboundAllowed;
        result.put('integration', normalizedIntegration);
        result.put('sfObject', sfObject);
        result.put('otherIntegration', otherIntegration);
        result.put('inboundAllowed', inboundAllowed);
        result.put('outboundAllowed', outboundAllowed);
        result.put('twoWayAllowed', twoWayAllowed);
        result.put('allDirectionsBlocked', !inboundAllowed && !outboundAllowed);
        result.put('otherIntegrationLabel', otherLabel);
        result.put('inboundConflictDirection', inboundConflictDirection);
        result.put('outboundConflictDirection', outboundConflictDirection);
        result.put(
            'message',
            buildAvailabilityMessage(
                sfObject,
                otherLabel,
                inboundAllowed,
                outboundAllowed,
                inboundConflictDirection,
                outboundConflictDirection
            )
        );
        return result;
    }

    private static String buildAvailabilityMessage(
        String sfObject,
        String otherLabel,
        Boolean inboundAllowed,
        Boolean outboundAllowed,
        String inboundConflictDirection,
        String outboundConflictDirection
    ) {
        if (inboundAllowed && outboundAllowed) {
            return '';
        }
        String objectLabel = String.isBlank(sfObject) ? 'this object' : sfObject;
        if (!inboundAllowed && !outboundAllowed) {
            if (inboundConflictDirection == DIRECTION_TWO_WAY || outboundConflictDirection == DIRECTION_TWO_WAY) {
                return 'Cannot create Two-Way mapping. ' + otherLabel + ' already has Two-Way mapping for ' +
                    objectLabel + '.';
            }
            return 'Cannot create Two-Way mapping. ' + otherLabel +
                ' already has inbound and outbound mappings for ' + objectLabel + '.';
        }
        if (!inboundAllowed) {
            return 'Cannot create inbound mapping. ' + otherLabel + ' already has ' +
                inboundConflictDirection + ' mapping for ' + objectLabel + '.';
        }
        return 'Cannot create outbound mapping. ' + otherLabel + ' already has ' +
            outboundConflictDirection + ' mapping for ' + objectLabel + '.';
    }

    private static void validateObjectDirectionAvailability(
        String integration,
        String sfObject,
        List<MappingRow> requestedMappings
    ) {
        if (!isQboOrShopify(integration) || requestedMappings.isEmpty()) {
            return;
        }

        Map<String, Object> availability = buildMappingDirectionAvailability(integration, sfObject);
        Boolean inboundAllowed = (Boolean) availability.get('inboundAllowed');
        Boolean outboundAllowed = (Boolean) availability.get('outboundAllowed');
        String message = (String) availability.get('message');

        for (MappingRow row : requestedMappings) {
            if (!inboundAllowed && directionTouchesInbound(row.syncDirection)) {
                throw new AuraHandledException('Mapping Direction Conflict: ' + message);
            }
            if (!outboundAllowed && directionTouchesOutbound(row.syncDirection)) {
                throw new AuraHandledException('Mapping Direction Conflict: ' + message);
            }
        }
    }

    private static List<Field_Mapping__mdt> getActiveMappingsForAvailability(String integration, String sfObject) {
        List<Field_Mapping__mdt> records = new List<Field_Mapping__mdt>();
        if (String.isBlank(integration) || String.isBlank(sfObject)) {
            return records;
        }

        if (Test.isRunningTest() && testActiveMappings != null) {
            for (Field_Mapping__mdt mapping : testActiveMappings) {
                if (mapping != null &&
                    mapping.Integration__c == integration &&
                    mapping.SF_Object__c == sfObject &&
                    mapping.Is_Active__c == true) {
                    records.add(mapping);
                }
            }
            return records;
        }

        return [
            SELECT Integration__c, SF_Object__c, Sync_Direction__c, Is_Active__c
            FROM Field_Mapping__mdt
            WHERE Integration__c = :integration
            AND SF_Object__c = :sfObject
            AND Is_Active__c = true
        ];
    }

    private static Boolean directionTouchesInbound(String syncDirection) {
        String direction = String.isBlank(syncDirection) ? DIRECTION_TWO_WAY : syncDirection;
        return direction == DIRECTION_TWO_WAY ||
            direction == DIRECTION_QBO_TO_SF ||
            direction == DIRECTION_SHOPIFY_TO_SF;
    }

    private static Boolean directionTouchesOutbound(String syncDirection) {
        String direction = String.isBlank(syncDirection) ? DIRECTION_TWO_WAY : syncDirection;
        return direction == DIRECTION_TWO_WAY ||
            direction == DIRECTION_SF_TO_QBO ||
            direction == DIRECTION_SF_TO_SHOPIFY;
    }

    private static String normalizeMappingDirection(String integration, String syncDirection) {
        if (!isQboOrShopify(integration)) {
            return syncDirection;
        }

        String direction = String.isBlank(syncDirection) ? DIRECTION_TWO_WAY : syncDirection.trim();
        Set<String> validDirections = normalizeIntegration(integration) == INTEGRATION_SHOPIFY
            ? new Set<String>{ DIRECTION_SF_TO_SHOPIFY, DIRECTION_SHOPIFY_TO_SF, DIRECTION_TWO_WAY }
            : new Set<String>{ DIRECTION_SF_TO_QBO, DIRECTION_QBO_TO_SF, DIRECTION_TWO_WAY };

        if (!validDirections.contains(direction)) {
            throw new AuraHandledException('Invalid sync direction for ' + getIntegrationLabel(integration) + ' mappings.');
        }
        return direction;
    }

    private static String normalizeIntegration(String integration) {
        return String.isBlank(integration) ? '' : integration.trim().toLowerCase();
    }

    private static String getPeerIntegration(String integration) {
        String normalized = normalizeIntegration(integration);
        if (normalized == INTEGRATION_QBO) {
            return INTEGRATION_SHOPIFY;
        }
        if (normalized == INTEGRATION_SHOPIFY) {
            return INTEGRATION_QBO;
        }
        return null;
    }

    private static Boolean isQboOrShopify(String integration) {
        String normalized = normalizeIntegration(integration);
        return EXCLUSIVE_INTEGRATIONS.contains(normalized);
    }

    private static String getIntegrationLabel(String integration) {
        String normalized = normalizeIntegration(integration);
        if (normalized == INTEGRATION_SHOPIFY) {
            return 'Shopify';
        }
        if (normalized == INTEGRATION_QBO) {
            return 'QuickBooks';
        }
        return 'the other integration';
    }

    private static Map<String, QBFieldDefinition> fetchQBFieldDefinitionsSafe(String qbEntity) {
        try {
            return fetchQBFieldDefinitions(qbEntity);
        } catch (Exception e) {
            return getFallbackQBFieldDefinitions(qbEntity);
        }
    }

    private static Map<String, QBFieldDefinition> fetchQBFieldDefinitions(String qbEntity) {
        Map<String, QBFieldDefinition> fieldDefinitions = getFallbackQBFieldDefinitions(qbEntity);
        List<Map<String, Object>> apiFields = fetchQBFieldsFromAPI(qbEntity);

        for (Map<String, Object> fieldData : apiFields) {
            String fieldPath = (String) fieldData.get('value');
            if (String.isBlank(fieldPath)) {
                continue;
            }

            QBFieldDefinition definition = fieldDefinitions.containsKey(fieldPath)
                ? fieldDefinitions.get(fieldPath)
                : new QBFieldDefinition();
            definition.label = (String) fieldData.get('label');
            definition.value = fieldPath;
            String apiType = normalizeType((String) fieldData.get('type'));
            if (String.isBlank(definition.type) || definition.type == 'STRING' || apiType != 'STRING') {
                definition.type = apiType;
            }
            if (definition.required == null) {
                definition.required = false;
            }
            fieldDefinitions.put(fieldPath, definition);
        }

        return fieldDefinitions;
    }

    private static Map<String, QBFieldDefinition> getFallbackQBFieldDefinitions(String qbEntity) {
        Map<String, QBFieldDefinition> qbFields = new Map<String, QBFieldDefinition>();

        if (qbEntity == 'Customer') {
            addQBFieldDefinition(qbFields, 'QB - DisplayName', 'DisplayName', 'STRING', true);
            addQBFieldDefinition(qbFields, 'QB - CompanyName', 'CompanyName', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - FamilyName', 'FamilyName', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - GivenName', 'GivenName', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - AcctNum', 'AcctNum', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - Email', 'PrimaryEmailAddr.Address', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - Phone', 'PrimaryPhone.FreeFormNumber', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - Street', 'BillAddr.Line1', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - City', 'BillAddr.City', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - Notes', 'Notes', 'STRING', false);
        } else if (qbEntity == 'Vendor') {
            addQBFieldDefinition(qbFields, 'QB - DisplayName', 'DisplayName', 'STRING', true);
            addQBFieldDefinition(qbFields, 'QB - CompanyName', 'CompanyName', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - FamilyName', 'FamilyName', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - GivenName', 'GivenName', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - Primary Email', 'PrimaryEmailAddr.Address', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - Primary Phone', 'PrimaryPhone.FreeFormNumber', 'STRING', false);
        } else if (qbEntity == 'Item') {
            addQBFieldDefinition(qbFields, 'QB - Name', 'Name', 'STRING', true);
            addQBFieldDefinition(qbFields, 'QB - Description', 'Description', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - Sku', 'Sku', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - UnitPrice', 'UnitPrice', 'NUMBER', false);
        } else if (qbEntity == 'Invoice') {
            addQBFieldDefinition(qbFields, 'QB - CustomerRef.value', 'CustomerRef.value', 'STRING', true);
            addQBFieldDefinition(qbFields, 'QB - DocNumber', 'DocNumber', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - TotalAmt', 'TotalAmt', 'NUMBER', false);
            addQBFieldDefinition(qbFields, 'QB - TxnDate', 'TxnDate', 'DATE', false);
            addQBFieldDefinition(qbFields, 'QB - Customer Memo', 'CustomerMemo.value', 'STRING', false);
        } else if (qbEntity == 'CreditMemo') {
            addQBFieldDefinition(qbFields, 'QB - CustomerRef.value', 'CustomerRef.value', 'STRING', true);
            addQBFieldDefinition(qbFields, 'QB - DocNumber', 'DocNumber', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - TxnDate', 'TxnDate', 'DATE', false);
            addQBFieldDefinition(qbFields, 'QB - TotalAmt', 'TotalAmt', 'NUMBER', false);
        } else if (qbEntity == 'PurchaseOrder') {
            addQBFieldDefinition(qbFields, 'QB - VendorRef.value', 'VendorRef.value', 'STRING', true);
            addQBFieldDefinition(qbFields, 'QB - DocNumber', 'DocNumber', 'STRING', false);
            addQBFieldDefinition(qbFields, 'QB - TxnDate', 'TxnDate', 'DATE', false);
            addQBFieldDefinition(qbFields, 'QB - TotalAmt', 'TotalAmt', 'NUMBER', false);
        } else if (qbEntity == 'TaxCode') {
            addQBFieldDefinition(qbFields, 'QB - Name', 'Name', 'STRING', true);
            addQBFieldDefinition(qbFields, 'QB - Description', 'Description', 'STRING', false);
        }

        return qbFields;
    }

    private static void addQBFieldDefinition(
        Map<String, QBFieldDefinition> fieldMap,
        String label,
        String value,
        String type,
        Boolean required
    ) {
        QBFieldDefinition definition = new QBFieldDefinition();
        definition.label = label;
        definition.value = value;
        definition.type = normalizeType(type);
        definition.required = required;
        fieldMap.put(value, definition);
    }

    private static List<Map<String, Object>> convertQBFieldDefinitions(Map<String, QBFieldDefinition> definitions) {
        List<QBFieldDefinition> sortableFields = new List<QBFieldDefinition>();
        sortableFields.addAll(definitions.values());
        sortableFields.sort();

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (QBFieldDefinition definition : sortableFields) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('label', definition.label);
            row.put('value', definition.value);
            row.put('type', definition.type);
            row.put('required', definition.required == true);
            result.add(row);
        }
        return result;
    }

    private static List<Map<String, Object>> fetchQBFieldsFromAPI(String qbEntity) {
        List<Map<String, Object>> qbFields = new List<Map<String, Object>>();

        List<Quickbridge_Config__mdt> configs = [
            SELECT QuickBooks_Realm_ID__c
            FROM Quickbridge_Config__mdt
            WHERE QuickBooks_Realm_ID__c != null
            LIMIT 1
        ];
        if (configs.isEmpty() || String.isBlank(configs[0].QuickBooks_Realm_ID__c)) {
            throw new CalloutException('Realm ID is missing in configuration.');
        }

        String realmId = configs[0].QuickBooks_Realm_ID__c.trim();

        HttpRequest req = new HttpRequest();
        String query = EncodingUtil.urlEncode('SELECT * FROM ' + qbEntity + ' MAXRESULTS 1', 'UTF-8');
        req.setEndpoint(QB_API_ENDPOINT + '/v3/company/' + realmId + '/query?query=' + query);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(20000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            ErrorLogUtility.logCalloutFailure(
                'QuickBooks',
                'FieldMappingController.fetchQBFieldsFromAPI',
                'QB API error while loading field metadata: ' + res.getStatusCode() + ' ' + res.getBody(),
                res.getStatusCode(),
                null,
                null
            );
            throw new CalloutException('QB API error: ' + res.getStatusCode());
        }

        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> queryResponse = (Map<String, Object>) responseBody.get('QueryResponse');

        if (queryResponse != null && queryResponse.containsKey(qbEntity)) {
            List<Object> entities = (List<Object>) queryResponse.get(qbEntity);
            if (!entities.isEmpty()) {
                Map<String, Object> entityData = (Map<String, Object>) entities[0];
                flattenFields(entityData, '', qbFields);
            }
        }
        return qbFields;
    }

    private static void flattenFields(
        Map<String, Object> jsonMap,
        String prefix,
        List<Map<String, Object>> resultList
    ) {
        for (String key : jsonMap.keySet()) {
            Object value = jsonMap.get(key);
            String fieldPath = String.isBlank(prefix) ? key : prefix + '.' + key;

            if (value instanceof Map<String, Object>) {
                flattenFields((Map<String, Object>) value, fieldPath, resultList);
            } else if (value instanceof List<Object>) {
                continue;
            } else {
                String qbType = 'STRING';
                if (value instanceof Boolean) {
                    qbType = 'BOOLEAN';
                } 
                else if (value instanceof Integer || value instanceof Long || value instanceof Double || value instanceof Decimal) {
                    qbType = 'NUMBER';
                } 
                else {
                    String lowerPath = fieldPath.toLowerCase();
                    if (lowerPath.contains('date') || lowerPath.contains('time')) {
                        qbType = 'DATE';
                    }
                }

                Map<String, Object> fieldData = new Map<String, Object>();
                fieldData.put('label', 'QB - ' + fieldPath);
                fieldData.put('value', fieldPath);
                fieldData.put('type', qbType);
                resultList.add(fieldData);
            }
        }
    }

    private static String resolveShopifyEntity(String sfObject, String shopifyObject) {
        if (String.isNotBlank(shopifyObject) && VALID_SHOPIFY_ENTITIES.contains(shopifyObject)) {
            return shopifyObject;
        }
        if (String.isNotBlank(sfObject) && SF_TO_SHOPIFY_ENTITY.containsKey(sfObject)) {
            return SF_TO_SHOPIFY_ENTITY.get(sfObject);
        }
        return 'Customer';
    }

    private static Map<String, QBFieldDefinition> getFallbackShopifyFieldDefinitions(String entity) {
        Map<String, QBFieldDefinition> fields = new Map<String, QBFieldDefinition>();

        if (entity == 'Customer') {
            addQBFieldDefinition(fields, 'Shopify - id',                             'id',                                       'STRING',  true);
            addQBFieldDefinition(fields, 'Shopify - email',                          'email',                                    'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - first_name',                     'first_name',                               'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - last_name',                      'last_name',                                'STRING',  true);
            addQBFieldDefinition(fields, 'Shopify - phone',                          'phone',                                    'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - tax_exempt',                     'tax_exempt',                               'BOOLEAN', false);
            addQBFieldDefinition(fields, 'Shopify - tags',                           'tags',                                     'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - total_spent',                    'total_spent',                              'NUMBER',  false);
            addQBFieldDefinition(fields, 'Shopify - orders_count',                   'orders_count',                             'NUMBER',  false);
            addQBFieldDefinition(fields, 'Shopify - default_address.address1',       'default_address.address1',                 'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - default_address.city',           'default_address.city',                     'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - default_address.province',       'default_address.province',                 'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - default_address.zip',            'default_address.zip',                      'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - default_address.country',        'default_address.country',                  'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - sms_marketing_consent.state',    'sms_marketing_consent.state',              'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - sms_marketing_consent.opt_in_level', 'sms_marketing_consent.opt_in_level',   'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - email_marketing_consent.state',  'email_marketing_consent.state',            'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - email_marketing_consent.opt_in_level', 'email_marketing_consent.opt_in_level', 'STRING', false);
        } else if (entity == 'Order') {
            addQBFieldDefinition(fields, 'Shopify - id',                   'id',                    'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - name',                 'name',                  'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - created_at',           'created_at',            'DATE',    false);
            addQBFieldDefinition(fields, 'Shopify - total_price',          'total_price',           'NUMBER',  false);
            addQBFieldDefinition(fields, 'Shopify - total_discounts',      'total_discounts',       'NUMBER',  false);
            addQBFieldDefinition(fields, 'Shopify - total_tax',            'total_tax',             'NUMBER',  false);
            addQBFieldDefinition(fields, 'Shopify - financial_status',     'financial_status',      'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - fulfillment_status',   'fulfillment_status',    'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - payment_gateway_names','payment_gateway_names', 'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - contact_email',        'contact_email',         'STRING',  false);
            addQBFieldDefinition(fields, 'Shopify - cancel_reason',        'cancel_reason',         'STRING',  false);
        } else if (entity == 'Product') {
            addQBFieldDefinition(fields, 'Shopify - id',     'id',     'STRING',  true);
            addQBFieldDefinition(fields, 'Shopify - title',  'title',  'STRING',  true);
            addQBFieldDefinition(fields, 'Shopify - status', 'status', 'STRING',  false);
        } else if (entity == 'LineItem') {
            addQBFieldDefinition(fields, 'Shopify - id',       'id',       'STRING', false);
            addQBFieldDefinition(fields, 'Shopify - quantity', 'quantity', 'NUMBER', false);
            addQBFieldDefinition(fields, 'Shopify - price',    'price',    'NUMBER', false);
            addQBFieldDefinition(fields, 'Shopify - sku',      'sku',      'STRING', false);
            addQBFieldDefinition(fields, 'Shopify - title',    'title',    'STRING', false);
        }

        return fields;
    }

    private static String resolveQBEntity(String sfObject, String qbObject) {
        if (!String.isBlank(qbObject) && VALID_QB_ENTITIES.contains(qbObject)) {
            return qbObject;
        }

        String key = sfObject;
        if (String.isNotBlank(sfObject) && sfObject.endsWith('__c') && sfObject.contains('__')) {
            // Check if it's a namespaced custom object (e.g. pkg__Object__c)
            if (sfObject.indexOf('__') != sfObject.lastIndexOf('__')) {
                key = sfObject.substringAfter('__');
            }
        }

        if (!String.isBlank(key) && SF_TO_QB_ENTITY.containsKey(key)) {
            return SF_TO_QB_ENTITY.get(key);
        }
        return 'Invoice';
    }

    private static List<Map<String, String>> getCarrierMappings(String integration, String actionName, String sfObject) {
        List<Map<String, String>> savedMappings = new List<Map<String, String>>();
        try {
            List<Field_Mapping__mdt> records = queryCarrierMappings(
                integration,
                actionName,
                sfObject,
                true
            );
            for (Field_Mapping__mdt record : records) {
                if (String.isBlank(record.SF_Field__c) || String.isBlank(record.External_Field__c)) {
                    continue;
                }
                Map<String, String> mapping = new Map<String, String>();
                mapping.put('developerName', record.DeveloperName);
                mapping.put('sfField', record.SF_Field__c);
                mapping.put('externalField', record.External_Field__c);
                mapping.put('syncDirection', toProviderDirection(integration, record.Sync_Direction__c));
                savedMappings.add(mapping);
            }
        } catch (Exception e) {
            System.debug('Error loading carrier mappings: ' + e.getMessage());
            ErrorLogUtility.logException(
                integration == 'fedex' ? 'FedEx' : 'UPS',
                'FieldMappingController.getCarrierMappings',
                e,
                null,
                null
            );
        }
        return savedMappings;
    }

    private static String saveCarrierFieldMappings(String integration, String actionName, String sfObject, String mappingsJson) {
        try {
            String integrationActionKey = integration + '_' + actionName;

            List<Object> rawList = String.isBlank(mappingsJson)
                ? new List<Object>()
                : (List<Object>) JSON.deserializeUntyped(mappingsJson);
            List<MappingRow> requestedMappings = new List<MappingRow>();
            Set<String> requestedExternalFields = new Set<String>();
            String requestedDirection = null;

            for (Object objRow : rawList) {
                Map<String, Object> row = (Map<String, Object>) objRow;
                String sfField = (String) row.get('sfField');
                String extField = (String) row.get('externalField');
                String canonicalDirection = toCanonicalCarrierDirection((String) row.get('syncDirection'));
                String syncDirection = toProviderDirection(integration, canonicalDirection);
                if (String.isBlank(sfField) || String.isBlank(extField)) {
                    continue;
                }
                if (requestedExternalFields.contains(extField)) {
                    String carrierLabel = integration == 'fedex' ? 'FedEx' : 'UPS';
                    throw new AuraHandledException('Each ' + carrierLabel + ' field can only be mapped once.');
                }
                if (requestedDirection == null) {
                    requestedDirection = canonicalDirection;
                }
                requestedMappings.add(new MappingRow(sfField, extField, syncDirection));
                requestedExternalFields.add(extField);
            }
            if (requestedDirection == null) {
                requestedDirection = 'SF to Carrier';
            }

            Map<String, QBFieldDefinition> fieldDefs = integration == 'fedex'
                ? getFedExFieldDefinitions(actionName, null)
                : getUPSFieldDefinitions(actionName, null);

            Set<String> mappedFields = new Set<String>();
            for (MappingRow row : requestedMappings) {
                mappedFields.add(row.externalField);
            }
            for (QBFieldDefinition fieldDef : fieldDefs.values()) {
                if (requestedDirection == 'SF to Carrier' && fieldDef.required && !mappedFields.contains(fieldDef.value)) {
                    String carrierLabel = integration == 'fedex' ? 'FedEx' : 'UPS';
                    throw new AuraHandledException('Map every required ' + carrierLabel + ' field before saving.');
                }
            }

            List<Field_Mapping__mdt> existingMappings = queryCarrierMappings(
                integration,
                actionName,
                sfObject,
                false
            );

            List<String> recordsToDeactivate = new List<String>();
            for (Field_Mapping__mdt existingRecord : existingMappings) {
                if (toCanonicalCarrierDirection(existingRecord.Sync_Direction__c) != requestedDirection) {
                    continue;
                }
                if (existingRecord.Is_Active__c && !requestedExternalFields.contains(existingRecord.External_Field__c)) {
                    recordsToDeactivate.add(existingRecord.DeveloperName);
                }
            }

            String nsPrefix = getNamespacePrefix();
            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            for (String developerName : recordsToDeactivate) {
                Metadata.CustomMetadata inactiveMetadata = new Metadata.CustomMetadata();
                inactiveMetadata.fullName = nsPrefix + 'Field_Mapping__mdt.' + developerName;
                inactiveMetadata.label = developerName;
                addCustomMetadataValue(inactiveMetadata, 'Is_Active__c', false);
                mdContainer.addMetadata(inactiveMetadata);
            }

            for (MappingRow row : requestedMappings) {
                Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
                String canonicalDirection = toCanonicalCarrierDirection(row.syncDirection);
                String recordKey = integrationActionKey + (canonicalDirection == 'Carrier to SF' ? '_to_sf' : '_to_carrier');
                customMetadata.fullName = nsPrefix + 'Field_Mapping__mdt.' + buildRecordName(recordKey, sfObject, row.externalField);
                String label = sfObject + ' ' + row.sfField;
                customMetadata.label = label.length() > 40 ? label.substring(0, 40) : label;
                addCustomMetadataValue(customMetadata, 'Integration__c', integration);
                addCustomMetadataValue(customMetadata, 'Action__c', actionName);
                addCustomMetadataValue(customMetadata, 'SF_Object__c', sfObject);
                addCustomMetadataValue(customMetadata, 'SF_Field__c', row.sfField);
                addCustomMetadataValue(customMetadata, 'External_Field__c', row.externalField);
                addCustomMetadataValue(customMetadata, 'Sync_Direction__c', row.syncDirection);
                addCustomMetadataValue(customMetadata, 'Is_Active__c', true);
                mdContainer.addMetadata(customMetadata);
            }

            if (Test.isRunningTest()) {
                return 'Mappings Deployment Started! Job ID: 0Af000000000000';
            }

            if (requestedMappings.isEmpty() && recordsToDeactivate.isEmpty()) {
                return 'Mappings updated successfully.';
            }

            Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, null);
            return 'Mappings Deployment Started! Job ID: ' + jobId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            ErrorLogUtility.logException(
                integration == 'fedex' ? 'FedEx' : 'UPS',
                'FieldMappingController.saveCarrierFieldMappings',
                e,
                null,
                null
            );
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static List<Field_Mapping__mdt> queryCarrierMappings(
        String integration,
        String actionName,
        String sfObject,
        Boolean activeOnly
    ) {
        List<Field_Mapping__mdt> records = new List<Field_Mapping__mdt>();
        if (String.isBlank(integration) || String.isBlank(actionName) || String.isBlank(sfObject)) {
            return records;
        }

        String legacyIntegrationActionKey = integration + '_' + actionName;
        if (activeOnly == true) {
            records.addAll([
                SELECT DeveloperName, Action__c, SF_Field__c, External_Field__c, Sync_Direction__c, Is_Active__c
                FROM Field_Mapping__mdt
                WHERE Integration__c = :integration
                AND Action__c = :actionName
                AND SF_Object__c = :sfObject
                AND Is_Active__c = true
            ]);
            records.addAll([
                SELECT DeveloperName, Action__c, SF_Field__c, External_Field__c, Sync_Direction__c, Is_Active__c
                FROM Field_Mapping__mdt
                WHERE Integration__c = :legacyIntegrationActionKey
                AND SF_Object__c = :sfObject
                AND Is_Active__c = true
            ]);
            return records;
        }

        records.addAll([
            SELECT DeveloperName, Action__c, SF_Field__c, External_Field__c, Sync_Direction__c, Is_Active__c
            FROM Field_Mapping__mdt
            WHERE Integration__c = :integration
            AND Action__c = :actionName
            AND SF_Object__c = :sfObject
        ]);
        records.addAll([
            SELECT DeveloperName, Action__c, SF_Field__c, External_Field__c, Sync_Direction__c, Is_Active__c
            FROM Field_Mapping__mdt
            WHERE Integration__c = :legacyIntegrationActionKey
            AND SF_Object__c = :sfObject
        ]);
        return records;
    }

    private static String toCanonicalCarrierDirection(String directionValue) {
        if (String.isBlank(directionValue)) {
            return 'SF to Carrier';
        }
        String normalized = directionValue.trim().toLowerCase();
        if (normalized == 'carrier to sf' ||
            normalized == 'carrier to salesforce' ||
            normalized == 'fedex to sf' ||
            normalized == 'ups to sf') {
            return 'Carrier to SF';
        }
        return 'SF to Carrier';
    }

    private static String toProviderDirection(String integration, String directionValue) {
        String canonical = toCanonicalCarrierDirection(directionValue);
        if (integration == 'fedex') {
            return canonical == 'Carrier to SF' ? 'FedEx to SF' : 'SF to FedEx';
        }
        if (integration == 'ups') {
            return canonical == 'Carrier to SF' ? 'UPS to SF' : 'SF to UPS';
        }
        return canonical;
    }

    private static Map<String, QBFieldDefinition> getFedExFieldDefinitions(String actionName, String direction) {
        Map<String, QBFieldDefinition> fields = new Map<String, QBFieldDefinition>();
        String act = String.isBlank(actionName) ? '' : actionName;

        if (act == 'validateAddress') {
            addQBFieldDefinition(fields, 'FedEx - streetLines[0]',          'streetLines[0]',               'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - city',                    'city',                         'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - stateOrProvinceCode',     'stateOrProvinceCode',          'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - postalCode',              'postalCode',                   'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - countryCode',             'countryCode',                  'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - streetLines[1]',          'streetLines[1]',               'STRING', false);
            addQBFieldDefinition(fields, 'FedEx - classification',          'classification',               'STRING', false);
        } else if (act == 'getRateQuote') {
            addQBFieldDefinition(fields, 'FedEx - shipper.streetLines[0]',          'shipper.streetLines[0]',           'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.city',                    'shipper.city',                     'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.stateOrProvinceCode',     'shipper.stateOrProvinceCode',      'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.postalCode',              'shipper.postalCode',               'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.countryCode',             'shipper.countryCode',              'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.streetLines[0]',        'recipient.streetLines[0]',         'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.city',                  'recipient.city',                   'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.stateOrProvinceCode',   'recipient.stateOrProvinceCode',    'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.postalCode',            'recipient.postalCode',             'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.countryCode',           'recipient.countryCode',            'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - requestedPackageLineItems[0].weight.value', 'requestedPackageLineItems[0].weight.value', 'NUMBER', false);
        } else if (act == 'createShipment') {
            addQBFieldDefinition(fields, 'FedEx - shipper.contact.personName',      'shipper.contact.personName',       'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.contact.phoneNumber',     'shipper.contact.phoneNumber',      'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.address.streetLines[0]',  'shipper.address.streetLines[0]',   'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.address.city',            'shipper.address.city',             'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.address.stateOrProvinceCode', 'shipper.address.stateOrProvinceCode', 'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.address.postalCode',      'shipper.address.postalCode',       'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.address.countryCode',     'shipper.address.countryCode',      'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.contact.personName',    'recipient.contact.personName',     'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.contact.phoneNumber',   'recipient.contact.phoneNumber',    'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.address.streetLines[0]','recipient.address.streetLines[0]', 'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.address.city',          'recipient.address.city',           'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.address.stateOrProvinceCode','recipient.address.stateOrProvinceCode','STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.address.postalCode',    'recipient.address.postalCode',     'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.address.countryCode',   'recipient.address.countryCode',    'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - requestedPackageLineItems[0].weight.value','requestedPackageLineItems[0].weight.value','NUMBER', true);
            addQBFieldDefinition(fields, 'FedEx - shipper.contact.companyName',     'shipper.contact.companyName',      'STRING', false);
            addQBFieldDefinition(fields, 'FedEx - recipient.contact.companyName',   'recipient.contact.companyName',    'STRING', false);
            addQBFieldDefinition(fields, 'FedEx - requestedPackageLineItems[0].dimensions.length','requestedPackageLineItems[0].dimensions.length','NUMBER', false);
            addQBFieldDefinition(fields, 'FedEx - requestedPackageLineItems[0].dimensions.width','requestedPackageLineItems[0].dimensions.width','NUMBER', false);
            addQBFieldDefinition(fields, 'FedEx - requestedPackageLineItems[0].dimensions.height','requestedPackageLineItems[0].dimensions.height','NUMBER', false);
        } else if (act == 'generateLabel') {
            addQBFieldDefinition(fields, 'FedEx - label.trackingNumber',            'label.trackingNumber',             'STRING', false);
            addQBFieldDefinition(fields, 'FedEx - label.imageType',                 'label.imageType',                  'STRING', false);
            addQBFieldDefinition(fields, 'FedEx - label.contentDocumentId',         'label.contentDocumentId',          'STRING', false);
        } else if (act == 'storeTrackingNumber') {
            addQBFieldDefinition(fields, 'FedEx - shipment.masterTrackingNumber',   'shipment.masterTrackingNumber',    'STRING', false);
            addQBFieldDefinition(fields, 'FedEx - package.trackingNumber',          'package.trackingNumber',           'STRING', false);
        } else if (act == 'syncTrackingStatus') {
            addQBFieldDefinition(fields, 'FedEx - tracking.trackingNumber',         'tracking.trackingNumber',          'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - tracking.latestStatus',           'tracking.latestStatus',            'STRING', false);
            addQBFieldDefinition(fields, 'FedEx - tracking.statusCode',             'tracking.statusCode',              'STRING', false);
            addQBFieldDefinition(fields, 'FedEx - tracking.statusDescription',      'tracking.statusDescription',       'STRING', false);
            addQBFieldDefinition(fields, 'FedEx - tracking.isTerminal',             'tracking.isTerminal',              'BOOLEAN', false);
        } else if (act == 'handleDeliveryExceptions') {
            addQBFieldDefinition(fields, 'FedEx - tracking.statusDescription',      'tracking.statusDescription',       'STRING', false);
            addQBFieldDefinition(fields, 'FedEx - tracking.statusCode',             'tracking.statusCode',              'STRING', false);
        } else if (act == 'createReturnLabel') {
            addQBFieldDefinition(fields, 'FedEx - recipient.contact.personName',    'recipient.contact.personName',     'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.contact.phoneNumber',   'recipient.contact.phoneNumber',    'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.address.streetLines[0]','recipient.address.streetLines[0]', 'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.address.city',          'recipient.address.city',           'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.address.stateOrProvinceCode','recipient.address.stateOrProvinceCode','STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.address.postalCode',    'recipient.address.postalCode',     'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - recipient.address.countryCode',   'recipient.address.countryCode',    'STRING', true);
            addQBFieldDefinition(fields, 'FedEx - requestedPackageLineItems[0].weight.value','requestedPackageLineItems[0].weight.value','NUMBER', true);
        } else if (act == 'voidShipment') {
            addQBFieldDefinition(fields, 'FedEx - masterTrackingNumber',            'masterTrackingNumber',             'STRING', true);
        } else {
            addQBFieldDefinition(fields, 'FedEx - masterTrackingNumber',            'masterTrackingNumber',             'STRING', false);
        }

        return fields;
    }

    private static Map<String, QBFieldDefinition> getUPSFieldDefinitions(String actionName, String direction) {
        Map<String, QBFieldDefinition> fields = new Map<String, QBFieldDefinition>();
        String act = String.isBlank(actionName) ? '' : actionName;

        if (act == 'validateAddress') {
            addQBFieldDefinition(fields, 'UPS - AddressLine',              'AddressLine',              'STRING', true);
            addQBFieldDefinition(fields, 'UPS - City',                     'City',                     'STRING', true);
            addQBFieldDefinition(fields, 'UPS - StateProvinceCode',        'StateProvinceCode',        'STRING', true);
            addQBFieldDefinition(fields, 'UPS - PostalCode',               'PostalCode',               'STRING', true);
            addQBFieldDefinition(fields, 'UPS - CountryCode',              'CountryCode',              'STRING', true);
            addQBFieldDefinition(fields, 'UPS - AddressLine2',             'AddressLine2',             'STRING', false);
        } else if (act == 'getRateQuote') {
            addQBFieldDefinition(fields, 'UPS - Shipper.Address.AddressLine', 'Shipper.Address.AddressLine', 'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.Address.City',        'Shipper.Address.City',        'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.Address.StateProvinceCode', 'Shipper.Address.StateProvinceCode', 'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.Address.PostalCode',  'Shipper.Address.PostalCode',  'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.Address.CountryCode', 'Shipper.Address.CountryCode', 'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.AddressLine',  'ShipTo.Address.AddressLine',  'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.City',         'ShipTo.Address.City',         'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.StateProvinceCode', 'ShipTo.Address.StateProvinceCode', 'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.PostalCode',   'ShipTo.Address.PostalCode',   'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.CountryCode',  'ShipTo.Address.CountryCode',  'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Package.PackageWeight.Weight','Package.PackageWeight.Weight', 'NUMBER', false);
        } else if (act == 'createShipment') {
            addQBFieldDefinition(fields, 'UPS - Shipper.Name',                    'Shipper.Name',                     'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.Phone.Number',            'Shipper.Phone.Number',             'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.Address.AddressLine',     'Shipper.Address.AddressLine',      'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.Address.City',            'Shipper.Address.City',             'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.Address.StateProvinceCode','Shipper.Address.StateProvinceCode','STRING', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.Address.PostalCode',      'Shipper.Address.PostalCode',       'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.Address.CountryCode',     'Shipper.Address.CountryCode',      'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Name',                     'ShipTo.Name',                      'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Phone.Number',             'ShipTo.Phone.Number',              'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.AddressLine',      'ShipTo.Address.AddressLine',       'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.City',             'ShipTo.Address.City',              'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.StateProvinceCode','ShipTo.Address.StateProvinceCode', 'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.PostalCode',       'ShipTo.Address.PostalCode',        'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.CountryCode',      'ShipTo.Address.CountryCode',       'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Package.PackageWeight.Weight',    'Package.PackageWeight.Weight',     'NUMBER', true);
            addQBFieldDefinition(fields, 'UPS - Shipper.AttentionName',           'Shipper.AttentionName',            'STRING', false);
            addQBFieldDefinition(fields, 'UPS - ShipTo.AttentionName',            'ShipTo.AttentionName',             'STRING', false);
            addQBFieldDefinition(fields, 'UPS - Package.Dimensions.Length',       'Package.Dimensions.Length',        'NUMBER', false);
            addQBFieldDefinition(fields, 'UPS - Package.Dimensions.Width',        'Package.Dimensions.Width',         'NUMBER', false);
            addQBFieldDefinition(fields, 'UPS - Package.Dimensions.Height',       'Package.Dimensions.Height',        'NUMBER', false);
            addQBFieldDefinition(fields, 'UPS - Package.Description',             'Package.Description',              'STRING', false);
        } else if (act == 'generateLabel') {
            addQBFieldDefinition(fields, 'UPS - label.trackingNumber',            'label.trackingNumber',             'STRING', false);
            addQBFieldDefinition(fields, 'UPS - label.imageType',                 'label.imageType',                  'STRING', false);
            addQBFieldDefinition(fields, 'UPS - label.contentDocumentId',         'label.contentDocumentId',          'STRING', false);
        } else if (act == 'storeTrackingNumber') {
            addQBFieldDefinition(fields, 'UPS - shipment.masterTrackingNumber',   'shipment.masterTrackingNumber',    'STRING', false);
            addQBFieldDefinition(fields, 'UPS - package.trackingNumber',          'package.trackingNumber',           'STRING', false);
        } else if (act == 'syncTrackingStatus') {
            addQBFieldDefinition(fields, 'UPS - tracking.trackingNumber',         'tracking.trackingNumber',          'STRING', true);
            addQBFieldDefinition(fields, 'UPS - tracking.latestStatus',           'tracking.latestStatus',            'STRING', false);
            addQBFieldDefinition(fields, 'UPS - tracking.statusCode',             'tracking.statusCode',              'STRING', false);
            addQBFieldDefinition(fields, 'UPS - tracking.statusDescription',      'tracking.statusDescription',       'STRING', false);
            addQBFieldDefinition(fields, 'UPS - tracking.isTerminal',             'tracking.isTerminal',              'BOOLEAN', false);
        } else if (act == 'handleDeliveryExceptions') {
            addQBFieldDefinition(fields, 'UPS - tracking.statusDescription',      'tracking.statusDescription',       'STRING', false);
            addQBFieldDefinition(fields, 'UPS - tracking.statusCode',             'tracking.statusCode',              'STRING', false);
        } else if (act == 'createReturnLabel') {
            addQBFieldDefinition(fields, 'UPS - ShipTo.Name',                     'ShipTo.Name',                      'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Phone.Number',             'ShipTo.Phone.Number',              'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.AddressLine',      'ShipTo.Address.AddressLine',       'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.City',             'ShipTo.Address.City',             'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.StateProvinceCode','ShipTo.Address.StateProvinceCode', 'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.PostalCode',       'ShipTo.Address.PostalCode',       'STRING', true);
            addQBFieldDefinition(fields, 'UPS - ShipTo.Address.CountryCode',      'ShipTo.Address.CountryCode',      'STRING', true);
            addQBFieldDefinition(fields, 'UPS - Package.PackageWeight.Weight',    'Package.PackageWeight.Weight',    'NUMBER', true);
            addQBFieldDefinition(fields, 'UPS - Package.Description',             'Package.Description',             'STRING', true);
        } else if (act == 'voidShipment') {
            addQBFieldDefinition(fields, 'UPS - masterTrackingNumber',            'masterTrackingNumber',            'STRING', true);
        } else {
            addQBFieldDefinition(fields, 'UPS - masterTrackingNumber',            'masterTrackingNumber',            'STRING', false);
        }

        return fields;
    }

    private static String buildRecordName(String integration, String sfObject, String extField) {
        String cleanObjName = sfObject.replace('__c', '').replaceAll('__+', '_');
        String sanitizedExternalField = extField.replaceAll('[^a-zA-Z0-9]', '_').replaceAll('__+', '_');
        String baseName = integration + '_' + cleanObjName + '_' + sanitizedExternalField;
        String hashSuffix = '_' + EncodingUtil.convertToHex(
            Crypto.generateDigest('MD5', Blob.valueOf(baseName))
        ).substring(0, 8).toLowerCase();

        Integer maxPrefixLength = 40 - hashSuffix.length();
        String prefix = baseName.length() > maxPrefixLength
            ? baseName.substring(0, maxPrefixLength)
            : baseName;

        prefix = prefix.replaceAll('_+$', '');
        if (prefix.length() + hashSuffix.length() > 40) {
            prefix = prefix.substring(0, 40 - hashSuffix.length()).replaceAll('_+$', '');
        }
        return prefix + hashSuffix;
    }

    private static void addCustomMetadataValue(Metadata.CustomMetadata metadataRecord, String fieldName, Object value) {
        Metadata.CustomMetadataValue customValue = new Metadata.CustomMetadataValue();
        customValue.field = getNamespacePrefix() + fieldName;
        customValue.value = value;
        metadataRecord.values.add(customValue);
    }

    private static String mapSalesforceType(Schema.DisplayType displayType) {
        return normalizeType(String.valueOf(displayType));
    }

    private class FieldWrapper implements Comparable {
        public String label { get; set; }
        public String value { get; set; }
        public String type { get; set; }

        public FieldWrapper(String label, String value, String type) {
            this.label = label;
            this.value = value;
            this.type = type;
        }

        public Integer compareTo(Object obj) {
            FieldWrapper other = (FieldWrapper) obj;
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }

    private class QBFieldDefinition implements Comparable {
        public String label { get; set; }
        public String value { get; set; }
        public String type { get; set; }
        public Boolean required { get; set; }

        public Integer compareTo(Object obj) {
            QBFieldDefinition other = (QBFieldDefinition) obj;
            if (this.required != other.required) {
                return this.required == true ? -1 : 1;
            }
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }

    private class MappingRow {
        public String sfField { get; set; }
        public String externalField { get; set; }
        public String syncDirection { get; set; }

        public MappingRow(String sfField, String externalField, String syncDirection) {
            this.sfField = sfField;
            this.externalField = externalField;
            this.syncDirection = syncDirection;
        }
    }
}