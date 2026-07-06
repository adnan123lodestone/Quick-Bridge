public with sharing class ConnectorOperationalControlService {
  private static final Set<String> SUPPORTED_CONNECTORS = new Set<String>{ 'netsuite', 'meta' };

  public class ReadinessReport {
    @AuraEnabled public String connectorKey { get; set; }
    @AuraEnabled public String label { get; set; }
    @AuraEnabled public String status { get; set; }
    @AuraEnabled public Integer readyCount { get; set; }
    @AuraEnabled public Integer warningCount { get; set; }
    @AuraEnabled public Integer blockedCount { get; set; }
    @AuraEnabled public List<ReadinessCheck> checks { get; set; }
    @AuraEnabled public List<OperationRunSummary> operationSummaries { get; set; }

    public ReadinessReport() {
      readyCount = 0;
      warningCount = 0;
      blockedCount = 0;
      checks = new List<ReadinessCheck>();
      operationSummaries = new List<OperationRunSummary>();
    }
  }

  public class ReadinessCheck {
    @AuraEnabled public String label { get; set; }
    @AuraEnabled public String status { get; set; }
    @AuraEnabled public String message { get; set; }
    @AuraEnabled public String remediation { get; set; }
  }

  public class OperationRunSummary {
    @AuraEnabled public String operationKey { get; set; }
    @AuraEnabled public Datetime lastRunAt { get; set; }
    @AuraEnabled public Integer pendingCount { get; set; }
    @AuraEnabled public Integer retryCount { get; set; }
    @AuraEnabled public Integer completedCount { get; set; }
    @AuraEnabled public Integer failedCount { get; set; }
    @AuraEnabled public Integer skippedCount { get; set; }

    public OperationRunSummary() {
      pendingCount = 0;
      retryCount = 0;
      completedCount = 0;
      failedCount = 0;
      skippedCount = 0;
    }
  }

  public class MappingPreset {
    @AuraEnabled public String connectorKey { get; set; }
    @AuraEnabled public String salesforceObject { get; set; }
    @AuraEnabled public String externalObject { get; set; }
    @AuraEnabled public String salesforceField { get; set; }
    @AuraEnabled public String externalField { get; set; }
    @AuraEnabled public String syncDirection { get; set; }
    @AuraEnabled public Boolean required { get; set; }
    @AuraEnabled public String guidance { get; set; }
  }

  public class ManualRunResponse {
    @AuraEnabled public Boolean success { get; set; }
    @AuraEnabled public String message { get; set; }
    @AuraEnabled public Id workItemId { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static ReadinessReport getReadiness(String connectorKey) {
    QuickBridgeAdminGuard.requireView();
    ConnectorRegistryService.ConnectorDescriptor descriptor = requireSupportedConnector(connectorKey);
    ReadinessReport report = new ReadinessReport();
    report.connectorKey = descriptor.connectorKey;
    report.label = descriptor.label;

    addCatalogChecks(report, descriptor);
    addConfigChecks(report, descriptor);
    addMappingChecks(report, descriptor);
    addSchedulerChecks(report, descriptor);
    report.operationSummaries = loadOperationSummaries(descriptor);
    calculateStatus(report);
    return report;
  }

  @AuraEnabled(cacheable=true)
  public static List<MappingPreset> getMappingPresets(String connectorKey) {
    QuickBridgeAdminGuard.requireView();
    ConnectorRegistryService.ConnectorDescriptor descriptor = requireSupportedConnector(connectorKey);
    String normalized = normalize(descriptor.connectorKey);
    if (normalized == 'netsuite') {
      return netSuitePresets();
    }
    if (normalized == 'meta') {
      return metaPresets();
    }
    return new List<MappingPreset>();
  }

  @AuraEnabled
  public static ManualRunResponse enqueueManualRun(
    String connectorKey,
    String operationKey,
    String direction,
    String sourceObject,
    String sourceRecordId,
    String payloadJson
  ) {
    QuickBridgeAdminGuard.requireRunSync();
    ConnectorRegistryService.ConnectorDescriptor descriptor = requireSupportedConnector(connectorKey);
    String normalizedOperation = normalizeOperation(operationKey);
    String canonicalOperation = canonicalOperation(descriptor, normalizedOperation);
    if (String.isBlank(canonicalOperation)) {
      throw new AuraHandledException('Unsupported ' + descriptor.label + ' operation: ' + operationKey);
    }
    if (isExplicitlyDisabled(descriptor.connectorKey, canonicalOperation)) {
      throw new AuraHandledException(descriptor.label + ' ' + canonicalOperation + ' is disabled in connector setup.');
    }

    String runDirection = String.isBlank(direction) ? 'Manual' : direction.trim();
    String runSourceObject = String.isBlank(sourceObject) ? 'ManualRun' : sourceObject.trim();
    String runSourceRecordId = String.isBlank(sourceRecordId)
      ? descriptor.connectorKey + ':' + canonicalOperation + ':' + runDirection
      : sourceRecordId.trim();

    Map<String, Object> payload = parsePayload(payloadJson);
    payload.put('manual', true);
    payload.put('direction', runDirection);
    payload.put('requestedAt', System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
    payload.put('connectorKey', descriptor.connectorKey);
    payload.put('operation', canonicalOperation);

    IntegrationWorkRequest request = new IntegrationWorkRequest();
    request.integration = String.isBlank(descriptor.integrationType) ? descriptor.label : descriptor.integrationType;
    request.operation = canonicalOperation;
    request.sourceObject = runSourceObject;
    request.sourceRecordId = runSourceRecordId;
    request.lockKey = descriptor.connectorKey + ':' + canonicalOperation + ':' + runDirection;
    request.payloadJson = JSON.serialize(payload);

    Id workItemId = IntegrationWorkService.enqueue(request);
    QuickBridgeAdminGuard.audit(
      'MANUAL_SYNC_ENQUEUE',
      descriptor.connectorKey,
      'Success',
      canonicalOperation + ' ' + runDirection,
      workItemId
    );

    ManualRunResponse response = new ManualRunResponse();
    response.success = true;
    response.workItemId = workItemId;
    response.message = descriptor.label + ' ' + canonicalOperation + ' queued.';
    return response;
  }

  private static void addCatalogChecks(
    ReadinessReport report,
    ConnectorRegistryService.ConnectorDescriptor descriptor
  ) {
    addCheck(
      report,
      'Connector Catalog',
      descriptor.enabled == true && descriptor.catalogActive == true ? 'Ready' : 'Blocked',
      descriptor.label + ' is registered in the connector catalog.',
      'Enable the connector metadata and product catalog row.'
    );
    addCheck(
      report,
      'Work Routing',
      workOperations(descriptor).isEmpty() ? 'Blocked' : 'Ready',
      workOperations(descriptor).size() + ' work operation(s) are registered.',
      'Register work.* capabilities with allowlisted adapter classes.'
    );
  }

  private static void addConfigChecks(
    ReadinessReport report,
    ConnectorRegistryService.ConnectorDescriptor descriptor
  ) {
    ConnectorConfigService.ConnectorConfig config;
    try {
      config = ConnectorConfigService.getConfig(descriptor.connectorKey);
    } catch (Exception e) {
      addCheck(report, 'Configuration', 'Blocked', e.getMessage(), 'Create the connector instance and config values.');
      return;
    }

    List<String> missingRequired = new List<String>();
    for (ConnectorRegistryService.ConfigFieldDescriptor field : descriptor.configFields) {
      if (field.required == true && field.secret != true) {
        String value = config.values == null ? null : config.values.get(field.fieldKey);
        if (String.isBlank(value)) {
          missingRequired.add(field.label);
        }
      }
    }
    if (!missingRequired.isEmpty()) {
      addCheck(
        report,
        'Required Setup Values',
        'Blocked',
        'Missing required non-secret setup values: ' + String.join(missingRequired, ', '),
        'Populate these values in the connector setup panel.'
      );
    } else {
      addCheck(report, 'Required Setup Values', 'Ready', 'Required non-secret setup values are present or optional.', null);
    }

    List<String> disabledToggles = disabledToggles(descriptor.connectorKey, config.values);
    addCheck(
      report,
      'Object Enablement',
      disabledToggles.isEmpty() ? 'Ready' : 'Warning',
      disabledToggles.isEmpty()
        ? 'No object-level sync toggles are explicitly disabled.'
        : 'Disabled sync toggles: ' + String.join(disabledToggles, ', '),
      'Enable only the objects that should run in this sandbox or production org.'
    );
  }

  private static void addMappingChecks(
    ReadinessReport report,
    ConnectorRegistryService.ConnectorDescriptor descriptor
  ) {
    Integer objectMapCount = descriptor.objectMappings == null ? 0 : descriptor.objectMappings.size();
    addCheck(
      report,
      'Object Maps',
      objectMapCount > 0 ? 'Ready' : 'Blocked',
      objectMapCount + ' object map(s) are active.',
      'Activate Integration_Object_Map__mdt rows for this connector.'
    );

    Integer activeMappingCount = activeFieldMappingCount(descriptor);
    addCheck(
      report,
      'Field Mappings',
      activeMappingCount > 0 ? 'Ready' : 'Warning',
      activeMappingCount > 0
        ? activeMappingCount + ' active field mapping(s) are available.'
        : 'No active saved field mappings were found. Runtime fallback mappings may still apply for foundation flows.',
      'Review recommended presets and save customer-specific mappings before live sync.'
    );
  }

  private static void addSchedulerChecks(
    ReadinessReport report,
    ConnectorRegistryService.ConnectorDescriptor descriptor
  ) {
    Boolean hasScheduler = hasCapability(descriptor, 'scheduler.operation');
    Integer scheduledJobs = scheduledJobCount(descriptor);
    addCheck(
      report,
      'Scheduler',
      hasScheduler ? (scheduledJobs > 0 ? 'Ready' : 'Warning') : 'Blocked',
      hasScheduler
        ? scheduledJobs + ' scheduled job row(s) exist for this connector.'
        : 'No scheduler capability is registered.',
      'Use the scheduler panel to create or review scheduled jobs.'
    );
  }

  private static List<OperationRunSummary> loadOperationSummaries(
    ConnectorRegistryService.ConnectorDescriptor descriptor
  ) {
    Map<String, OperationRunSummary> byOperation = new Map<String, OperationRunSummary>();
    for (String operation : workOperations(descriptor)) {
      OperationRunSummary summary = new OperationRunSummary();
      summary.operationKey = operation;
      byOperation.put(operation, summary);
    }

    Set<String> integrationNames = integrationNames(descriptor);
    for (AggregateResult row : [
      SELECT Operation__c operationKey, Status__c statusValue, COUNT(Id) recordCount, MAX(LastModifiedDate) lastRunAt
      FROM Integration_Work_Item__c
      WHERE Integration__c IN :integrationNames
      GROUP BY Operation__c, Status__c
      LIMIT 200
    ]) {
      String operation = String.valueOf(row.get('operationKey'));
      if (String.isBlank(operation)) {
        continue;
      }
      OperationRunSummary summary = byOperation.get(operation);
      if (summary == null) {
        summary = new OperationRunSummary();
        summary.operationKey = operation;
        byOperation.put(operation, summary);
      }
      Integer countValue = Integer.valueOf(row.get('recordCount'));
      String statusValue = String.valueOf(row.get('statusValue'));
      if (statusValue == IntegrationWorkService.STATUS_PENDING) summary.pendingCount += countValue;
      else if (statusValue == IntegrationWorkService.STATUS_RETRY) summary.retryCount += countValue;
      else if (statusValue == IntegrationWorkService.STATUS_COMPLETED) summary.completedCount += countValue;
      else if (statusValue == IntegrationWorkService.STATUS_FAILED) summary.failedCount += countValue;
      else if (statusValue == IntegrationWorkService.STATUS_CANCELLED) summary.skippedCount += countValue;
      Datetime lastRunAt = (Datetime) row.get('lastRunAt');
      if (summary.lastRunAt == null || (lastRunAt != null && lastRunAt > summary.lastRunAt)) {
        summary.lastRunAt = lastRunAt;
      }
    }
    return byOperation.values();
  }

  private static ConnectorRegistryService.ConnectorDescriptor requireSupportedConnector(String connectorKey) {
    ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(connectorKey);
    if (descriptor == null || !SUPPORTED_CONNECTORS.contains(normalize(descriptor.connectorKey))) {
      throw new AuraHandledException('Unsupported operational connector: ' + connectorKey);
    }
    return descriptor;
  }

  private static String canonicalOperation(
    ConnectorRegistryService.ConnectorDescriptor descriptor,
    String normalizedOperation
  ) {
    for (String operation : workOperations(descriptor)) {
      if (normalizeOperation(operation) == normalizedOperation) {
        return operation;
      }
    }
    return null;
  }

  private static List<String> workOperations(ConnectorRegistryService.ConnectorDescriptor descriptor) {
    List<String> result = new List<String>();
    if (descriptor == null || descriptor.capabilities == null) {
      return result;
    }
    for (String capability : descriptor.capabilities) {
      if (String.isNotBlank(capability) && capability.startsWith('work.')) {
        result.add(capability.substringAfter('work.'));
      }
    }
    result.sort();
    return result;
  }

  private static Boolean hasCapability(ConnectorRegistryService.ConnectorDescriptor descriptor, String capabilityKey) {
    if (descriptor == null || descriptor.capabilities == null) {
      return false;
    }
    String target = normalizeOperation(capabilityKey);
    for (String capability : descriptor.capabilities) {
      if (normalizeOperation(capability) == target) {
        return true;
      }
    }
    return false;
  }

  private static Integer activeFieldMappingCount(ConnectorRegistryService.ConnectorDescriptor descriptor) {
    Set<String> integrationNames = integrationNames(descriptor);
    try {
      return [
        SELECT COUNT()
        FROM Field_Mapping__mdt
        WHERE Integration__c IN :integrationNames AND Is_Active__c = true
      ];
    } catch (Exception e) {
      return 0;
    }
  }

  private static Integer scheduledJobCount(ConnectorRegistryService.ConnectorDescriptor descriptor) {
    Set<String> integrationNames = integrationNames(descriptor);
    try {
      return [
        SELECT COUNT()
        FROM Scheduled_Integration_Job__c
        WHERE Integration_Type__c IN :integrationNames AND Status__c != 'Deleted'
      ];
    } catch (Exception e) {
      return 0;
    }
  }

  private static Set<String> integrationNames(ConnectorRegistryService.ConnectorDescriptor descriptor) {
    Set<String> names = new Set<String>();
    if (descriptor == null) {
      return names;
    }
    names.add(descriptor.connectorKey);
    names.add(descriptor.label);
    names.add(descriptor.productKey);
    names.add(descriptor.integrationType);
    names.remove(null);
    names.remove('');
    return names;
  }

  private static List<String> disabledToggles(String connectorKey, Map<String, String> values) {
    List<String> disabled = new List<String>();
    if (values == null) {
      return disabled;
    }
    for (String fieldKey : toggleFields(connectorKey)) {
      String value = values.get(fieldKey);
      if (String.isNotBlank(value) && !parseBoolean(value)) {
        disabled.add(fieldKey);
      }
    }
    return disabled;
  }

  private static Boolean isExplicitlyDisabled(String connectorKey, String operationKey) {
    String fieldKey = toggleFieldForOperation(connectorKey, operationKey);
    if (String.isBlank(fieldKey)) {
      return false;
    }
    String value = ConnectorConfigService.getConfigValue(connectorKey, fieldKey);
    return String.isNotBlank(value) && !parseBoolean(value);
  }

  private static List<String> toggleFields(String connectorKey) {
    String normalized = normalize(connectorKey);
    if (normalized == 'netsuite') {
      return new List<String>{
        'enableCustomerSync',
        'enableItemSync',
        'enableSalesOrderSync',
        'enableInvoiceSync',
        'enablePaymentSync',
        'enableFulfillmentSync'
      };
    }
    if (normalized == 'meta') {
      return new List<String>{
        'campaignSyncEnabled',
        'insightsSyncEnabled',
        'leadAdsEnabled',
        'commentAttributionEnabled'
      };
    }
    return new List<String>();
  }

  private static String toggleFieldForOperation(String connectorKey, String operationKey) {
    String normalizedConnector = normalize(connectorKey);
    String normalizedOperation = normalizeOperation(operationKey);
    if (normalizedConnector == 'netsuite') {
      if (normalizedOperation == 'customersync') return 'enableCustomerSync';
      if (normalizedOperation == 'itemsync') return 'enableItemSync';
      if (normalizedOperation == 'salesordersync') return 'enableSalesOrderSync';
      if (normalizedOperation == 'invoicesync') return 'enableInvoiceSync';
      if (normalizedOperation == 'paymentsync') return 'enablePaymentSync';
      if (normalizedOperation == 'fulfillmentsync') return 'enableFulfillmentSync';
    }
    if (normalizedConnector == 'meta') {
      if (normalizedOperation == 'campaignsync') return 'campaignSyncEnabled';
      if (normalizedOperation == 'insightssync') return 'insightsSyncEnabled';
      if (normalizedOperation == 'leadad') return 'leadAdsEnabled';
      if (normalizedOperation == 'commentattribution') return 'commentAttributionEnabled';
    }
    return null;
  }

  private static Map<String, Object> parsePayload(String payloadJson) {
    if (String.isBlank(payloadJson)) {
      return new Map<String, Object>();
    }
    try {
      Object parsed = JSON.deserializeUntyped(payloadJson);
      if (parsed instanceof Map<String, Object>) {
        return (Map<String, Object>) parsed;
      }
      return new Map<String, Object>{ 'rawPayload' => payloadJson };
    } catch (Exception e) {
      throw new AuraHandledException('Manual run payload must be valid JSON.');
    }
  }

  private static void addCheck(
    ReadinessReport report,
    String label,
    String status,
    String message,
    String remediation
  ) {
    ReadinessCheck check = new ReadinessCheck();
    check.label = label;
    check.status = status;
    check.message = message;
    check.remediation = remediation;
    report.checks.add(check);
    if (status == 'Ready') report.readyCount++;
    else if (status == 'Blocked') report.blockedCount++;
    else report.warningCount++;
  }

  private static void calculateStatus(ReadinessReport report) {
    if (report.blockedCount > 0) {
      report.status = 'Blocked';
    } else if (report.warningCount > 0) {
      report.status = 'Needs Attention';
    } else {
      report.status = 'Ready';
    }
  }

  private static Boolean parseBoolean(String value) {
    return String.isNotBlank(value) &&
      (value.equalsIgnoreCase('true') || value.equalsIgnoreCase('yes') || value == '1');
  }

  private static String normalize(String value) {
    return ConnectorRegistryService.normalize(value);
  }

  private static String normalizeOperation(String value) {
    return String.isBlank(value) ? '' : value.toLowerCase().replaceAll('[^a-z0-9]', '');
  }

  private static List<MappingPreset> netSuitePresets() {
    List<MappingPreset> presets = new List<MappingPreset>();
    addPreset(presets, 'netsuite', 'Account', 'Customer', 'External_Id__c', 'id', 'NetSuite to SF', true, 'Store NetSuite Customer IDs as netsuite:<id> for idempotent matching.');
    addPreset(presets, 'netsuite', 'Account', 'Customer', 'Name', 'companyname', 'Two-Way', true, 'Customer display name is required for most NetSuite customer records.');
    addPreset(presets, 'netsuite', 'Contact', 'Customer', 'Email', 'email', 'Two-Way', false, 'Contact email supports duplicate detection and customer matching.');
    addPreset(presets, 'netsuite', 'Product2', 'Item', 'External_Id__c', 'id', 'NetSuite to SF', true, 'Store NetSuite Item IDs as netsuite:<id>.');
    addPreset(presets, 'netsuite', 'Product2', 'Item', 'ProductCode', 'itemid', 'Two-Way', true, 'Use Product Code/SKU for item matching.');
    addPreset(presets, 'netsuite', 'Order', 'SalesOrder', 'External_Id__c', 'id', 'NetSuite to SF', true, 'Store NetSuite Sales Order IDs as netsuite:<id>.');
    addPreset(presets, 'netsuite', 'Order', 'SalesOrder', 'AccountId', 'entity', 'Two-Way', true, 'Sales order sync requires a resolved NetSuite customer dependency.');
    addPreset(presets, 'netsuite', 'OrderItem', 'SalesOrderLine', 'Product2Id', 'item', 'Two-Way', true, 'Line sync requires a resolved NetSuite item dependency.');
    addPreset(presets, 'netsuite', 'Invoice__c', 'Invoice', 'External_Id__c', 'id', 'NetSuite to SF', true, 'Invoice external IDs must remain stable for retries.');
    addPreset(presets, 'netsuite', 'Invoice__c', 'Invoice', 'Related_Account__c', 'entity', 'Two-Way', true, 'Invoice sync requires a resolved NetSuite customer dependency.');
    addPreset(presets, 'netsuite', 'Invoice_Line__c', 'InvoiceLine', 'Product__c', 'item', 'Two-Way', true, 'Invoice lines require a resolvable NetSuite item.');
    addPreset(presets, 'netsuite', 'Portal_Payment_Transaction__c', 'Payment', 'Gateway_Event_Id__c', 'id', 'NetSuite to SF', true, 'Use the gateway event id to store the NetSuite payment identifier.');
    addPreset(presets, 'netsuite', 'Portal_Payment_Transaction__c', 'Payment', 'Gateway_Amount__c', 'payment', 'Two-Way', true, 'Payment amount is required for customer payment records.');
    addPreset(presets, 'netsuite', 'Carrier_Shipment__c', 'Fulfillment', 'External_Shipment_Id__c', 'id', 'NetSuite to SF', true, 'Store NetSuite item fulfillment IDs on the shipment.');
    addPreset(presets, 'netsuite', 'Carrier_Shipment__c', 'Fulfillment', 'Master_Tracking_Number__c', 'trackingnumbers', 'Two-Way', false, 'Tracking values should remain visible in carrier shipment records.');
    return presets;
  }

  private static List<MappingPreset> metaPresets() {
    List<MappingPreset> presets = new List<MappingPreset>();
    addPreset(presets, 'meta', 'Campaign', 'Campaign', 'Meta_Campaign_Id__c', 'id', 'Two-Way', true, 'Campaign hierarchy sync should key Campaign records by Meta campaign id.');
    addPreset(presets, 'meta', 'Campaign', 'Campaign', 'Name', 'name', 'Meta to SF', true, 'Campaign names should mirror Meta for admin reconciliation.');
    addPreset(presets, 'meta', 'Campaign', 'Campaign', 'Meta_Status__c', 'status', 'Meta to SF', false, 'Status supports deleted/inactive campaign diagnostics.');
    addPreset(presets, 'meta', 'Meta_Ad_Set__c', 'AdSet', 'Meta_Ad_Set_Id__c', 'id', 'Meta to SF', true, 'Ad Sets should key by Meta ad set id.');
    addPreset(presets, 'meta', 'Meta_Ad_Set__c', 'AdSet', 'Meta_Campaign_Id__c', 'campaign_id', 'Meta to SF', true, 'Ad Set sync requires campaign parent resolution.');
    addPreset(presets, 'meta', 'Meta_Ad__c', 'Ad', 'Meta_Ad_Id__c', 'id', 'Meta to SF', true, 'Ads should key by Meta ad id.');
    addPreset(presets, 'meta', 'Meta_Ad__c', 'Ad', 'Meta_Ad_Set_Id__c', 'adset_id', 'Meta to SF', true, 'Ad sync requires ad set parent resolution.');
    addPreset(presets, 'meta', 'Lead', 'LeadAd', 'Meta_Leadgen_Id__c', 'id', 'Meta to SF', true, 'Lead events must be idempotent on Meta leadgen id.');
    addPreset(presets, 'meta', 'Lead', 'LeadAd', 'Email', 'email', 'Meta to SF', false, 'Email supports lead matching and duplicate detection.');
    addPreset(presets, 'meta', 'Lead', 'LeadAd', 'Primary_Campaign__c', 'campaign_id', 'Meta to SF', false, 'Primary campaign should resolve from synced Meta campaign ids.');
    addPreset(presets, 'meta', 'CampaignMember', 'CampaignMemberAttribution', 'Status', 'status', 'Meta to SF', false, 'CampaignMember status should use the configured default or mapped value.');
    addPreset(presets, 'meta', 'Social_Interaction__c', 'CommentAttribution', 'Meta_Comment_Id__c', 'comment_id', 'Meta to SF', true, 'Comment attribution should be idempotent on the Meta comment id.');
    return presets;
  }

  private static void addPreset(
    List<MappingPreset> presets,
    String connectorKey,
    String salesforceObject,
    String externalObject,
    String salesforceField,
    String externalField,
    String syncDirection,
    Boolean required,
    String guidance
  ) {
    MappingPreset preset = new MappingPreset();
    preset.connectorKey = connectorKey;
    preset.salesforceObject = salesforceObject;
    preset.externalObject = externalObject;
    preset.salesforceField = salesforceField;
    preset.externalField = externalField;
    preset.syncDirection = syncDirection;
    preset.required = required == true;
    preset.guidance = guidance;
    presets.add(preset);
  }
}
