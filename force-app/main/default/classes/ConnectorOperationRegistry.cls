public inherited sharing class ConnectorOperationRegistry {
  private static final Set<String> BOTH_DIRECTIONS = new Set<String>{
    'both',
    'bidirectional'
  };
  private static final Set<String> GENERIC_MAPPING_OPERATIONS = new Set<String>{
    'fieldmapping',
    'mapping'
  };
  private static String shopifyApprovedStoreUrl;

  public class OperationDefinition {
    public String connectorKey { get; set; }
    public String operationKey { get; set; }
    public String direction { get; set; }
    public String salesforceObject { get; set; }
    public String externalEntity { get; set; }
    public String namedCredential { get; set; }
    public String relativeEndpoint { get; set; }
    public String approvedBaseUrl { get; set; }
    public Integer maximumPages { get; set; }
    public String executorClassName { get; set; }

    public OperationDefinition() {
      maximumPages = ConnectorHttpClient.DEFAULT_MAX_PAGES;
    }

    public String identity() {
      return operationIdentity(
        connectorKey,
        operationKey,
        direction,
        salesforceObject,
        externalEntity
      );
    }
  }

  @TestVisible
  private static Map<String, OperationDefinition> testDefinitions = new Map<String, OperationDefinition>();

  public static OperationDefinition resolve(ConnectorExecutionRequest request) {
    if (request == null) {
      throw new ConnectorOperationRegistryException(
        'Connector execution request is required.'
      );
    }
    assertSafeToken(request.connectorKey, 'Connector key');
    assertSafeToken(request.operationKey, 'Operation key');
    String requestedDirection = normalizeDirection(request.direction);
    String requestedObject = canonicalObjectName(request.salesforceObject);
    String requestedEntity = validateExternalEntity(request.externalEntity);

    ConnectorRegistryService.ConnectorDescriptor connector = ConnectorRegistryService.byKey(
      request.connectorKey
    );
    if (connector == null || connector.enabled != true) {
      throw new ConnectorOperationRegistryException(
        'Unsupported or inactive connector.'
      );
    }

    String testKey = operationIdentity(
      connector.connectorKey,
      request.operationKey,
      requestedDirection,
      requestedObject,
      requestedEntity
    );
    if (Test.isRunningTest() && testDefinitions.containsKey(testKey)) {
      return copyDefinition(testDefinitions.get(testKey));
    }

    OperationDefinition fallbackDefinition;
    for (OperationDefinition definition : definitionsFor(connector)) {
      if (
        matches(
          definition,
          request.operationKey,
          requestedDirection,
          requestedObject,
          requestedEntity
        )
      ) {
        if (String.isNotBlank(definition.executorClassName)) {
          return copyDefinition(definition);
        }
        if (fallbackDefinition == null) {
          fallbackDefinition = definition;
        }
      }
    }
    if (fallbackDefinition != null) {
      return copyDefinition(fallbackDefinition);
    }
    throw new ConnectorOperationRegistryException(
      'Unsupported connector operation, direction, or object mapping.'
    );
  }

  public static String normalizeDirection(String direction) {
    String normalized = normalize(direction);
    if (
      normalized == 'inbound' ||
      normalized == 'in' ||
      normalized == 'tosalesforce'
    ) {
      return ConnectorExecutionRequest.DIRECTION_INBOUND;
    }
    if (
      normalized == 'outbound' ||
      normalized == 'out' ||
      normalized == 'fromsalesforce'
    ) {
      return ConnectorExecutionRequest.DIRECTION_OUTBOUND;
    }
    throw new ConnectorOperationRegistryException(
      'Direction must be Inbound or Outbound.'
    );
  }

  @TestVisible
  private static void registerTestOperation(OperationDefinition definition) {
    if (!Test.isRunningTest()) {
      throw new ConnectorOperationRegistryException(
        'Test operation registration is unavailable outside tests.'
      );
    }
    validateDefinition(definition);
    ConnectorRegistryService.ConnectorDescriptor connector = ConnectorRegistryService.byKey(
      definition.connectorKey
    );
    if (connector == null) {
      throw new ConnectorOperationRegistryException(
        'Test operation must use a registered connector.'
      );
    }
    definition.connectorKey = connector.connectorKey;
    definition.direction = normalizeDefinitionDirection(definition.direction);
    definition.salesforceObject = canonicalObjectName(
      definition.salesforceObject
    );
    definition.externalEntity = validateExternalEntity(
      definition.externalEntity
    );
    if (BOTH_DIRECTIONS.contains(normalize(definition.direction))) {
      testDefinitions.put(
        operationIdentity(
          definition.connectorKey,
          definition.operationKey,
          ConnectorExecutionRequest.DIRECTION_INBOUND,
          definition.salesforceObject,
          definition.externalEntity
        ),
        copyDefinition(definition)
      );
      testDefinitions.put(
        operationIdentity(
          definition.connectorKey,
          definition.operationKey,
          ConnectorExecutionRequest.DIRECTION_OUTBOUND,
          definition.salesforceObject,
          definition.externalEntity
        ),
        copyDefinition(definition)
      );
    } else {
      testDefinitions.put(definition.identity(), copyDefinition(definition));
    }
  }

  @TestVisible
  private static void clearTestOperations() {
    testDefinitions.clear();
  }

  private static List<OperationDefinition> definitionsFor(
    ConnectorRegistryService.ConnectorDescriptor connector
  ) {
    List<OperationDefinition> definitions = new List<OperationDefinition>();
    for (
      ConnectorRegistryService.ObjectMapDescriptor mapping : connector.objectMappings ==
        null
        ? new List<ConnectorRegistryService.ObjectMapDescriptor>()
        : connector.objectMappings
    ) {
      String mappingDirection = normalizeDefinitionDirection(mapping.direction);
      if (
        String.isNotBlank(mapping.operationKey) &&
        !GENERIC_MAPPING_OPERATIONS.contains(normalize(mapping.operationKey))
      ) {
        definitions.add(
          definitionFor(
            connector.connectorKey,
            mapping.operationKey,
            mappingDirection,
            mapping.salesforceObject,
            mapping.externalObject
          )
        );
        continue;
      }
      for (
        String operationAlias : operationAliases(
          mapping.salesforceObject,
          mapping.externalObject
        )
      ) {
        definitions.add(
          definitionFor(
            connector.connectorKey,
            operationAlias,
            mappingDirection,
            mapping.salesforceObject,
            mapping.externalObject
          )
        );
      }
    }
    addCompatibilityDefinitions(definitions, connector.connectorKey);
    return definitions;
  }

  private static void addCompatibilityDefinitions(
    List<OperationDefinition> definitions,
    String connectorKey
  ) {
    String normalizedConnector = normalize(connectorKey);
    if (normalizedConnector == 'klaviyo') {
      definitions.add(
        klaviyoInboundDefinition(
          connectorKey,
          'ProfileSync',
          'Account',
          'Profile',
          '/api/profiles'
        )
      );
      definitions.add(
        klaviyoInboundDefinition(
          connectorKey,
          'Profiles',
          'Account',
          'Profile',
          '/api/profiles'
        )
      );
      definitions.add(
        klaviyoInboundDefinition(
          connectorKey,
          'ListSync',
          'Campaign',
          'List',
          '/api/lists'
        )
      );
      definitions.add(
        klaviyoInboundDefinition(
          connectorKey,
          'Lists',
          'Campaign',
          'List',
          '/api/lists'
        )
      );
      definitions.add(
        klaviyoInboundDefinition(
          connectorKey,
          'EventSync',
          'Event',
          'Event',
          '/api/events'
        )
      );
      definitions.add(
        klaviyoInboundDefinition(
          connectorKey,
          'Events',
          'Event',
          'Event',
          '/api/events'
        )
      );
      definitions.add(
        definitionFor(
          connectorKey,
          'CampaignMemberSync',
          'Inbound',
          'CampaignMember',
          'CampaignMember'
        )
      );
      definitions.add(
        klaviyoInboundDefinition(
          connectorKey,
          'CampaignMemberSync',
          'Campaign',
          'CampaignMember',
          '/api/lists'
        )
      );
    } else if (normalizedConnector == 'shopify') {
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Customer',
          'Inbound',
          'Account',
          'Customer',
          'ConnectorInboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Customers',
          'Inbound',
          'Account',
          'Customer',
          'ConnectorInboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Customer',
          'Outbound',
          'Account',
          'Customer',
          'ConnectorOutboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Customers',
          'Outbound',
          'Account',
          'Customer',
          'ConnectorOutboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Product',
          'Inbound',
          'Product2',
          'Product',
          'ConnectorInboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Products',
          'Inbound',
          'Product2',
          'Product',
          'ConnectorInboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Product',
          'Outbound',
          'Product2',
          'Product',
          'ConnectorOutboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Products',
          'Outbound',
          'Product2',
          'Product',
          'ConnectorOutboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Order',
          'Inbound',
          'Order',
          'Order',
          'ConnectorInboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Orders',
          'Inbound',
          'Order',
          'Order',
          'ConnectorInboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Order',
          'Outbound',
          'Order',
          'Order',
          'ConnectorOutboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Orders',
          'Outbound',
          'Order',
          'Order',
          'ConnectorOutboundOperationExecutor'
        )
      );
    } else if (normalizedConnector == 'qbo') {
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Quote',
          'Outbound',
          'Quote',
          'Estimate',
          'ConnectorOutboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'PurchaseOrder',
          'Outbound',
          'Purchase_Order__c',
          'PurchaseOrder',
          'ConnectorOutboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Order',
          'Outbound',
          'Order',
          'Invoice',
          'ConnectorOutboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Vendor',
          'Inbound',
          'Account',
          'Vendor',
          'ConnectorInboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Vendor',
          'Outbound',
          'Account',
          'Vendor',
          'ConnectorOutboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Customer',
          'Inbound',
          'Account',
          'Customer',
          'ConnectorInboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Customer',
          'Outbound',
          'Account',
          'Customer',
          'ConnectorOutboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Item',
          'Inbound',
          'Product2',
          'Item',
          'ConnectorInboundOperationExecutor'
        )
      );
      definitions.add(
        compatibilityDefinition(
          connectorKey,
          'Item',
          'Outbound',
          'Product2',
          'Item',
          'ConnectorOutboundOperationExecutor'
        )
      );
    }
  }

  private static OperationDefinition compatibilityDefinition(
    String connectorKey,
    String operationKey,
    String direction,
    String salesforceObject,
    String externalEntity,
    String executorClassName
  ) {
    OperationDefinition definition = definitionFor(
      connectorKey,
      operationKey,
      direction,
      salesforceObject,
      externalEntity
    );
    definition.executorClassName = executorClassName;
    if (normalize(connectorKey) == 'shopify') {
      String normalizedEntity = normalize(externalEntity);
      String entityPath = normalizedEntity == 'customer'
        ? 'customers.json'
        : (normalizedEntity == 'order' ? 'orders.json' : 'products.json');
      definition.namedCredential = 'Shopify_API';
      definition.relativeEndpoint = '/admin/api/2024-04/' + entityPath;
      definition.approvedBaseUrl =
        approvedShopifyStoreUrl() + definition.relativeEndpoint;
    }
    return definition;
  }

  private static String approvedShopifyStoreUrl() {
    if (String.isBlank(shopifyApprovedStoreUrl)) {
      ShopifyConfigService.Config config = ShopifyConfigService.getConfig();
      if (
        config == null ||
        config.isActive != true ||
        String.isBlank(config.storeUrl) ||
        !config.storeUrl.toLowerCase().startsWith('https://')
      ) {
        throw new ConnectorOperationRegistryException(
          'Shopify requires an active HTTPS store URL.'
        );
      }
      shopifyApprovedStoreUrl = config.storeUrl;
      while (shopifyApprovedStoreUrl.endsWith('/')) {
        shopifyApprovedStoreUrl = shopifyApprovedStoreUrl.substring(
          0,
          shopifyApprovedStoreUrl.length() - 1
        );
      }
    }
    return shopifyApprovedStoreUrl;
  }

  private static OperationDefinition klaviyoInboundDefinition(
    String connectorKey,
    String operationKey,
    String salesforceObject,
    String externalEntity,
    String relativeEndpoint
  ) {
    OperationDefinition definition = compatibilityDefinition(
      connectorKey,
      operationKey,
      ConnectorExecutionRequest.DIRECTION_INBOUND,
      salesforceObject,
      externalEntity,
      'ConnectorInboundOperationExecutor'
    );
    definition.namedCredential = KlaviyoAuthService.NAMED_CREDENTIAL;
    definition.relativeEndpoint = relativeEndpoint;
    definition.approvedBaseUrl = 'https://a.klaviyo.com' + relativeEndpoint;
    definition.maximumPages = ConnectorHttpClient.DEFAULT_MAX_PAGES;
    return definition;
  }

  private static List<String> operationAliases(
    String salesforceObject,
    String externalEntity
  ) {
    Set<String> entities = new Set<String>();
    entities.add(cleanEntityName(salesforceObject));
    entities.add(cleanEntityName(externalEntity));
    List<String> aliases = new List<String>();
    for (String entity : entities) {
      if (String.isBlank(entity)) {
        continue;
      }
      aliases.add(entity);
      aliases.add(entity + 'Sync');
      aliases.add(entity + 'Import');
      aliases.add(entity + 'Export');
      aliases.add(entity + 'Upsert');
    }
    return aliases;
  }

  private static OperationDefinition definitionFor(
    String connectorKey,
    String operationKey,
    String direction,
    String salesforceObject,
    String externalEntity
  ) {
    OperationDefinition definition = new OperationDefinition();
    definition.connectorKey = connectorKey;
    definition.operationKey = operationKey;
    definition.direction = direction;
    definition.salesforceObject = salesforceObject;
    definition.externalEntity = externalEntity;
    return definition;
  }

  private static Boolean matches(
    OperationDefinition definition,
    String requestedOperation,
    String requestedDirection,
    String requestedObject,
    String requestedEntity
  ) {
    return singularize(normalize(definition.operationKey)) ==
      singularize(normalize(requestedOperation)) &&
      directionAllows(definition.direction, requestedDirection) &&
      equivalentObject(definition.salesforceObject, requestedObject) &&
      equivalentEntity(definition.externalEntity, requestedEntity);
  }

  private static Boolean directionAllows(
    String definitionDirection,
    String requestedDirection
  ) {
    String normalizedDefinition = normalize(definitionDirection);
    return BOTH_DIRECTIONS.contains(normalizedDefinition) ||
      normalizeDirection(definitionDirection) == requestedDirection;
  }

  private static String normalizeDefinitionDirection(String direction) {
    String normalized = normalize(direction);
    if (BOTH_DIRECTIONS.contains(normalized)) {
      return 'Bidirectional';
    }
    return normalizeDirection(direction);
  }

  private static String canonicalObjectName(String objectName) {
    if (
      String.isBlank(objectName) ||
      !Pattern.matches('^[A-Za-z][A-Za-z0-9_]{0,79}$', objectName)
    ) {
      throw new ConnectorOperationRegistryException(
        'A valid Salesforce object API name is required.'
      );
    }
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    if (globalDescribe.containsKey(objectName)) {
      return globalDescribe.get(objectName).getDescribe().getName();
    }
    String equivalentCandidate = uniqueEquivalentObjectName(
      objectName,
      globalDescribe.keySet()
    );
    if (equivalentCandidate != null) {
      return globalDescribe.get(equivalentCandidate).getDescribe().getName();
    }
    throw new ConnectorOperationRegistryException(
      'The requested Salesforce object is unavailable.'
    );
  }

  @TestVisible
  private static String uniqueEquivalentObjectName(
    String requestedObject,
    Set<String> candidates
  ) {
    String resolvedCandidate;
    Set<String> safeCandidates = candidates == null
      ? new Set<String>()
      : candidates;
    for (String candidate : safeCandidates) {
      if (!equivalentObject(candidate, requestedObject)) {
        continue;
      }
      if (resolvedCandidate != null && resolvedCandidate != candidate) {
        throw new ConnectorOperationRegistryException(
          'The requested Salesforce object is ambiguous across installed namespaces.'
        );
      }
      resolvedCandidate = candidate;
    }
    return resolvedCandidate;
  }

  private static String validateExternalEntity(String externalEntity) {
    if (
      String.isBlank(externalEntity) ||
      !Pattern.matches('^[A-Za-z][A-Za-z0-9 _.-]{0,79}$', externalEntity)
    ) {
      throw new ConnectorOperationRegistryException(
        'A valid external entity is required.'
      );
    }
    return externalEntity.trim();
  }

  @TestVisible
  private static Boolean equivalentObject(String leftValue, String rightValue) {
    String leftNormalized = normalize(leftValue);
    String rightNormalized = normalize(rightValue);
    if (leftNormalized == rightNormalized) {
      return true;
    }
    if (
      (!hasNamespace(leftValue) || !hasNamespace(rightValue)) &&
      normalize(cleanEntityName(leftValue)) ==
      normalize(cleanEntityName(rightValue))
    ) {
      return true;
    }
    return leftNormalized.endsWith(rightNormalized) &&
      leftValue != null &&
      hasNamespace(leftValue) &&
      !hasNamespace(rightValue);
  }

  private static Boolean hasNamespace(String objectName) {
    if (String.isBlank(objectName)) {
      return false;
    }
    String withoutCustomSuffix = objectName.endsWith('__c')
      ? objectName.substring(0, objectName.length() - 3)
      : objectName;
    return withoutCustomSuffix.contains('__');
  }

  private static Boolean equivalentEntity(String leftValue, String rightValue) {
    return singularize(normalize(leftValue)) ==
      singularize(normalize(rightValue));
  }

  private static String cleanEntityName(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    String withoutCustomSuffix = value.endsWith('__c')
      ? value.substring(0, value.length() - 3)
      : value;
    Integer namespaceSeparator = withoutCustomSuffix.lastIndexOf('__');
    return namespaceSeparator >= 0
      ? withoutCustomSuffix.substring(namespaceSeparator + 2)
      : withoutCustomSuffix;
  }

  private static String singularize(String value) {
    if (String.isBlank(value)) {
      return '';
    }
    if (value.endsWith('ies') && value.length() > 3) {
      return value.substring(0, value.length() - 3) + 'y';
    }
    if (value.endsWith('s') && !value.endsWith('ss') && value.length() > 1) {
      return value.substring(0, value.length() - 1);
    }
    return value;
  }

  private static String operationIdentity(
    String connectorKey,
    String operationKey,
    String direction,
    String salesforceObject,
    String externalEntity
  ) {
    return String.join(
      new List<String>{
        normalize(connectorKey),
        normalize(operationKey),
        normalize(direction),
        normalize(salesforceObject),
        singularize(normalize(externalEntity))
      },
      ':'
    );
  }

  private static void validateDefinition(OperationDefinition definition) {
    if (definition == null) {
      throw new ConnectorOperationRegistryException(
        'Operation definition is required.'
      );
    }
    assertSafeToken(definition.connectorKey, 'Connector key');
    assertSafeToken(definition.operationKey, 'Operation key');
    normalizeDefinitionDirection(definition.direction);
    canonicalObjectName(definition.salesforceObject);
    validateExternalEntity(definition.externalEntity);
    if (
      definition.maximumPages == null ||
      definition.maximumPages < 1 ||
      definition.maximumPages > ConnectorHttpClient.ABSOLUTE_MAX_PAGES
    ) {
      throw new ConnectorOperationRegistryException(
        'Maximum pages is outside the supported range.'
      );
    }
  }

  private static void assertSafeToken(String value, String label) {
    if (
      String.isBlank(value) ||
      !Pattern.matches('^[A-Za-z][A-Za-z0-9_. -]{0,79}$', value)
    ) {
      throw new ConnectorOperationRegistryException(label + ' is invalid.');
    }
  }

  private static String normalize(String value) {
    return String.isBlank(value)
      ? ''
      : value.toLowerCase().replaceAll('[^a-z0-9]', '');
  }

  private static OperationDefinition copyDefinition(
    OperationDefinition source
  ) {
    OperationDefinition copyValue = new OperationDefinition();
    copyValue.connectorKey = source.connectorKey;
    copyValue.operationKey = source.operationKey;
    copyValue.direction = source.direction;
    copyValue.salesforceObject = source.salesforceObject;
    copyValue.externalEntity = source.externalEntity;
    copyValue.namedCredential = source.namedCredential;
    copyValue.relativeEndpoint = source.relativeEndpoint;
    copyValue.approvedBaseUrl = source.approvedBaseUrl;
    copyValue.maximumPages = source.maximumPages;
    copyValue.executorClassName = source.executorClassName;
    return copyValue;
  }

  public class ConnectorOperationRegistryException extends Exception {
  }
}
