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
  private static final String INTEGRATION_NETSUITE = 'netsuite';
  private static final String INTEGRATION_META = 'meta';
  private static final String DIRECTION_TWO_WAY = 'Two-Way';
  private static final String DIRECTION_SF_TO_QBO = 'SF to QBO';
  private static final String DIRECTION_QBO_TO_SF = 'QBO to SF';
  private static final String DIRECTION_SF_TO_SHOPIFY = 'SF to Shopify';
  private static final String DIRECTION_SHOPIFY_TO_SF = 'Shopify to SF';
  private static final String DIRECTION_SF_TO_NETSUITE = 'SF to NetSuite';
  private static final String DIRECTION_NETSUITE_TO_SF = 'NetSuite to SF';
  private static final String DIRECTION_SF_TO_META = 'SF to Meta';
  private static final String DIRECTION_META_TO_SF = 'Meta to SF';
  private static final Set<String> EXCLUSIVE_INTEGRATIONS = new Set<String>{
    INTEGRATION_QBO,
    INTEGRATION_SHOPIFY
  };
  @TestVisible
  private static List<Field_Mapping__mdt> testActiveMappings;
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
        throw new IllegalArgumentException(
          'Invalid object name: ' + objectName
        );
      }

      Schema.DescribeSObjectResult objectDescribe = sObjectType.getDescribe(
        SObjectDescribeOptions.DEFERRED
      );
      if (!objectDescribe.isAccessible() || !objectDescribe.isQueryable()) {
        throw new IllegalArgumentException(
          'Object is not accessible and queryable: ' + objectName
        );
      }

      Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();

      for (String fieldName : fieldMap.keySet()) {
        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName)
          .getDescribe();
        if (
          fieldDescribe.isAccessible() &&
          fieldDescribe.getType() != Schema.DisplayType.Address &&
          MappingFieldEligibilityService.isSalesforceFieldAllowed(
            fieldDescribe.getName()
          )
        ) {
          fields.add(
            new FieldWrapper(
              fieldDescribe.getLabel(),
              fieldDescribe.getName(),
              mapSalesforceType(fieldDescribe.getType())
            )
          );
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
      logCacheableReadError('FieldMappingController.getObjectFields', e);
      throw new AuraHandledException(
        'Unable to retrieve fields: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getShopifyFields(
    String sfObject,
    String shopifyObject
  ) {
    String shopifyEntity = resolveShopifyEntity(sfObject, shopifyObject);
    return convertQBFieldDefinitions(
      getFallbackShopifyFieldDefinitions(shopifyEntity)
    );
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getNetSuiteFields(
    String sfObject,
    String netSuiteObject
  ) {
    return convertQBFieldDefinitions(
      getFallbackNetSuiteFieldDefinitions(
        resolveNetSuiteEntity(sfObject, netSuiteObject)
      )
    );
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getExternalFields(
    String integration,
    String sfObject,
    String externalObject
  ) {
    String normalizedIntegration = normalizeIntegration(integration);
    if (normalizedIntegration == INTEGRATION_SHOPIFY) {
      return getShopifyFields(sfObject, externalObject);
    }
    if (normalizedIntegration == INTEGRATION_NETSUITE) {
      return getNetSuiteFields(sfObject, externalObject);
    }
    if (normalizedIntegration == INTEGRATION_META) {
      return convertQBFieldDefinitions(
        getFallbackMetaFieldDefinitions(
          resolveMetaEntity(sfObject, externalObject)
        )
      );
    }
    return getQuickBooksFields(sfObject, externalObject);
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getFedExFields(
    String actionName,
    String direction
  ) {
    return convertQBFieldDefinitions(
      getFedExFieldDefinitions(actionName, direction)
    );
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getExistingFedExMappings(
    String actionName,
    String sfObject
  ) {
    return getCarrierMappings('fedex', actionName, sfObject);
  }

  @AuraEnabled
  public static String saveFedExFieldMappings(
    String actionName,
    String sfObject,
    String mappingsJson
  ) {
    return saveCarrierFieldMappings(
      'fedex',
      actionName,
      sfObject,
      mappingsJson
    );
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getUPSFields(
    String actionName,
    String direction
  ) {
    return convertQBFieldDefinitions(
      getUPSFieldDefinitions(actionName, direction)
    );
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getExistingUPSMappings(
    String actionName,
    String sfObject
  ) {
    return getCarrierMappings('ups', actionName, sfObject);
  }

  @AuraEnabled
  public static String saveUPSFieldMappings(
    String actionName,
    String sfObject,
    String mappingsJson
  ) {
    return saveCarrierFieldMappings('ups', actionName, sfObject, mappingsJson);
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getDHLFields(
    String actionName,
    String direction
  ) {
    return convertQBFieldDefinitions(
      getDHLFieldDefinitions(actionName, direction)
    );
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getExistingDHLMappings(
    String actionName,
    String sfObject
  ) {
    return getCarrierMappings('dhl', actionName, sfObject);
  }

  @AuraEnabled
  public static String saveDHLFieldMappings(
    String actionName,
    String sfObject,
    String mappingsJson
  ) {
    return saveCarrierFieldMappings('dhl', actionName, sfObject, mappingsJson);
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getQuickBooksFields(
    String sfObject,
    String qbObject
  ) {
    String qbEntity = resolveQBEntity(sfObject, qbObject);

    try {
      Map<String, QBFieldDefinition> fieldDefinitions = fetchQBFieldDefinitions(
        qbEntity
      );
      return convertQBFieldDefinitions(fieldDefinitions);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'QB schema lookup failed for ' + qbEntity + ': ' + e.getMessage()
      );
      logCacheableReadError('FieldMappingController.getQuickBooksFields', e);
      return convertQBFieldDefinitions(getFallbackQBFieldDefinitions(qbEntity));
    }
  }

  @AuraEnabled
  public static Map<String, Object> getMappingDirectionAvailability(
    String integration,
    String sfObject
  ) {
    return buildMappingDirectionAvailability(integration, sfObject);
  }

  @AuraEnabled
  public static String clearFieldMappings(String integration, String sfObject) {
    try {
      List<Field_Mapping__mdt> existingMappings = [
        SELECT DeveloperName, Is_Active__c
        FROM Field_Mapping__mdt
        WHERE
          Integration__c = :integration
          AND SF_Object__c = :sfObject
          AND Is_Active__c = TRUE
      ];
      if (existingMappings.isEmpty()) {
        return 'No active mappings to clear.';
      }
      String nsPrefix = getNamespacePrefix();
      Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
      for (Field_Mapping__mdt rec : existingMappings) {
        Metadata.CustomMetadata inactive = new Metadata.CustomMetadata();
        inactive.fullName =
          nsPrefix +
          'Field_Mapping__mdt.' +
          rec.DeveloperName;
        inactive.label = rec.DeveloperName;
        addCustomMetadataValue(inactive, 'Is_Active__c', false);
        mdContainer.addMetadata(inactive);
      }
      if (Test.isRunningTest()) {
        return 'Mappings Cleared. Job ID: 0Af000000000000';
      }
      Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, null);
      return 'Mappings Cleared. Job ID: ' + jobId;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      ErrorLogUtility.logException(
        'QuickBooks',
        'FieldMappingController.clearFieldMappings',
        e,
        null,
        null
      );
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static String clearFieldMappingsForTargetObject(
    String integration,
    String sfObject,
    String externalObject
  ) {
    try {
      if (String.isBlank(externalObject)) {
        throw new AuraHandledException('External object is required.');
      }
      List<Field_Mapping__mdt> existingMappings = [
        SELECT DeveloperName, Is_Active__c
        FROM Field_Mapping__mdt
        WHERE
          Integration__c = :integration
          AND SF_Object__c = :sfObject
          AND Target_Object_API_Name__c = :externalObject
          AND Is_Active__c = TRUE
      ];
      if (existingMappings.isEmpty()) {
        return 'No active mappings to clear.';
      }
      String nsPrefix = getNamespacePrefix();
      Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
      for (Field_Mapping__mdt rec : existingMappings) {
        Metadata.CustomMetadata inactive = new Metadata.CustomMetadata();
        inactive.fullName =
          nsPrefix +
          'Field_Mapping__mdt.' +
          rec.DeveloperName;
        inactive.label = rec.DeveloperName;
        addCustomMetadataValue(inactive, 'Is_Active__c', false);
        mdContainer.addMetadata(inactive);
      }
      if (Test.isRunningTest()) {
        return 'Mappings Cleared. Job ID: 0Af000000000000';
      }
      Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, null);
      return 'Mappings Cleared. Job ID: ' + jobId;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      ErrorLogUtility.logException(
        getIntegrationLabel(integration),
        'FieldMappingController.clearFieldMappingsForTargetObject',
        e,
        null,
        null
      );
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static Integer deactivateBlockedFieldMappings() {
    List<Field_Mapping__mdt> active = [
      SELECT DeveloperName, SF_Field__c
      FROM Field_Mapping__mdt
      WHERE Is_Active__c = TRUE
    ];
    String nsPrefix = getNamespacePrefix();
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    Integer count = 0;
    for (Field_Mapping__mdt rec : active) {
      if (
        !MappingFieldEligibilityService.isSalesforceFieldAllowed(
          rec.SF_Field__c
        )
      ) {
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = nsPrefix + 'Field_Mapping__mdt.' + rec.DeveloperName;
        md.label = rec.DeveloperName;
        addCustomMetadataValue(md, 'Is_Active__c', false);
        container.addMetadata(md);
        count++;
      }
    }
    if (count > 0 && !Test.isRunningTest()) {
      Metadata.Operations.enqueueDeployment(container, null);
    }
    return count;
  }

  @AuraEnabled
  public static String saveFieldMappings(
    String integration,
    String sfObject,
    String qbObject,
    String mappingsJson
  ) {
    try {
      if (
        integration == INTEGRATION_QBO &&
        resolveQBEntity(sfObject, qbObject) == 'Invoice'
      ) {
        List<Field_Mapping__mdt> invoiceMappings = getActiveQboMappingsForConflict();
        String conflictingObject;
        for (Field_Mapping__mdt existingMapping : invoiceMappings) {
          if (
            existingMapping.SF_Object__c != sfObject &&
            resolveQBEntity(
              existingMapping.SF_Object__c,
              existingMapping.Target_Object_API_Name__c
            ) == 'Invoice'
          ) {
            conflictingObject = existingMapping.SF_Object__c;
            break;
          }
        }
        if (String.isNotBlank(conflictingObject)) {
          throw new AuraHandledException(
            'Conflict Error: You cannot map both ' +
              sfObject +
              ' and ' +
              conflictingObject +
              ' to QuickBooks Invoice. Please clear ' +
              conflictingObject +
              ' mappings first.'
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
        String syncDirection = normalizeMappingDirection(
          integration,
          (String) row.get('syncDirection')
        );

        if (String.isBlank(sfField) || String.isBlank(extField)) {
          continue;
        }
        if (requestedExternalFields.contains(extField)) {
          String integrationLabel = getIntegrationLabel(integration);
          throw new AuraHandledException(
            'Each ' + integrationLabel + ' field can only be mapped once.'
          );
        }
        requestedMappings.add(new MappingRow(sfField, extField, syncDirection));
        requestedExternalFields.add(extField);
      }

      List<String> sfFieldNames = new List<String>();
      for (MappingRow row : requestedMappings) {
        sfFieldNames.add(row.sfField);
      }
      MappingFieldEligibilityService.assertNoBlockedSalesforceFields(
        sfFieldNames
      );
      assertNoCompoundAddressFields(sfObject, sfFieldNames);
      validateExternalFieldCapabilities(
        integration,
        sfObject,
        qbObject,
        requestedMappings
      );
      validateNoOverlappingSalesforceTargets(
        integration,
        sfObject,
        qbObject,
        requestedMappings
      );

      validateObjectDirectionAvailability(
        integration,
        sfObject,
        requestedMappings
      );
      validateRequiredMappings(
        integration,
        sfObject,
        qbObject,
        requestedMappings
      );
      validateDataTypes(integration, sfObject, qbObject, requestedMappings);

      // Only consider rows for the same external/QBO object (Customer vs Vendor ...)
      // when deciding what to deactivate, so saving Vendor mappings never disturbs
      // Customer mappings. Legacy rows (blank Target_Object_API_Name__c) are still
      // included so they get cleaned up / re-stamped on save.
      Boolean scopeByObject = String.isNotBlank(qbObject);
      List<Field_Mapping__mdt> existingMappings = [
        SELECT
          DeveloperName,
          External_Field__c,
          Is_Active__c,
          Target_Object_API_Name__c
        FROM Field_Mapping__mdt
        WHERE Integration__c = :integration AND SF_Object__c = :sfObject
      ];

      List<String> recordsToDeactivate = new List<String>();
      for (Field_Mapping__mdt existingRecord : existingMappings) {
        // Skip rows that belong to a different QBO object so they are preserved.
        if (
          scopeByObject &&
          String.isNotBlank(existingRecord.Target_Object_API_Name__c) &&
          existingRecord.Target_Object_API_Name__c != qbObject
        ) {
          continue;
        }
        if (
          existingRecord.Is_Active__c &&
          !requestedExternalFields.contains(existingRecord.External_Field__c)
        ) {
          recordsToDeactivate.add(existingRecord.DeveloperName);
        }
      }

      String nsPrefix = getNamespacePrefix();
      Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
      if (!requestedMappings.isEmpty()) {
        IntegrationObjectMapRegistrationService.addMissingPair(
          mdContainer,
          integration,
          sfObject,
          qbObject
        );
      }
      for (String developerName : recordsToDeactivate) {
        Metadata.CustomMetadata inactiveMetadata = new Metadata.CustomMetadata();
        inactiveMetadata.fullName =
          nsPrefix +
          'Field_Mapping__mdt.' +
          developerName;
        inactiveMetadata.label = developerName;
        addCustomMetadataValue(inactiveMetadata, 'Is_Active__c', false);
        mdContainer.addMetadata(inactiveMetadata);
      }

      for (MappingRow row : requestedMappings) {
        Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
        customMetadata.fullName =
          nsPrefix +
          'Field_Mapping__mdt.' +
          buildRecordName(integration, sfObject, qbObject, row.externalField);
        String label = sfObject + ' ' + row.sfField;
        customMetadata.label = label.length() > 40
          ? label.substring(0, 40)
          : label;

        addCustomMetadataValue(customMetadata, 'Integration__c', integration);
        addCustomMetadataValue(customMetadata, 'SF_Object__c', sfObject);
        addCustomMetadataValue(customMetadata, 'SF_Field__c', row.sfField);
        addCustomMetadataValue(
          customMetadata,
          'External_Field__c',
          row.externalField
        );
        addCustomMetadataValue(
          customMetadata,
          'Sync_Direction__c',
          row.syncDirection
        );
        // Persist which QBO object (Customer / Vendor / Item ...) this mapping
        // belongs to so each object keeps an independent mapping set.
        if (String.isNotBlank(qbObject)) {
          addCustomMetadataValue(
            customMetadata,
            'Target_Object_API_Name__c',
            qbObject
          );
        }
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
        getIntegrationLabel(integration),
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
    for (
      Map<String, Object> option : SalesforceObjectDiscoveryService.discover(
        null
      )
    ) {
      if (option.get('available') != true) {
        continue;
      }
      objects.add(
        new Map<String, String>{
          'label' => (String) option.get('label'),
          'value' => (String) option.get('value')
        }
      );
    }
    return objects;
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getSalesforceObjectDiscovery(
    String connectorKey
  ) {
    return SalesforceObjectDiscoveryService.discover(connectorKey);
  }

  private static String getNamespacePrefix() {
    String className = FieldMappingController.class.getName();
    if (className.contains('.')) {
      return className.substringBefore('.') + '__';
    }
    return '';
  }

  private static List<Field_Mapping__mdt> getActiveQboMappingsForConflict() {
    if (Test.isRunningTest() && testActiveMappings != null) {
      List<Field_Mapping__mdt> testMappings = new List<Field_Mapping__mdt>();
      for (Field_Mapping__mdt mapping : testActiveMappings) {
        if (
          mapping != null &&
          mapping.Integration__c == INTEGRATION_QBO &&
          mapping.Is_Active__c == true
        ) {
          testMappings.add(mapping);
        }
      }
      return testMappings;
    }
    return [
      SELECT SF_Object__c, Target_Object_API_Name__c
      FROM Field_Mapping__mdt
      WHERE Integration__c = 'qbonline' AND Is_Active__c = TRUE
    ];
  }

  /**
   * Helper to resolve SObjectType while accounting for package namespaces
   */
  private static Schema.SObjectType getSObjectType(String objApiName) {
    if (String.isBlank(objApiName))
      return null;

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

  private static void logCacheableReadError(String methodName, Exception e) {
    System.debug(
      LoggingLevel.WARN,
      methodName + ' read failed: ' + e.getMessage()
    );
  }

  // Backward-compatible overload (no QBO-object scoping) for Apex callers that
  // don't distinguish a target object. Intentionally NOT @AuraEnabled so the LWC
  // wire bridge resolves the 3-arg version unambiguously.
  public static List<Map<String, String>> getExistingMappings(
    String integration,
    String sfObject
  ) {
    return getExistingMappings(integration, sfObject, null);
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getExistingMappings(
    String integration,
    String sfObject,
    String qbObject
  ) {
    List<Map<String, String>> savedMappings = new List<Map<String, String>>();
    try {
      // When a QBO object is supplied, scope to rows for that object (Customer vs
      // Vendor ...). Legacy rows with a blank Target_Object_API_Name__c still apply
      // so existing mappings remain visible until re-saved (which stamps them).
      Boolean scopeByObject = String.isNotBlank(qbObject);
      List<Field_Mapping__mdt> records = [
        SELECT
          DeveloperName,
          SF_Field__c,
          External_Field__c,
          Sync_Direction__c,
          Target_Object_API_Name__c
        FROM Field_Mapping__mdt
        WHERE
          Integration__c = :integration
          AND SF_Object__c = :sfObject
          AND Is_Active__c = TRUE
      ];

      for (Field_Mapping__mdt record : records) {
        if (
          String.isBlank(record.SF_Field__c) ||
          String.isBlank(record.External_Field__c)
        ) {
          continue;
        }
        // Skip rows that belong to a different QBO object.
        if (
          scopeByObject &&
          String.isNotBlank(record.Target_Object_API_Name__c) &&
          record.Target_Object_API_Name__c != qbObject
        ) {
          continue;
        }
        Map<String, String> mapping = new Map<String, String>();
        mapping.put('developerName', record.DeveloperName);
        mapping.put('sfField', record.SF_Field__c);
        mapping.put('externalField', record.External_Field__c);
        mapping.put(
          'syncDirection',
          String.isNotBlank(record.Sync_Direction__c)
            ? record.Sync_Direction__c
            : 'Two-Way'
        );
        savedMappings.add(mapping);
      }
    } catch (Exception e) {
      System.debug('Error loading metadata: ' + e.getMessage());
      logCacheableReadError('FieldMappingController.getExistingMappings', e);
    }
    return savedMappings;
  }

  private static void validateRequiredMappings(
    String sfObject,
    String qbObject,
    List<MappingRow> requestedMappings
  ) {
    String qbEntity = resolveQBEntity(sfObject, qbObject);
    Map<String, QBFieldDefinition> qbFields = fetchQBFieldDefinitionsSafe(
      qbEntity
    );
    Set<String> mappedExternalFields = new Set<String>();
    for (MappingRow row : requestedMappings) {
      mappedExternalFields.add(row.externalField);
    }

    for (QBFieldDefinition fieldDef : qbFields.values()) {
      if (fieldDef.required && !mappedExternalFields.contains(fieldDef.value)) {
        throw new AuraHandledException(
          'Map every required QuickBooks field before saving.'
        );
      }
    }
  }

  private static void validateExternalFieldCapabilities(
    String integration,
    String sfObject,
    String externalObject,
    List<MappingRow> requestedMappings
  ) {
    if (
      integration != INTEGRATION_QBO ||
      sfObject != 'Account' ||
      (externalObject != 'Customer' && externalObject != 'Vendor')
    ) {
      return;
    }
    for (MappingRow row : requestedMappings) {
      Boolean includesInbound = row.syncDirection == DIRECTION_QBO_TO_SF ||
        row.syncDirection == DIRECTION_TWO_WAY;
      Boolean includesOutbound = row.syncDirection == DIRECTION_SF_TO_QBO ||
        row.syncDirection == DIRECTION_TWO_WAY;
      if (
        includesOutbound &&
        !isQboAccountFieldOutboundWritable(externalObject, row.externalField)
      ) {
        throw new AuraHandledException(
          'QuickBooks ' + externalObject + ' field "' + row.externalField +
          '" is read-only and can only use QBO to SF.'
        );
      }
      if (includesInbound && !isWritableInboundSalesforceField(sfObject, row.sfField)) {
        throw new AuraHandledException(
          'Salesforce field "' + row.sfField +
          '" is read-only and cannot receive QuickBooks values.'
        );
      }
    }
  }

  private static Boolean isQboAccountFieldOutboundWritable(
    String externalObject,
    String externalField
  ) {
    return externalObject == 'Vendor'
      ? QBVendorFieldCapabilities.isOutboundWritable(externalField)
      : QBCustomerFieldCapabilities.isOutboundWritable(externalField);
  }

  private static Boolean isWritableInboundSalesforceField(
    String sfObject,
    String sfField
  ) {
    Schema.SObjectType objectType = getSObjectType(sfObject);
    if (objectType == null || String.isBlank(sfField) || sfField.contains('.')) {
      return false;
    }
    Map<String, Schema.SObjectField> fieldMap = objectType
      .getDescribe(SObjectDescribeOptions.DEFERRED)
      .fields.getMap();
    Schema.SObjectField fieldToken = fieldMap.get(sfField.toLowerCase());
    if (fieldToken == null) {
      String normalizedField = sfField.toLowerCase();
      for (String candidate : fieldMap.keySet()) {
        if (
          candidate.equalsIgnoreCase(sfField) ||
          candidate.toLowerCase().endsWith('__' + normalizedField)
        ) {
          fieldToken = fieldMap.get(candidate);
          break;
        }
      }
    }
    if (fieldToken == null) {
      return false;
    }
    Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
    return !fieldDescribe.isCalculated() &&
      !fieldDescribe.isAutoNumber() &&
      (fieldDescribe.isCreateable() || fieldDescribe.isUpdateable());
  }

  private static void validateNoOverlappingSalesforceTargets(
    String integration,
    String sfObject,
    String externalObject,
    List<MappingRow> requestedMappings
  ) {
    if (
      integration != INTEGRATION_QBO ||
      sfObject != 'Account' ||
      (externalObject != 'Customer' && externalObject != 'Vendor')
    ) {
      return;
    }
    Set<String> inboundTargets = new Set<String>();
    Set<String> outboundSources = new Set<String>();
    for (MappingRow row : requestedMappings) {
      Boolean includesInbound = row.syncDirection == DIRECTION_QBO_TO_SF ||
        row.syncDirection == DIRECTION_TWO_WAY;
      Boolean includesOutbound = row.syncDirection == DIRECTION_SF_TO_QBO ||
        row.syncDirection == DIRECTION_TWO_WAY;
      if (includesInbound && !inboundTargets.add(row.sfField)) {
        throw new AuraHandledException(
          'A Salesforce field can only receive one QuickBooks ' + externalObject + ' field in overlapping inbound directions: ' +
          row.sfField + '.'
        );
      }
      if (includesOutbound && !outboundSources.add(row.sfField)) {
        throw new AuraHandledException(
          'A Salesforce field can only populate one QuickBooks ' + externalObject + ' field in overlapping outbound directions: ' +
          row.sfField + '.'
        );
      }
    }
  }

  private static void assertNoCompoundAddressFields(
    String sfObject,
    List<String> sfFieldNames
  ) {
    if (String.isBlank(sfObject) || sfFieldNames == null) {
      return;
    }

    Schema.SObjectType objectType = getSObjectType(sfObject);
    if (objectType == null) {
      return;
    }

    Map<String, Schema.SObjectField> fields = objectType
      .getDescribe(SObjectDescribeOptions.DEFERRED)
      .fields.getMap();
    for (String sfFieldName : sfFieldNames) {
      if (String.isBlank(sfFieldName)) {
        continue;
      }

      Schema.SObjectField fieldToken = fields.get(sfFieldName.toLowerCase());
      if (
        fieldToken != null &&
        fieldToken.getDescribe().getType() == Schema.DisplayType.Address
      ) {
        String message =
          'Field "' +
          fieldToken.getDescribe().getName() +
          '" is a compound address and cannot be used in a mapping. Map its Street, City, State, Postal Code, and Country fields separately.';
        AuraHandledException exceptionValue = new AuraHandledException(message);
        exceptionValue.setMessage(message);
        throw exceptionValue;
      }
    }
  }

  private static void validateRequiredMappings(
    String integration,
    String sfObject,
    String extObject,
    List<MappingRow> requestedMappings
  ) {
    Map<String, QBFieldDefinition> fieldDefs;
    String integrationLabel;
    if (integration == INTEGRATION_SHOPIFY) {
      String shopifyEntity = resolveShopifyEntity(sfObject, extObject);
      fieldDefs = getFallbackShopifyFieldDefinitions(shopifyEntity);
      integrationLabel = 'Shopify';
    } else if (integration == INTEGRATION_NETSUITE) {
      fieldDefs = getFallbackNetSuiteFieldDefinitions(
        resolveNetSuiteEntity(sfObject, extObject)
      );
      integrationLabel = 'NetSuite';
    } else if (integration == INTEGRATION_META) {
      fieldDefs = getFallbackMetaFieldDefinitions(
        resolveMetaEntity(sfObject, extObject)
      );
      integrationLabel = 'Meta';
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
        throw new AuraHandledException(
          'Map every required ' + integrationLabel + ' field before saving.'
        );
      }
    }
  }

  private static void validateDataTypes(
    String sfObject,
    String qbObject,
    List<MappingRow> requestedMappings
  ) {
    validateDataTypes(null, sfObject, qbObject, requestedMappings);
  }

  private static void validateDataTypes(
    String integration,
    String sfObject,
    String extObject,
    List<MappingRow> requestedMappings
  ) {
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
    } else if (integration == INTEGRATION_NETSUITE) {
      extFields = getFallbackNetSuiteFieldDefinitions(
        resolveNetSuiteEntity(sfObject, extObject)
      );
      integrationLabel = 'NetSuite';
    } else if (integration == INTEGRATION_META) {
      extFields = getFallbackMetaFieldDefinitions(
        resolveMetaEntity(sfObject, extObject)
      );
      integrationLabel = 'Meta';
    } else {
      extFields = fetchQBFieldDefinitionsSafe(
        resolveQBEntity(sfObject, extObject)
      );
      integrationLabel = 'QuickBooks';
    }

    for (MappingRow row : requestedMappings) {
      if (
        !sfFieldTypes.containsKey(row.sfField) ||
        !extFields.containsKey(row.externalField)
      ) {
        continue;
      }

      String sfType = sfFieldTypes.get(row.sfField);
      String extType = extFields.get(row.externalField).type;
      if (!isTypeMatch(sfType, extType)) {
        throw new AuraHandledException(
          'Field type mismatch for ' +
            integrationLabel +
            ' field ' +
            row.externalField +
            '.'
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
    if (
      upperValue == 'CURRENCY' ||
      upperValue == 'DOUBLE' ||
      upperValue == 'INTEGER' ||
      upperValue == 'PERCENT' ||
      upperValue == 'DECIMAL' ||
      upperValue == 'LONG' ||
      upperValue == 'NUMBER'
    ) {
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

  private static Map<String, Object> buildMappingDirectionAvailability(
    String integration,
    String sfObject
  ) {
    Map<String, Object> result = new Map<String, Object>();
    String normalizedIntegration = normalizeIntegration(integration);
    String otherIntegration = getPeerIntegration(normalizedIntegration);
    String otherLabel = getIntegrationLabel(otherIntegration);

    Boolean inboundAllowed = true;
    Boolean outboundAllowed = true;
    String inboundConflictDirection;
    String outboundConflictDirection;

    if (otherIntegration != null && String.isNotBlank(sfObject)) {
      for (
        Field_Mapping__mdt mapping : getActiveMappingsForAvailability(
          otherIntegration,
          sfObject
        )
      ) {
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
            outboundConflictDirection = String.isBlank(
                mapping.Sync_Direction__c
              )
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
      if (
        inboundConflictDirection == DIRECTION_TWO_WAY ||
        outboundConflictDirection == DIRECTION_TWO_WAY
      ) {
        return 'Cannot create Two-Way mapping. ' +
          otherLabel +
          ' already has Two-Way mapping for ' +
          objectLabel +
          '.';
      }
      return 'Cannot create Two-Way mapping. ' +
        otherLabel +
        ' already has inbound and outbound mappings for ' +
        objectLabel +
        '.';
    }
    if (!inboundAllowed) {
      return 'Cannot create inbound mapping. ' +
        otherLabel +
        ' already has ' +
        inboundConflictDirection +
        ' mapping for ' +
        objectLabel +
        '.';
    }
    return 'Cannot create outbound mapping. ' +
      otherLabel +
      ' already has ' +
      outboundConflictDirection +
      ' mapping for ' +
      objectLabel +
      '.';
  }

  private static void validateObjectDirectionAvailability(
    String integration,
    String sfObject,
    List<MappingRow> requestedMappings
  ) {
    if (!isQboOrShopify(integration) || requestedMappings.isEmpty()) {
      return;
    }

    Map<String, Object> availability = buildMappingDirectionAvailability(
      integration,
      sfObject
    );
    Boolean inboundAllowed = (Boolean) availability.get('inboundAllowed');
    Boolean outboundAllowed = (Boolean) availability.get('outboundAllowed');
    String message = (String) availability.get('message');

    for (MappingRow row : requestedMappings) {
      if (!inboundAllowed && directionTouchesInbound(row.syncDirection)) {
        throw new AuraHandledException(
          'Mapping Direction Conflict: ' + message
        );
      }
      if (!outboundAllowed && directionTouchesOutbound(row.syncDirection)) {
        throw new AuraHandledException(
          'Mapping Direction Conflict: ' + message
        );
      }
    }
  }

  private static List<Field_Mapping__mdt> getActiveMappingsForAvailability(
    String integration,
    String sfObject
  ) {
    List<Field_Mapping__mdt> records = new List<Field_Mapping__mdt>();
    if (String.isBlank(integration) || String.isBlank(sfObject)) {
      return records;
    }

    if (Test.isRunningTest() && testActiveMappings != null) {
      for (Field_Mapping__mdt mapping : testActiveMappings) {
        if (
          mapping != null &&
          mapping.Integration__c == integration &&
          mapping.SF_Object__c == sfObject &&
          mapping.Is_Active__c == true
        ) {
          records.add(mapping);
        }
      }
      return records;
    }

    return [
      SELECT Integration__c, SF_Object__c, Sync_Direction__c, Is_Active__c
      FROM Field_Mapping__mdt
      WHERE
        Integration__c = :integration
        AND SF_Object__c = :sfObject
        AND Is_Active__c = TRUE
    ];
  }

  private static Boolean directionTouchesInbound(String syncDirection) {
    String direction = String.isBlank(syncDirection)
      ? DIRECTION_TWO_WAY
      : syncDirection;
    return direction == DIRECTION_TWO_WAY ||
      direction == DIRECTION_QBO_TO_SF ||
      direction == DIRECTION_SHOPIFY_TO_SF ||
      direction == DIRECTION_NETSUITE_TO_SF ||
      direction == DIRECTION_META_TO_SF;
  }

  private static Boolean directionTouchesOutbound(String syncDirection) {
    String direction = String.isBlank(syncDirection)
      ? DIRECTION_TWO_WAY
      : syncDirection;
    return direction == DIRECTION_TWO_WAY ||
      direction == DIRECTION_SF_TO_QBO ||
      direction == DIRECTION_SF_TO_SHOPIFY ||
      direction == DIRECTION_SF_TO_NETSUITE ||
      direction == DIRECTION_SF_TO_META;
  }

  private static String normalizeMappingDirection(
    String integration,
    String syncDirection
  ) {
    String normalizedIntegration = normalizeIntegration(integration);
    if (
      !isQboOrShopify(integration) &&
      normalizedIntegration != INTEGRATION_NETSUITE &&
      normalizedIntegration != INTEGRATION_META
    ) {
      return syncDirection;
    }

    String direction = String.isBlank(syncDirection)
      ? DIRECTION_TWO_WAY
      : syncDirection.trim();
    Set<String> validDirections;
    if (normalizedIntegration == INTEGRATION_SHOPIFY) {
      validDirections = new Set<String>{
        DIRECTION_SF_TO_SHOPIFY,
        DIRECTION_SHOPIFY_TO_SF,
        DIRECTION_TWO_WAY
      };
    } else if (normalizedIntegration == INTEGRATION_NETSUITE) {
      validDirections = new Set<String>{
        DIRECTION_SF_TO_NETSUITE,
        DIRECTION_NETSUITE_TO_SF,
        DIRECTION_TWO_WAY
      };
    } else if (normalizedIntegration == INTEGRATION_META) {
      validDirections = new Set<String>{
        DIRECTION_SF_TO_META,
        DIRECTION_META_TO_SF,
        DIRECTION_TWO_WAY
      };
    } else {
      validDirections = new Set<String>{
        DIRECTION_SF_TO_QBO,
        DIRECTION_QBO_TO_SF,
        DIRECTION_TWO_WAY
      };
    }

    if (!validDirections.contains(direction)) {
      throw new AuraHandledException(
        'Invalid sync direction for ' +
          getIntegrationLabel(integration) +
          ' mappings.'
      );
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
    if (normalized == INTEGRATION_NETSUITE) {
      return 'NetSuite';
    }
    if (normalized == INTEGRATION_META) {
      return 'Meta';
    }
    return 'the other integration';
  }

  private static Map<String, QBFieldDefinition> fetchQBFieldDefinitionsSafe(
    String qbEntity
  ) {
    try {
      return fetchQBFieldDefinitions(qbEntity);
    } catch (Exception e) {
      return getFallbackQBFieldDefinitions(qbEntity);
    }
  }

  private static Map<String, QBFieldDefinition> fetchQBFieldDefinitions(
    String qbEntity
  ) {
    Map<String, QBFieldDefinition> fieldDefinitions = getFallbackQBFieldDefinitions(
      qbEntity
    );
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
      if (
        String.isBlank(definition.type) ||
        definition.type == 'STRING' ||
        apiType != 'STRING'
      ) {
        definition.type = apiType;
      }
      if (definition.required == null) {
        definition.required = false;
      }
      fieldDefinitions.put(fieldPath, definition);
    }

    applyQBFieldCapabilities(qbEntity, fieldDefinitions);
    return fieldDefinitions;
  }

  private static Map<String, QBFieldDefinition> getFallbackQBFieldDefinitions(
    String qbEntity
  ) {
    Map<String, QBFieldDefinition> qbFields = new Map<String, QBFieldDefinition>();

    if (qbEntity == 'Customer') {
      addQBFieldDefinition(
        qbFields,
        'QB - DisplayName',
        'DisplayName',
        'STRING',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - CompanyName',
        'CompanyName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - FamilyName',
        'FamilyName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - GivenName',
        'GivenName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - AcctNum',
        'AcctNum',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Email',
        'PrimaryEmailAddr.Address',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Phone',
        'PrimaryPhone.FreeFormNumber',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Billing Street',
        'BillAddr.Line1',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Billing City',
        'BillAddr.City',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Billing State/Province',
        'BillAddr.CountrySubDivisionCode',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Billing Postal Code',
        'BillAddr.PostalCode',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Billing Country',
        'BillAddr.Country',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Shipping Street',
        'ShipAddr.Line1',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Shipping City',
        'ShipAddr.City',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Shipping State/Province',
        'ShipAddr.CountrySubDivisionCode',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Shipping Postal Code',
        'ShipAddr.PostalCode',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Shipping Country',
        'ShipAddr.Country',
        'STRING',
        false
      );
      addQBFieldDefinition(qbFields, 'QB - Notes', 'Notes', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Balance', 'Balance', 'NUMBER', false);
      addQBFieldDefinition(
        qbFields,
        'QB - Balance With Jobs',
        'BalanceWithJobs',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Fully Qualified Name',
        'FullyQualifiedName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Print On Check Name',
        'PrintOnCheckName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Currency Name',
        'CurrencyRef.name',
        'STRING',
        false
      );
    } else if (qbEntity == 'Vendor') {
      addQBFieldDefinition(
        qbFields,
        'QB - DisplayName',
        'DisplayName',
        'STRING',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - CompanyName',
        'CompanyName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - FamilyName',
        'FamilyName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - GivenName',
        'GivenName',
        'STRING',
        false
      );
      addQBFieldDefinition(qbFields, 'QB - MiddleName', 'MiddleName', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Suffix', 'Suffix', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Account Number', 'AcctNum', 'STRING', false);
      addQBFieldDefinition(
        qbFields,
        'QB - Primary Email',
        'PrimaryEmailAddr.Address',
        'STRING',
        false
      );
      addQBFieldDefinition(qbFields, 'QB - Billing Street', 'BillAddr.Line1', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Billing City', 'BillAddr.City', 'STRING', false);
      addQBFieldDefinition(
        qbFields,
        'QB - Billing State/Province',
        'BillAddr.CountrySubDivisionCode',
        'STRING',
        false
      );
      addQBFieldDefinition(qbFields, 'QB - Billing Postal Code', 'BillAddr.PostalCode', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Billing Country', 'BillAddr.Country', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Notes', 'Notes', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Balance', 'Balance', 'NUMBER', false);
      addQBFieldDefinition(qbFields, 'QB - Print On Check Name', 'PrintOnCheckName', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Currency Name', 'CurrencyRef.name', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Currency Id', 'CurrencyRef.value', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Terms Id', 'TermRef.value', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - Tax Identifier', 'TaxIdentifier', 'STRING', false);
      addQBFieldDefinition(qbFields, 'QB - 1099 Vendor', 'Vendor1099', 'BOOLEAN', false);
      addQBFieldDefinition(
        qbFields,
        'QB - Primary Phone',
        'PrimaryPhone.FreeFormNumber',
        'STRING',
        false
      );
    } else if (qbEntity == 'Item') {
      addQBFieldDefinition(qbFields, 'QB - Name', 'Name', 'STRING', true);
      addQBFieldDefinition(
        qbFields,
        'QB - Description',
        'Description',
        'STRING',
        false
      );
      addQBFieldDefinition(qbFields, 'QB - Sku', 'Sku', 'STRING', false);
      addQBFieldDefinition(
        qbFields,
        'QB - UnitPrice',
        'UnitPrice',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - PurchaseCost',
        'PurchaseCost',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Type',
        'Type',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Active',
        'Active',
        'BOOLEAN',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - TrackQtyOnHand',
        'TrackQtyOnHand',
        'BOOLEAN',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - QtyOnHand',
        'QtyOnHand',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - InvStartDate',
        'InvStartDate',
        'DATE',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - IncomeAccountRef.value',
        'IncomeAccountRef.value',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - ExpenseAccountRef.value',
        'ExpenseAccountRef.value',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - AssetAccountRef.value',
        'AssetAccountRef.value',
        'STRING',
        false
      );
    } else if (qbEntity == 'Invoice') {
      addQBFieldDefinition(
        qbFields,
        'QB - CustomerRef.value',
        'CustomerRef.value',
        'STRING',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - DocNumber',
        'DocNumber',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - TotalAmt',
        'TotalAmt',
        'NUMBER',
        false
      );
      addQBFieldDefinition(qbFields, 'QB - TxnDate', 'TxnDate', 'DATE', false);
      addQBFieldDefinition(
        qbFields,
        'QB - Customer Memo',
        'CustomerMemo.value',
        'STRING',
        false
      );
    } else if (qbEntity == 'CreditMemo') {
      addQBFieldDefinition(
        qbFields,
        'QB - CustomerRef.value',
        'CustomerRef.value',
        'STRING',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - DocNumber',
        'DocNumber',
        'STRING',
        false
      );
      addQBFieldDefinition(qbFields, 'QB - TxnDate', 'TxnDate', 'DATE', false);
      addQBFieldDefinition(
        qbFields,
        'QB - TotalAmt',
        'TotalAmt',
        'NUMBER',
        false
      );
    } else if (qbEntity == 'PurchaseOrder') {
      addQBFieldDefinition(
        qbFields,
        'QB - VendorRef.value',
        'VendorRef.value',
        'STRING',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - DocNumber',
        'DocNumber',
        'STRING',
        false
      );
      addQBFieldDefinition(qbFields, 'QB - TxnDate', 'TxnDate', 'DATE', false);
      addQBFieldDefinition(
        qbFields,
        'QB - TotalAmt',
        'TotalAmt',
        'NUMBER',
        false
      );
    } else if (qbEntity == 'TaxCode') {
      addQBFieldDefinition(qbFields, 'QB - Name', 'Name', 'STRING', true);
      addQBFieldDefinition(
        qbFields,
        'QB - Description',
        'Description',
        'STRING',
        false
      );
    } else if (qbEntity == 'InvoiceLine') {
      addQBFieldDefinition(
        qbFields,
        'QB - Product/Service ID',
        'Line.SalesItemLineDetail.ItemRef.value',
        'STRING',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Amount',
        'Line.Amount',
        'NUMBER',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Quantity',
        'Line.SalesItemLineDetail.Qty',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Unit Price',
        'Line.SalesItemLineDetail.UnitPrice',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Description',
        'Line.Description',
        'STRING',
        false
      );
    } else if (qbEntity == 'CreditMemoLine') {
      addQBFieldDefinition(
        qbFields,
        'QB - Product/Service ID',
        'Line.SalesItemLineDetail.ItemRef.value',
        'STRING',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Amount',
        'Line.Amount',
        'NUMBER',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Quantity',
        'Line.SalesItemLineDetail.Qty',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Unit Price',
        'Line.SalesItemLineDetail.UnitPrice',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Description',
        'Line.Description',
        'STRING',
        false
      );
    } else if (qbEntity == 'PurchaseOrderLine') {
      addQBFieldDefinition(
        qbFields,
        'QB - Product/Service ID',
        'Line.ItemBasedExpenseLineDetail.ItemRef.value',
        'STRING',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Amount',
        'Line.Amount',
        'NUMBER',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Quantity',
        'Line.ItemBasedExpenseLineDetail.Qty',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Unit Price',
        'Line.ItemBasedExpenseLineDetail.UnitPrice',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Description',
        'Line.Description',
        'STRING',
        false
      );
    } else if (qbEntity == 'Estimate') {
      addQBFieldDefinition(
        qbFields,
        'QB - CustomerRef.value',
        'CustomerRef.value',
        'STRING',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - DocNumber',
        'DocNumber',
        'STRING',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - TotalAmt',
        'TotalAmt',
        'NUMBER',
        false
      );
      addQBFieldDefinition(qbFields, 'QB - TxnDate', 'TxnDate', 'DATE', false);
      addQBFieldDefinition(
        qbFields,
        'QB - ExpirationDate',
        'ExpirationDate',
        'DATE',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Customer Memo',
        'CustomerMemo.value',
        'STRING',
        false
      );
    } else if (qbEntity == 'EstimateLine') {
      addQBFieldDefinition(
        qbFields,
        'QB - Product/Service ID',
        'Line.SalesItemLineDetail.ItemRef.value',
        'STRING',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Amount',
        'Line.Amount',
        'NUMBER',
        true
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Quantity',
        'Line.SalesItemLineDetail.Qty',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Unit Price',
        'Line.SalesItemLineDetail.UnitPrice',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        qbFields,
        'QB - Description',
        'Line.Description',
        'STRING',
        false
      );
    }

    applyQBFieldCapabilities(qbEntity, qbFields);
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
    definition.inboundAllowed = true;
    definition.outboundAllowed = true;
    fieldMap.put(value, definition);
  }

  private static void applyQBFieldCapabilities(
    String qbEntity,
    Map<String, QBFieldDefinition> definitions
  ) {
    if (definitions == null) {
      return;
    }
    for (QBFieldDefinition definition : definitions.values()) {
      definition.inboundAllowed = true;
      definition.outboundAllowed = qbEntity == 'Customer'
        ? QBCustomerFieldCapabilities.isOutboundWritable(definition.value)
        : qbEntity == 'Vendor'
          ? QBVendorFieldCapabilities.isOutboundWritable(definition.value)
          : true;
    }
  }

  private static List<Map<String, Object>> convertQBFieldDefinitions(
    Map<String, QBFieldDefinition> definitions
  ) {
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
      row.put('inboundAllowed', definition.inboundAllowed != false);
      row.put('outboundAllowed', definition.outboundAllowed != false);
      result.add(row);
    }
    return result;
  }

  private static List<Map<String, Object>> fetchQBFieldsFromAPI(
    String qbEntity
  ) {
    List<Map<String, Object>> qbFields = new List<Map<String, Object>>();

    String realmId = ConnectorConfigResolver.getValue(
      'qbo',
      'QuickBooks_Realm_ID__c'
    );
    if (String.isBlank(realmId)) {
      throw new CalloutException('Realm ID is missing in configuration.');
    }
    realmId = realmId.trim();

    HttpRequest req = new HttpRequest();
    String query = EncodingUtil.urlEncode(
      'SELECT * FROM ' + qbEntity + ' MAXRESULTS 1',
      'UTF-8'
    );
    req.setEndpoint(
      QB_API_ENDPOINT + '/v3/company/' + realmId + '/query?query=' + query
    );
    req.setMethod('GET');
    req.setHeader('Accept', 'application/json');
    req.setTimeout(20000);

    HttpResponse res = new Http().send(req);
    if (res.getStatusCode() != 200) {
      System.debug(
        LoggingLevel.WARN,
        'FieldMappingController.fetchQBFieldsFromAPI failed with status ' +
          res.getStatusCode() +
          ': ' +
          res.getBody()
      );
      throw new CalloutException('QB API error: ' + res.getStatusCode());
    }

    Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(
      res.getBody()
    );
    Map<String, Object> queryResponse = (Map<String, Object>) responseBody.get(
      'QueryResponse'
    );

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
        } else if (
          value instanceof Integer ||
          value instanceof Long ||
          value instanceof Double ||
          value instanceof Decimal
        ) {
          qbType = 'NUMBER';
        } else {
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

  private static String resolveShopifyEntity(
    String sfObject,
    String shopifyObject
  ) {
    return IntegrationEntityRegistry.resolveExternalEntity(
      INTEGRATION_SHOPIFY,
      sfObject,
      shopifyObject,
      'Customer'
    );
  }

  private static Map<String, QBFieldDefinition> getFallbackShopifyFieldDefinitions(
    String entity
  ) {
    Map<String, QBFieldDefinition> fields = new Map<String, QBFieldDefinition>();

    if (entity == 'Customer') {
      addQBFieldDefinition(fields, 'Shopify - id', 'id', 'STRING', true);
      addQBFieldDefinition(fields, 'Shopify - email', 'email', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'Shopify - first_name',
        'first_name',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - last_name',
        'last_name',
        'STRING',
        true
      );
      addQBFieldDefinition(fields, 'Shopify - phone', 'phone', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'Shopify - tax_exempt',
        'tax_exempt',
        'BOOLEAN',
        false
      );
      addQBFieldDefinition(fields, 'Shopify - tags', 'tags', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'Shopify - total_spent',
        'total_spent',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - orders_count',
        'orders_count',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - default_address.address1',
        'default_address.address1',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - default_address.city',
        'default_address.city',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - default_address.province',
        'default_address.province',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - default_address.zip',
        'default_address.zip',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - default_address.country',
        'default_address.country',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - sms_marketing_consent.state',
        'sms_marketing_consent.state',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - sms_marketing_consent.opt_in_level',
        'sms_marketing_consent.opt_in_level',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - email_marketing_consent.state',
        'email_marketing_consent.state',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - email_marketing_consent.opt_in_level',
        'email_marketing_consent.opt_in_level',
        'STRING',
        false
      );
    } else if (entity == 'Order') {
      addQBFieldDefinition(fields, 'Shopify - id', 'id', 'STRING', false);
      addQBFieldDefinition(fields, 'Shopify - name', 'name', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'Shopify - created_at',
        'created_at',
        'DATE',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - total_price',
        'total_price',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - total_discounts',
        'total_discounts',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - total_tax',
        'total_tax',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - financial_status',
        'financial_status',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - fulfillment_status',
        'fulfillment_status',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - payment_gateway_names',
        'payment_gateway_names',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - contact_email',
        'contact_email',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Shopify - cancel_reason',
        'cancel_reason',
        'STRING',
        false
      );
    } else if (entity == 'Product') {
      addQBFieldDefinition(fields, 'Shopify - id', 'id', 'STRING', true);
      addQBFieldDefinition(fields, 'Shopify - title', 'title', 'STRING', true);
      addQBFieldDefinition(
        fields,
        'Shopify - status',
        'status',
        'STRING',
        false
      );
    } else if (entity == 'LineItem') {
      addQBFieldDefinition(fields, 'Shopify - id', 'id', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'Shopify - quantity',
        'quantity',
        'NUMBER',
        false
      );
      addQBFieldDefinition(fields, 'Shopify - price', 'price', 'NUMBER', false);
      addQBFieldDefinition(fields, 'Shopify - sku', 'sku', 'STRING', false);
      addQBFieldDefinition(fields, 'Shopify - title', 'title', 'STRING', false);
    }

    return fields;
  }

  private static String resolveMetaEntity(String sfObject, String metaObject) {
    if (String.isNotBlank(metaObject)) {
      return normalizeMetaEntity(metaObject);
    }
    String objectKey = normalizeObjectToken(sfObject);
    if (objectKey == 'campaign')
      return 'campaign';
    if (objectKey == 'metaadset')
      return 'adset';
    if (objectKey == 'metaad')
      return 'ad';
    if (objectKey == 'lead')
      return 'leadad';
    if (objectKey == 'campaignmember')
      return 'campaignmemberattribution';
    if (objectKey == 'socialinteraction')
      return 'commentattribution';
    if (objectKey == 'metainsight' || objectKey == 'campaigninsight')
      return 'insights';
    return 'campaign';
  }

  private static String normalizeMetaEntity(String metaObject) {
    String value = normalizeObjectToken(metaObject);
    if (value == 'campaign')
      return 'campaign';
    if (value == 'adset' || value == 'adsets')
      return 'adset';
    if (value == 'ad' || value == 'ads')
      return 'ad';
    if (value == 'lead' || value == 'leadad' || value == 'leadads')
      return 'leadad';
    if (value == 'campaignmemberattribution')
      return 'campaignmemberattribution';
    if (value == 'commentattribution')
      return 'commentattribution';
    if (value == 'insight' || value == 'insights')
      return 'insights';
    return metaObject;
  }

  private static String normalizeObjectToken(String apiName) {
    if (String.isBlank(apiName)) {
      return '';
    }
    String token = apiName.trim();
    if (token.endsWith('__c')) {
      List<String> parts = token.split('__');
      if (parts.size() == 3) {
        token = parts[1] + '__c';
      }
      token = token.substring(0, token.length() - 3);
    }
    return token.replaceAll('[^A-Za-z0-9]', '').toLowerCase();
  }

  private static Map<String, QBFieldDefinition> getFallbackMetaFieldDefinitions(
    String entity
  ) {
    Map<String, QBFieldDefinition> fields = new Map<String, QBFieldDefinition>();
    String normalizedEntity = normalizeMetaEntity(entity);

    if (normalizedEntity == 'campaign') {
      addQBFieldDefinition(fields, 'Meta - Campaign ID', 'id', 'STRING', true);
      addQBFieldDefinition(
        fields,
        'Meta - Campaign Name',
        'name',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'Meta - Ad Account ID',
        'account_id',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Objective',
        'objective',
        'STRING',
        false
      );
      addQBFieldDefinition(fields, 'Meta - Status', 'status', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'Meta - Daily Budget',
        'daily_budget',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Lifetime Budget',
        'lifetime_budget',
        'NUMBER',
        false
      );
    } else if (normalizedEntity == 'adset') {
      addQBFieldDefinition(fields, 'Meta - Ad Set ID', 'id', 'STRING', true);
      addQBFieldDefinition(
        fields,
        'Meta - Ad Set Name',
        'name',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'Meta - Campaign ID',
        'campaign_id',
        'STRING',
        true
      );
      addQBFieldDefinition(fields, 'Meta - Status', 'status', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'Meta - Optimization Goal',
        'optimization_goal',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Daily Budget',
        'daily_budget',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Lifetime Budget',
        'lifetime_budget',
        'NUMBER',
        false
      );
    } else if (normalizedEntity == 'ad') {
      addQBFieldDefinition(fields, 'Meta - Ad ID', 'id', 'STRING', true);
      addQBFieldDefinition(fields, 'Meta - Ad Name', 'name', 'STRING', true);
      addQBFieldDefinition(
        fields,
        'Meta - Campaign ID',
        'campaign_id',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'Meta - Ad Set ID',
        'adset_id',
        'STRING',
        true
      );
      addQBFieldDefinition(fields, 'Meta - Status', 'status', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'Meta - Creative ID',
        'creative.id',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Preview Link',
        'preview_shareable_link',
        'STRING',
        false
      );
    } else if (normalizedEntity == 'leadad') {
      addQBFieldDefinition(fields, 'Meta - Lead ID', 'id', 'STRING', true);
      addQBFieldDefinition(
        fields,
        'Meta - Campaign ID',
        'campaign_id',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Ad Set ID',
        'adset_id',
        'STRING',
        false
      );
      addQBFieldDefinition(fields, 'Meta - Ad ID', 'ad_id', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'Meta - Form ID',
        'form_id',
        'STRING',
        false
      );
      addQBFieldDefinition(fields, 'Meta - Email', 'email', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'Meta - Phone Number',
        'phone_number',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Full Name',
        'full_name',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - First Name',
        'first_name',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Last Name',
        'last_name',
        'STRING',
        false
      );
    } else if (normalizedEntity == 'campaignmemberattribution') {
      addQBFieldDefinition(
        fields,
        'Meta - Leadgen ID',
        'leadgen_id',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'Meta - Campaign ID',
        'campaign_id',
        'STRING',
        true
      );
      addQBFieldDefinition(fields, 'Meta - Status', 'status', 'STRING', false);
    } else if (normalizedEntity == 'commentattribution') {
      addQBFieldDefinition(
        fields,
        'Meta - Comment ID',
        'comment_id',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'Meta - Post ID',
        'post_id',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Campaign ID',
        'campaign_id',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Comment Text',
        'comment_text',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'Meta - Commenter Name',
        'commenter_name',
        'STRING',
        false
      );
    } else if (normalizedEntity == 'insights') {
      addQBFieldDefinition(fields, 'Meta - Insight ID', 'id', 'STRING', true);
      addQBFieldDefinition(fields, 'Meta - Spend', 'spend', 'NUMBER', false);
      addQBFieldDefinition(
        fields,
        'Meta - Impressions',
        'impressions',
        'NUMBER',
        false
      );
      addQBFieldDefinition(fields, 'Meta - Clicks', 'clicks', 'NUMBER', false);
      addQBFieldDefinition(fields, 'Meta - Reach', 'reach', 'NUMBER', false);
      addQBFieldDefinition(
        fields,
        'Meta - Lead Actions',
        'actions.lead',
        'NUMBER',
        false
      );
    }
    return fields;
  }

  private static Map<String, QBFieldDefinition> getFallbackNetSuiteFieldDefinitions(
    String entity
  ) {
    Map<String, QBFieldDefinition> fields = new Map<String, QBFieldDefinition>();
    if (entity == 'Customer') {
      addQBFieldDefinition(
        fields,
        'NetSuite - Internal ID',
        'id',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Entity ID',
        'entityid',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Company Name',
        'companyname',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - First Name',
        'firstname',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Last Name',
        'lastname',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Email',
        'email',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Phone',
        'phone',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Billing City',
        'billcity',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Subsidiary',
        'subsidiary',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Currency',
        'currency',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Taxable',
        'taxable',
        'BOOLEAN',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Status',
        'entitystatus',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Last Modified Date',
        'lastmodifieddate',
        'DATETIME',
        false
      );
    } else if (entity == 'Item') {
      addQBFieldDefinition(
        fields,
        'NetSuite - Internal ID',
        'id',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - SKU / Item ID',
        'itemid',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Display Name',
        'displayname',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Description',
        'salesdescription',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Item Type',
        'itemtype',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Base Price',
        'baseprice',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Currency',
        'currency',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Price Level',
        'pricelevel',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Tax Schedule',
        'taxschedule',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Inactive',
        'isinactive',
        'BOOLEAN',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Quantity Available',
        'quantityavailable',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Last Modified Date',
        'lastmodifieddate',
        'DATETIME',
        false
      );
    } else if (entity == 'SalesOrder') {
      addQBFieldDefinition(
        fields,
        'NetSuite - Internal ID',
        'id',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Transaction ID',
        'tranid',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Entity',
        'entity',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Transaction Date',
        'trandate',
        'DATE',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Status',
        'status',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Total',
        'total',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Subsidiary',
        'subsidiary',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Department',
        'department',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Class',
        'class',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Location',
        'location',
        'STRING',
        false
      );
    } else if (entity == 'SalesOrderLine') {
      addQBFieldDefinition(
        fields,
        'NetSuite - Line ID',
        'line',
        'STRING',
        true
      );
      addQBFieldDefinition(fields, 'NetSuite - Item', 'item', 'STRING', true);
      addQBFieldDefinition(
        fields,
        'NetSuite - Description',
        'description',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Quantity',
        'quantity',
        'NUMBER',
        false
      );
      addQBFieldDefinition(fields, 'NetSuite - Rate', 'rate', 'NUMBER', false);
      addQBFieldDefinition(
        fields,
        'NetSuite - Amount',
        'amount',
        'NUMBER',
        false
      );
    } else if (entity == 'Invoice') {
      addQBFieldDefinition(
        fields,
        'NetSuite - Internal ID',
        'id',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Transaction ID',
        'tranid',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Entity',
        'entity',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Transaction Date',
        'trandate',
        'DATE',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Total',
        'total',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Amount Remaining',
        'amountremaining',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Status',
        'status',
        'STRING',
        false
      );
    } else if (entity == 'InvoiceLine') {
      addQBFieldDefinition(
        fields,
        'NetSuite - Line ID',
        'line',
        'STRING',
        true
      );
      addQBFieldDefinition(fields, 'NetSuite - Item', 'item', 'STRING', true);
      addQBFieldDefinition(
        fields,
        'NetSuite - Description',
        'description',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Quantity',
        'quantity',
        'NUMBER',
        false
      );
      addQBFieldDefinition(fields, 'NetSuite - Rate', 'rate', 'NUMBER', false);
      addQBFieldDefinition(
        fields,
        'NetSuite - Amount',
        'amount',
        'NUMBER',
        false
      );
    } else if (entity == 'Payment') {
      addQBFieldDefinition(
        fields,
        'NetSuite - Internal ID',
        'id',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Transaction ID',
        'tranid',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Customer',
        'customer',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Amount',
        'payment',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Account',
        'account',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Applied Invoice',
        'appliedto',
        'STRING',
        false
      );
    } else if (entity == 'Fulfillment') {
      addQBFieldDefinition(
        fields,
        'NetSuite - Internal ID',
        'id',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Created From',
        'createdfrom',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Tracking Number',
        'trackingnumbers',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Ship Date',
        'shipdate',
        'DATE',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Status',
        'status',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'NetSuite - Location',
        'location',
        'STRING',
        false
      );
      addQBFieldDefinition(fields, 'NetSuite - Item', 'item', 'STRING', false);
      addQBFieldDefinition(
        fields,
        'NetSuite - Quantity',
        'quantity',
        'NUMBER',
        false
      );
    }
    return fields;
  }

  private static String resolveNetSuiteEntity(
    String sfObject,
    String netSuiteObject
  ) {
    if (String.isNotBlank(netSuiteObject)) {
      return netSuiteObject;
    }
    String normalizedObject = sfObject;
    if (
      normalizedObject != null &&
      normalizedObject.endsWith('__c') &&
      normalizedObject.split('__').size() == 3
    ) {
      normalizedObject = normalizedObject.split('__')[1] + '__c';
    }
    if (normalizedObject == 'Account' || normalizedObject == 'Contact')
      return 'Customer';
    if (normalizedObject == 'Product2')
      return 'Item';
    if (
      normalizedObject == 'Order' ||
      normalizedObject == 'Quote' ||
      normalizedObject == 'OrderSummary'
    )
      return 'SalesOrder';
    if (
      normalizedObject == 'OrderItem' ||
      normalizedObject == 'QuoteLineItem' ||
      normalizedObject == 'OrderItemSummary'
    )
      return 'SalesOrderLine';
    if (normalizedObject == 'Invoice__c')
      return 'Invoice';
    if (normalizedObject == 'Invoice_Line__c')
      return 'InvoiceLine';
    if (
      normalizedObject == 'Payment' ||
      normalizedObject == 'Portal_Payment_Transaction__c'
    )
      return 'Payment';
    if (
      normalizedObject == 'Shipment' ||
      normalizedObject == 'Carrier_Shipment__c'
    )
      return 'Fulfillment';
    return 'Customer';
  }

  private static String resolveQBEntity(String sfObject, String qbObject) {
    return IntegrationEntityRegistry.resolveExternalEntity(
      INTEGRATION_QBO,
      sfObject,
      qbObject,
      'Invoice'
    );
  }

  private static List<Map<String, String>> getCarrierMappings(
    String integration,
    String actionName,
    String sfObject
  ) {
    List<Map<String, String>> savedMappings = new List<Map<String, String>>();
    try {
      List<Field_Mapping__mdt> records = queryCarrierMappings(
        integration,
        actionName,
        sfObject,
        true
      );
      for (Field_Mapping__mdt record : records) {
        if (
          String.isBlank(record.SF_Field__c) ||
          String.isBlank(record.External_Field__c)
        ) {
          continue;
        }
        Map<String, String> mapping = new Map<String, String>();
        mapping.put('developerName', record.DeveloperName);
        mapping.put('sfField', record.SF_Field__c);
        mapping.put('externalField', record.External_Field__c);
        mapping.put(
          'syncDirection',
          toProviderDirection(integration, record.Sync_Direction__c)
        );
        savedMappings.add(mapping);
      }
    } catch (Exception e) {
      System.debug('Error loading carrier mappings: ' + e.getMessage());
      logCacheableReadError('FieldMappingController.getCarrierMappings', e);
    }
    return savedMappings;
  }

  private static String saveCarrierFieldMappings(
    String integration,
    String actionName,
    String sfObject,
    String mappingsJson
  ) {
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
        String canonicalDirection = toCanonicalCarrierDirection(
          (String) row.get('syncDirection')
        );
        String syncDirection = toProviderDirection(
          integration,
          canonicalDirection
        );
        extField = normalizeCarrierExternalField(
          integration,
          actionName,
          canonicalDirection,
          extField
        );
        if (String.isBlank(sfField) || String.isBlank(extField)) {
          continue;
        }
        if (requestedExternalFields.contains(extField)) {
          String carrierLabel = carrierLabel(integration);
          throw new AuraHandledException(
            'Each ' + carrierLabel + ' field can only be mapped once.'
          );
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

      List<String> carrierSfFields = new List<String>();
      for (MappingRow row : requestedMappings) {
        carrierSfFields.add(row.sfField);
      }
      MappingFieldEligibilityService.assertNoBlockedSalesforceFields(
        carrierSfFields
      );

      Map<String, QBFieldDefinition> fieldDefs = getCarrierFieldDefinitions(
        integration,
        actionName,
        null
      );

      Set<String> mappedFields = new Set<String>();
      for (MappingRow row : requestedMappings) {
        mappedFields.add(row.externalField);
      }
      for (QBFieldDefinition fieldDef : fieldDefs.values()) {
        if (
          requestedDirection == 'SF to Carrier' &&
          fieldDef.required &&
          !mappedFields.contains(fieldDef.value)
        ) {
          String carrierLabel = carrierLabel(integration);
          throw new AuraHandledException(
            'Map every required ' + carrierLabel + ' field before saving.'
          );
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
        if (
          toCanonicalCarrierDirection(existingRecord.Sync_Direction__c) !=
          requestedDirection
        ) {
          continue;
        }
        if (
          existingRecord.Is_Active__c &&
          !requestedExternalFields.contains(existingRecord.External_Field__c)
        ) {
          recordsToDeactivate.add(existingRecord.DeveloperName);
        }
      }

      String nsPrefix = getNamespacePrefix();
      Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
      if (!requestedMappings.isEmpty()) {
        IntegrationObjectMapRegistrationService.addMissingCarrierPair(
          mdContainer,
          integration,
          sfObject,
          actionName
        );
      }
      for (String developerName : recordsToDeactivate) {
        Metadata.CustomMetadata inactiveMetadata = new Metadata.CustomMetadata();
        inactiveMetadata.fullName =
          nsPrefix +
          'Field_Mapping__mdt.' +
          developerName;
        inactiveMetadata.label = developerName;
        addCustomMetadataValue(inactiveMetadata, 'Is_Active__c', false);
        mdContainer.addMetadata(inactiveMetadata);
      }

      for (MappingRow row : requestedMappings) {
        Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
        String canonicalDirection = toCanonicalCarrierDirection(
          row.syncDirection
        );
        String recordKey =
          integrationActionKey +
          (canonicalDirection == 'Carrier to SF' ? '_to_sf' : '_to_carrier');
        customMetadata.fullName =
          nsPrefix +
          'Field_Mapping__mdt.' +
          buildRecordName(recordKey, sfObject, row.externalField);
        String label = sfObject + ' ' + row.sfField;
        customMetadata.label = label.length() > 40
          ? label.substring(0, 40)
          : label;
        addCustomMetadataValue(customMetadata, 'Integration__c', integration);
        addCustomMetadataValue(customMetadata, 'Action__c', actionName);
        addCustomMetadataValue(customMetadata, 'SF_Object__c', sfObject);
        addCustomMetadataValue(customMetadata, 'SF_Field__c', row.sfField);
        addCustomMetadataValue(
          customMetadata,
          'External_Field__c',
          row.externalField
        );
        addCustomMetadataValue(
          customMetadata,
          'Sync_Direction__c',
          row.syncDirection
        );
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
        carrierLabel(integration),
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
    if (
      String.isBlank(integration) ||
      String.isBlank(actionName) ||
      String.isBlank(sfObject)
    ) {
      return records;
    }

    String legacyIntegrationActionKey = integration + '_' + actionName;
    if (activeOnly == true) {
      records.addAll(
        [
          SELECT
            DeveloperName,
            Action__c,
            SF_Field__c,
            External_Field__c,
            Sync_Direction__c,
            Is_Active__c
          FROM Field_Mapping__mdt
          WHERE
            Integration__c = :integration
            AND Action__c = :actionName
            AND SF_Object__c = :sfObject
            AND Is_Active__c = TRUE
        ]
      );
      records.addAll(
        [
          SELECT
            DeveloperName,
            Action__c,
            SF_Field__c,
            External_Field__c,
            Sync_Direction__c,
            Is_Active__c
          FROM Field_Mapping__mdt
          WHERE
            Integration__c = :legacyIntegrationActionKey
            AND SF_Object__c = :sfObject
            AND Is_Active__c = TRUE
        ]
      );
      return records;
    }

    records.addAll(
      [
        SELECT
          DeveloperName,
          Action__c,
          SF_Field__c,
          External_Field__c,
          Sync_Direction__c,
          Is_Active__c
        FROM Field_Mapping__mdt
        WHERE
          Integration__c = :integration
          AND Action__c = :actionName
          AND SF_Object__c = :sfObject
      ]
    );
    records.addAll(
      [
        SELECT
          DeveloperName,
          Action__c,
          SF_Field__c,
          External_Field__c,
          Sync_Direction__c,
          Is_Active__c
        FROM Field_Mapping__mdt
        WHERE
          Integration__c = :legacyIntegrationActionKey
          AND SF_Object__c = :sfObject
      ]
    );
    return records;
  }

  private static String toCanonicalCarrierDirection(String directionValue) {
    if (String.isBlank(directionValue)) {
      return 'SF to Carrier';
    }
    String normalized = directionValue.trim().toLowerCase();
    if (
      normalized == 'carrier to sf' ||
      normalized == 'carrier to salesforce' ||
      normalized == 'fedex to sf' ||
      normalized == 'ups to sf' ||
      normalized == 'dhl to sf'
    ) {
      return 'Carrier to SF';
    }
    return 'SF to Carrier';
  }

  private static String toProviderDirection(
    String integration,
    String directionValue
  ) {
    String canonical = toCanonicalCarrierDirection(directionValue);
    if (integration == 'fedex') {
      return canonical == 'Carrier to SF' ? 'FedEx to SF' : 'SF to FedEx';
    }
    if (integration == 'ups') {
      return canonical == 'Carrier to SF' ? 'UPS to SF' : 'SF to UPS';
    }
    if (integration == 'dhl') {
      return canonical == 'Carrier to SF' ? 'DHL to SF' : 'SF to DHL';
    }
    return canonical;
  }

  private static String carrierLabel(String integration) {
    if (integration == 'fedex') {
      return 'FedEx';
    }
    if (integration == 'ups') {
      return 'UPS';
    }
    if (integration == 'dhl') {
      return 'DHL';
    }
    return 'Carrier';
  }

  private static Map<String, QBFieldDefinition> getCarrierFieldDefinitions(
    String integration,
    String actionName,
    String direction
  ) {
    if (integration == 'fedex') {
      return getFedExFieldDefinitions(actionName, direction);
    }
    if (integration == 'ups') {
      return getUPSFieldDefinitions(actionName, direction);
    }
    if (integration == 'dhl') {
      return getDHLFieldDefinitions(actionName, direction);
    }
    return new Map<String, QBFieldDefinition>();
  }

  private static String normalizeCarrierExternalField(
    String integration,
    String actionName,
    String canonicalDirection,
    String externalField
  ) {
    if (String.isBlank(externalField)) {
      return externalField;
    }
    if (
      (integration != 'fedex' &&
      integration != 'dhl') ||
      actionName != 'validateAddress' ||
      canonicalDirection != 'Carrier to SF'
    ) {
      return externalField;
    }
    if (
      externalField.startsWith('validatedAddress[') &&
      externalField.endsWith(']')
    ) {
      externalField =
        'validatedAddress.' +
        externalField.substring(
          'validatedAddress['.length(),
          externalField.length() - 1
        );
    }
    if (externalField.startsWith('validatedAddress.')) {
      return externalField;
    }

    Set<String> validateAddressResponseFields = new Set<String>{
      'streetLines[0]',
      'streetLines[1]',
      'city',
      'stateOrProvinceCode',
      'postalCode',
      'countryCode',
      'classification'
    };
    return validateAddressResponseFields.contains(externalField)
      ? 'validatedAddress.' + externalField
      : externalField;
  }

  private static Map<String, QBFieldDefinition> getFedExFieldDefinitions(
    String actionName,
    String direction
  ) {
    Map<String, QBFieldDefinition> fields = new Map<String, QBFieldDefinition>();
    String act = String.isBlank(actionName) ? '' : actionName;

    if (act == 'validateAddress') {
      Boolean inbound =
        toCanonicalCarrierDirection(direction) == 'Carrier to SF';
      String responsePrefix = inbound ? 'validatedAddress.' : '';
      addQBFieldDefinition(
        fields,
        inbound
          ? 'FedEx - validatedAddress.streetLines[0]'
          : 'FedEx - streetLines[0]',
        responsePrefix + 'streetLines[0]',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        inbound ? 'FedEx - validatedAddress.city' : 'FedEx - city',
        responsePrefix + 'city',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        inbound
          ? 'FedEx - validatedAddress.stateOrProvinceCode'
          : 'FedEx - stateOrProvinceCode',
        responsePrefix + 'stateOrProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        inbound ? 'FedEx - validatedAddress.postalCode' : 'FedEx - postalCode',
        responsePrefix + 'postalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        inbound
          ? 'FedEx - validatedAddress.countryCode'
          : 'FedEx - countryCode',
        responsePrefix + 'countryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        inbound
          ? 'FedEx - validatedAddress.streetLines[1]'
          : 'FedEx - streetLines[1]',
        responsePrefix + 'streetLines[1]',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        inbound
          ? 'FedEx - validatedAddress.classification'
          : 'FedEx - classification',
        responsePrefix + 'classification',
        'STRING',
        false
      );
    } else if (act == 'getRateQuote') {
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.streetLines[0]',
        'shipper.streetLines[0]',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.city',
        'shipper.city',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.stateOrProvinceCode',
        'shipper.stateOrProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.postalCode',
        'shipper.postalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.countryCode',
        'shipper.countryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.streetLines[0]',
        'recipient.streetLines[0]',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.city',
        'recipient.city',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.stateOrProvinceCode',
        'recipient.stateOrProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.postalCode',
        'recipient.postalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.countryCode',
        'recipient.countryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - requestedPackageLineItems[0].weight.value',
        'requestedPackageLineItems[0].weight.value',
        'NUMBER',
        true
      );
    } else if (act == 'createShipment') {
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.contact.personName',
        'shipper.contact.personName',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.contact.phoneNumber',
        'shipper.contact.phoneNumber',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.address.streetLines[0]',
        'shipper.address.streetLines[0]',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.address.city',
        'shipper.address.city',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.address.stateOrProvinceCode',
        'shipper.address.stateOrProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.address.postalCode',
        'shipper.address.postalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.address.countryCode',
        'shipper.address.countryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.contact.personName',
        'recipient.contact.personName',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.contact.phoneNumber',
        'recipient.contact.phoneNumber',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.address.streetLines[0]',
        'recipient.address.streetLines[0]',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.address.city',
        'recipient.address.city',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.address.stateOrProvinceCode',
        'recipient.address.stateOrProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.address.postalCode',
        'recipient.address.postalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.address.countryCode',
        'recipient.address.countryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - requestedPackageLineItems[0].weight.value',
        'requestedPackageLineItems[0].weight.value',
        'NUMBER',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - shipper.contact.companyName',
        'shipper.contact.companyName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.contact.companyName',
        'recipient.contact.companyName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'FedEx - requestedPackageLineItems[0].dimensions.length',
        'requestedPackageLineItems[0].dimensions.length',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'FedEx - requestedPackageLineItems[0].dimensions.width',
        'requestedPackageLineItems[0].dimensions.width',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'FedEx - requestedPackageLineItems[0].dimensions.height',
        'requestedPackageLineItems[0].dimensions.height',
        'NUMBER',
        false
      );
    } else if (act == 'storeTrackingNumber') {
      addQBFieldDefinition(
        fields,
        'FedEx - shipment.masterTrackingNumber',
        'shipment.masterTrackingNumber',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'FedEx - package.trackingNumber',
        'package.trackingNumber',
        'STRING',
        false
      );
    } else if (act == 'syncTrackingStatus') {
      addQBFieldDefinition(
        fields,
        'FedEx - tracking.trackingNumber',
        'tracking.trackingNumber',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - tracking.latestStatus',
        'tracking.latestStatus',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'FedEx - tracking.statusCode',
        'tracking.statusCode',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'FedEx - tracking.statusDescription',
        'tracking.statusDescription',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'FedEx - tracking.isTerminal',
        'tracking.isTerminal',
        'BOOLEAN',
        false
      );
    } else if (act == 'handleDeliveryExceptions') {
      addQBFieldDefinition(
        fields,
        'FedEx - tracking.statusDescription',
        'tracking.statusDescription',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'FedEx - tracking.statusCode',
        'tracking.statusCode',
        'STRING',
        false
      );
    } else if (act == 'createReturnLabel') {
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.contact.personName',
        'recipient.contact.personName',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.contact.phoneNumber',
        'recipient.contact.phoneNumber',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.address.streetLines[0]',
        'recipient.address.streetLines[0]',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.address.city',
        'recipient.address.city',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.address.stateOrProvinceCode',
        'recipient.address.stateOrProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.address.postalCode',
        'recipient.address.postalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - recipient.address.countryCode',
        'recipient.address.countryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'FedEx - requestedPackageLineItems[0].weight.value',
        'requestedPackageLineItems[0].weight.value',
        'NUMBER',
        true
      );
    } else if (act == 'voidShipment') {
      addQBFieldDefinition(
        fields,
        'FedEx - masterTrackingNumber',
        'masterTrackingNumber',
        'STRING',
        true
      );
    } else {
      addQBFieldDefinition(
        fields,
        'FedEx - masterTrackingNumber',
        'masterTrackingNumber',
        'STRING',
        false
      );
    }

    return fields;
  }

  private static Map<String, QBFieldDefinition> getUPSFieldDefinitions(
    String actionName,
    String direction
  ) {
    Map<String, QBFieldDefinition> fields = new Map<String, QBFieldDefinition>();
    String act = String.isBlank(actionName) ? '' : actionName;

    if (act == 'validateAddress') {
      addQBFieldDefinition(
        fields,
        'UPS - AddressLine',
        'AddressLine',
        'STRING',
        true
      );
      addQBFieldDefinition(fields, 'UPS - City', 'City', 'STRING', true);
      addQBFieldDefinition(
        fields,
        'UPS - StateProvinceCode',
        'StateProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - PostalCode',
        'PostalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - CountryCode',
        'CountryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - AddressLine2',
        'AddressLine2',
        'STRING',
        false
      );
    } else if (act == 'getRateQuote') {
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Address.AddressLine',
        'Shipper.Address.AddressLine',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Address.City',
        'Shipper.Address.City',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Address.StateProvinceCode',
        'Shipper.Address.StateProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Address.PostalCode',
        'Shipper.Address.PostalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Address.CountryCode',
        'Shipper.Address.CountryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.AddressLine',
        'ShipTo.Address.AddressLine',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.City',
        'ShipTo.Address.City',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.StateProvinceCode',
        'ShipTo.Address.StateProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.PostalCode',
        'ShipTo.Address.PostalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.CountryCode',
        'ShipTo.Address.CountryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Package.PackageWeight.Weight',
        'Package.PackageWeight.Weight',
        'NUMBER',
        true
      );
    } else if (act == 'createShipment') {
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Name',
        'Shipper.Name',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Phone.Number',
        'Shipper.Phone.Number',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Address.AddressLine',
        'Shipper.Address.AddressLine',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Address.City',
        'Shipper.Address.City',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Address.StateProvinceCode',
        'Shipper.Address.StateProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Address.PostalCode',
        'Shipper.Address.PostalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.Address.CountryCode',
        'Shipper.Address.CountryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Name',
        'ShipTo.Name',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Phone.Number',
        'ShipTo.Phone.Number',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.AddressLine',
        'ShipTo.Address.AddressLine',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.City',
        'ShipTo.Address.City',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.StateProvinceCode',
        'ShipTo.Address.StateProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.PostalCode',
        'ShipTo.Address.PostalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.CountryCode',
        'ShipTo.Address.CountryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Package.PackageWeight.Weight',
        'Package.PackageWeight.Weight',
        'NUMBER',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Shipper.AttentionName',
        'Shipper.AttentionName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.AttentionName',
        'ShipTo.AttentionName',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'UPS - Package.Dimensions.Length',
        'Package.Dimensions.Length',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'UPS - Package.Dimensions.Width',
        'Package.Dimensions.Width',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'UPS - Package.Dimensions.Height',
        'Package.Dimensions.Height',
        'NUMBER',
        false
      );
      addQBFieldDefinition(
        fields,
        'UPS - Package.Description',
        'Package.Description',
        'STRING',
        false
      );
    } else if (act == 'storeTrackingNumber') {
      addQBFieldDefinition(
        fields,
        'UPS - shipment.masterTrackingNumber',
        'shipment.masterTrackingNumber',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'UPS - package.trackingNumber',
        'package.trackingNumber',
        'STRING',
        false
      );
    } else if (act == 'syncTrackingStatus') {
      addQBFieldDefinition(
        fields,
        'UPS - tracking.trackingNumber',
        'tracking.trackingNumber',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - tracking.latestStatus',
        'tracking.latestStatus',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'UPS - tracking.statusCode',
        'tracking.statusCode',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'UPS - tracking.statusDescription',
        'tracking.statusDescription',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'UPS - tracking.isTerminal',
        'tracking.isTerminal',
        'BOOLEAN',
        false
      );
    } else if (act == 'handleDeliveryExceptions') {
      addQBFieldDefinition(
        fields,
        'UPS - tracking.statusDescription',
        'tracking.statusDescription',
        'STRING',
        false
      );
      addQBFieldDefinition(
        fields,
        'UPS - tracking.statusCode',
        'tracking.statusCode',
        'STRING',
        false
      );
    } else if (act == 'createReturnLabel') {
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Name',
        'ShipTo.Name',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Phone.Number',
        'ShipTo.Phone.Number',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.AddressLine',
        'ShipTo.Address.AddressLine',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.City',
        'ShipTo.Address.City',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.StateProvinceCode',
        'ShipTo.Address.StateProvinceCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.PostalCode',
        'ShipTo.Address.PostalCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - ShipTo.Address.CountryCode',
        'ShipTo.Address.CountryCode',
        'STRING',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Package.PackageWeight.Weight',
        'Package.PackageWeight.Weight',
        'NUMBER',
        true
      );
      addQBFieldDefinition(
        fields,
        'UPS - Package.Description',
        'Package.Description',
        'STRING',
        true
      );
    } else if (act == 'voidShipment') {
      addQBFieldDefinition(
        fields,
        'UPS - masterTrackingNumber',
        'masterTrackingNumber',
        'STRING',
        true
      );
    } else {
      addQBFieldDefinition(
        fields,
        'UPS - masterTrackingNumber',
        'masterTrackingNumber',
        'STRING',
        false
      );
    }

    return fields;
  }

  private static Map<String, QBFieldDefinition> getDHLFieldDefinitions(
    String actionName,
    String direction
  ) {
    Map<String, QBFieldDefinition> fields = getFedExFieldDefinitions(
      actionName,
      direction
    );
    for (QBFieldDefinition field : fields.values()) {
      if (String.isNotBlank(field.label)) {
        field.label = field.label.replace('FedEx - ', 'DHL - ');
      }
    }
    return fields;
  }

  private static String buildRecordName(
    String integration,
    String sfObject,
    String extField
  ) {
    return buildRecordName(integration, sfObject, null, extField);
  }

  // qbObject is folded into the unique name (and hash) so that the same external
  // field mapped on different QBO objects (e.g. Account->Customer.DisplayName vs
  // Account->Vendor.DisplayName) produces distinct metadata records instead of
  // colliding on one.
  private static String buildRecordName(
    String integration,
    String sfObject,
    String qbObject,
    String extField
  ) {
    String cleanObjName = sfObject.replace('__c', '').replaceAll('__+', '_');
    String sanitizedExternalField = extField.replaceAll('[^a-zA-Z0-9]', '_')
      .replaceAll('__+', '_');
    String objToken = String.isBlank(qbObject)
      ? ''
      : '_' + qbObject.replaceAll('[^a-zA-Z0-9]', '_').replaceAll('__+', '_');
    String baseName =
      integration +
      '_' +
      cleanObjName +
      objToken +
      '_' +
      sanitizedExternalField;
    String hashSuffix =
      '_' +
      EncodingUtil.convertToHex(
          Crypto.generateDigest('MD5', Blob.valueOf(baseName))
        )
        .substring(0, 8)
        .toLowerCase();

    Integer maxPrefixLength = 40 - hashSuffix.length();
    String prefix = baseName.length() > maxPrefixLength
      ? baseName.substring(0, maxPrefixLength)
      : baseName;

    prefix = prefix.replaceAll('_+$', '');
    if (prefix.length() + hashSuffix.length() > 40) {
      prefix = prefix.substring(0, 40 - hashSuffix.length())
        .replaceAll('_+$', '');
    }
    return prefix + hashSuffix;
  }

  private static void addCustomMetadataValue(
    Metadata.CustomMetadata metadataRecord,
    String fieldName,
    Object value
  ) {
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
    public Boolean inboundAllowed { get; set; }
    public Boolean outboundAllowed { get; set; }

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

    public MappingRow(
      String sfField,
      String externalField,
      String syncDirection
    ) {
      this.sfField = sfField;
      this.externalField = externalField;
      this.syncDirection = syncDirection;
    }
  }

  @AuraEnabled
  public static String saveChildFieldMappings(
    String integration,
    String sfObject,
    String qbObject,
    String mappingsJson
  ) {
    try {
      List<Object> rawList = String.isBlank(mappingsJson)
        ? new List<Object>()
        : (List<Object>) JSON.deserializeUntyped(mappingsJson);
      List<MappingRow> requestedMappings = new List<MappingRow>();
      Set<String> requestedExternalFields = new Set<String>();

      for (Object objRow : rawList) {
        Map<String, Object> row = (Map<String, Object>) objRow;
        String sfField = (String) row.get('sfField');
        String extField = (String) row.get('qbField');
        String syncDirection = (String) row.get('syncDirection');
        if (String.isBlank(syncDirection))
          syncDirection = DIRECTION_TWO_WAY;

        if (String.isBlank(sfField) || String.isBlank(extField))
          continue;
        if (requestedExternalFields.contains(extField)) {
          throw new AuraHandledException(
            'Each QuickBooks field can only be mapped once.'
          );
        }
        requestedMappings.add(new MappingRow(sfField, extField, syncDirection));
        requestedExternalFields.add(extField);
      }

      // Existing active mappings for this child object
      List<Field_Mapping__mdt> existingMappings = [
        SELECT DeveloperName, External_Field__c, Is_Active__c
        FROM Field_Mapping__mdt
        WHERE Integration__c = :integration AND SF_Object__c = :sfObject
      ];

      List<String> recordsToDeactivate = new List<String>();
      for (Field_Mapping__mdt existingRecord : existingMappings) {
        if (
          existingRecord.Is_Active__c &&
          !requestedExternalFields.contains(existingRecord.External_Field__c)
        ) {
          recordsToDeactivate.add(existingRecord.DeveloperName);
        }
      }

      String nsPrefix = getNamespacePrefix();
      Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();

      for (String developerName : recordsToDeactivate) {
        Metadata.CustomMetadata inactiveMetadata = new Metadata.CustomMetadata();
        inactiveMetadata.fullName =
          nsPrefix +
          'Field_Mapping__mdt.' +
          developerName;
        inactiveMetadata.label = developerName;
        addCustomMetadataValue(inactiveMetadata, 'Is_Active__c', false);
        mdContainer.addMetadata(inactiveMetadata);
      }

      for (MappingRow row : requestedMappings) {
        Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
        customMetadata.fullName =
          nsPrefix +
          'Field_Mapping__mdt.' +
          buildRecordName(integration, sfObject, row.externalField);
        String label = sfObject + ' ' + row.sfField;
        customMetadata.label = label.length() > 40
          ? label.substring(0, 40)
          : label;

        addCustomMetadataValue(customMetadata, 'Integration__c', integration);
        addCustomMetadataValue(customMetadata, 'SF_Object__c', sfObject);
        addCustomMetadataValue(customMetadata, 'SF_Field__c', row.sfField);
        addCustomMetadataValue(
          customMetadata,
          'External_Field__c',
          row.externalField
        );
        addCustomMetadataValue(
          customMetadata,
          'Sync_Direction__c',
          row.syncDirection
        );
        addCustomMetadataValue(customMetadata, 'Is_Active__c', true);

        mdContainer.addMetadata(customMetadata);
      }

      if (Test.isRunningTest())
        return 'Child Mappings Deployment Started!';
      if (requestedMappings.isEmpty() && recordsToDeactivate.isEmpty())
        return 'Child mappings updated successfully.';

      Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, null);
      return 'Child Mappings Deployment Started! Job ID: ' + jobId;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static Boolean getDraftOrderSetting() {
    try {
      return ConnectorConfigResolver.getBoolean(
        'qbo',
        'Map_Draft_Orders_as_Estimates__c'
      );
    } catch (Exception e) {
      return false;
    }
  }

  @AuraEnabled
  public static void saveDraftOrderSetting(Boolean value) {
    try {
      ConnectorConfigService.upsertNonSecretValue(
        'qbo',
        'Map_Draft_Orders_as_Estimates__c',
        String.valueOf(value)
      );
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}