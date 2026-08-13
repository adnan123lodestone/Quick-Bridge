public with sharing class GenericSchedulerController {
  private static final Set<String> LIVE_STATUSES = new Set<String>{
    'Active',
    'Ready',
    'Claimed',
    'Running'
  };

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getScheduledJobs(
    String connectorKey
  ) {
    QuickBridgeAdminGuard.requireView();
    String integrationType = connectorKeyToIntegrationType(connectorKey);
    List<Map<String, Object>> jobList = new List<Map<String, Object>>();
    for (Scheduled_Integration_Job__c job : [
      SELECT
        Id,
        Logical_Job_Key__c,
        Scheduler_Name__c,
        Source_Object__c,
        Status__c,
        Next_Run_At__c,
        Last_Run_At__c,
        Created_DateTime__c,
        Created_By_User__r.Name,
        Frequency_Value__c,
        Frequency_Type__c
      FROM Scheduled_Integration_Job__c
      WHERE
        Integration_Type__c = :integrationType
        AND Status__c IN :LIVE_STATUSES
      ORDER BY Created_DateTime__c DESC
      LIMIT 50
    ]) {
      jobList.add(toUiMap(job));
    }
    return jobList;
  }

  @AuraEnabled(cacheable=true)
  public static Map<String, String> getSyncSettingsSummary(String connectorKey) {
    QuickBridgeAdminGuard.requireView();
    Map<String, String> summary = new Map<String, String>();
    ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(
      connectorKey
    );
    String label = descriptor == null || String.isBlank(descriptor.label)
      ? connectorKey
      : descriptor.label;

    try {
      Set<String> mappingKeys = mappingIntegrationKeys(descriptor, connectorKey);
      List<Field_Mapping__mdt> mappings = [
        SELECT SF_Object__c
        FROM Field_Mapping__mdt
        WHERE Integration__c IN :mappingKeys AND Is_Active__c = true
      ];

      Set<String> uniqueObjects = new Set<String>();
      for (Field_Mapping__mdt mapping : mappings) {
        if (String.isNotBlank(mapping.SF_Object__c)) {
          uniqueObjects.add(mapping.SF_Object__c);
        }
      }

      List<String> objectNames = new List<String>(uniqueObjects);
      objectNames.sort();
      summary.put(
        'objects',
        objectNames.isEmpty() ? 'No objects mapped' : String.join(objectNames, ', ')
      );
      summary.put('direction', 'Salesforce <-> ' + label);
      summary.put('type', 'Incremental Sync');
    } catch (Exception e) {
      ErrorLogUtility.logException(
        label,
        'GenericSchedulerController.getSyncSettingsSummary',
        e,
        null,
        null
      );
      summary.put('objects', 'Error loading objects');
      summary.put('direction', 'Salesforce <-> ' + label);
      summary.put('type', 'Incremental Sync');
    }

    return summary;
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getRecentRuns(String jobId) {
    QuickBridgeAdminGuard.requireView();
    List<Map<String, Object>> runList = new List<Map<String, Object>>();
    if (String.isBlank(jobId)) {
      return runList;
    }

    for (AsyncApexJob job : [
      SELECT Id, CompletedDate, Status, TotalJobItems, NumberOfErrors
      FROM AsyncApexJob
      WHERE
        JobType = 'BatchApex'
        AND CronTriggerId = :jobId
        AND CompletedDate != null
      ORDER BY CompletedDate DESC
      LIMIT 5
    ]) {
      Map<String, Object> runMap = new Map<String, Object>();
      runMap.put('id', job.Id);
      runMap.put('date', job.CompletedDate.format());
      runMap.put('status', job.Status == 'Completed' ? 'Success' : job.Status);
      runMap.put('processed', job.TotalJobItems);
      runMap.put('failed', job.NumberOfErrors);
      runMap.put(
        'icon',
        job.NumberOfErrors > 0 ? 'utility:warning' : 'utility:success'
      );
      runMap.put('variant', job.NumberOfErrors > 0 ? 'warning' : 'success');
      runList.add(runMap);
    }
    return runList;
  }

  @AuraEnabled
  public static String scheduleJob(
    String connectorKey,
    String freqValue,
    String freqType,
    String selectedObject,
    String direction
  ) {
    QuickBridgeAdminGuard.requireRunSync();
    validateScheduleConfiguration(connectorKey);
    Integer safeValue = Integer.valueOf(freqValue.trim());
    String integrationType = connectorKeyToIntegrationType(connectorKey);
    String selectedObjectSafe = String.isBlank(selectedObject)
      ? 'Account'
      : selectedObject;
    String logicalJobName = buildLogicalJobName(
      integrationType,
      selectedObjectSafe,
      direction
    );

    SchedulerEntitlementService.recordScheduleCreated(
      integrationType,
      selectedObjectSafe,
      String.valueOf(safeValue),
      freqType,
      logicalJobName,
      new List<Id>()
    );
    ScheduledIntegrationHeartbeat.ensureScheduled();

    Scheduled_Integration_Job__c trackedJob = [
      SELECT Id, Direction__c
      FROM Scheduled_Integration_Job__c
      WHERE
        Logical_Job_Key__c = :SchedulerEntitlementService.normalizeLogicalJobName(
          logicalJobName
        )
      LIMIT 1
    ];
    if (String.isNotBlank(direction)) {
      trackedJob.Direction__c = direction;
      update trackedJob;
    }
    QuickBridgeAdminGuard.audit(
      'SCHEDULE_CREATE',
      connectorKey,
      'Success',
      logicalJobName,
      trackedJob.Id
    );
    return (String) trackedJob.Id;
  }

  @AuraEnabled
  public static void deleteJob(String jobName) {
    QuickBridgeAdminGuard.requireRunSync();
    SchedulerEntitlementService.markScheduleDeleted(jobName);
    markLogicalSchedulesDeletedByPrefix(jobName);
    QuickBridgeAdminGuard.audit(
      'SCHEDULE_DELETE',
      null,
      'Success',
      jobName,
      null
    );
  }

  @AuraEnabled
  public static String editJob(
    String connectorKey,
    String jobName,
    String freqValue,
    String freqType
  ) {
    QuickBridgeAdminGuard.requireRunSync();
    deleteJob(jobName);
    ParsedJobName parsed = parseJobName(jobName, connectorKey);
    String idValue = scheduleJob(
      connectorKey,
      freqValue,
      freqType,
      parsed.sourceObject,
      parsed.direction
    );
    return 'Success: Job updated for every ' +
      Integer.valueOf(freqValue.trim()) +
      ' ' +
      freqType;
  }

  @AuraEnabled
  public static String stopConnectorSchedules(String connectorKey) {
    QuickBridgeAdminGuard.requireRunSync();
    String integrationType = connectorKeyToIntegrationType(connectorKey);
    List<Scheduled_Integration_Job__c> jobs = [
      SELECT Id, Status__c, Deleted_DateTime__c
      FROM Scheduled_Integration_Job__c
      WHERE
        Integration_Type__c = :integrationType
        AND Status__c IN :LIVE_STATUSES
    ];
    for (Scheduled_Integration_Job__c job : jobs) {
      job.Status__c = 'Deleted';
      job.Deleted_DateTime__c = Datetime.now();
    }
    if (!jobs.isEmpty())
      update jobs;
    QuickBridgeAdminGuard.audit(
      'SCHEDULE_STOP_ALL',
      connectorKey,
      'Success',
      String.valueOf(jobs.size()),
      null
    );
    return jobs.isEmpty()
      ? 'Notice: No active schedule found to stop.'
      : 'Success: Schedule stopped successfully.';
  }

  public static String connectorKeyToIntegrationType(String connectorKey) {
    return ConnectorRegistryService.integrationTypeFor(connectorKey);
  }

  @AuraEnabled
  public static void togglePauseStatus(String connectorKey, Boolean pauseIt) {
    QuickBridgeAdminGuard.requireRunSync();
    Sync_Settings__c settings = Sync_Settings__c.getOrgDefaults();
    settings.Is_Paused__c = pauseIt == true;
    upsert settings;
    QuickBridgeAdminGuard.audit(
      'SCHEDULE_PAUSE_TOGGLE',
      connectorKey,
      'Success',
      'paused=' + String.valueOf(pauseIt == true),
      null
    );
  }

  @AuraEnabled(cacheable=true)
  public static Boolean getPauseStatus(String connectorKey) {
    QuickBridgeAdminGuard.requireView();
    Sync_Settings__c settings = Sync_Settings__c.getOrgDefaults();
    return settings.Is_Paused__c;
  }

  private static Map<String, Object> toUiMap(Scheduled_Integration_Job__c job) {
    Map<String, Object> jobMap = new Map<String, Object>();
    String fullName = String.isBlank(job.Scheduler_Name__c)
      ? job.Logical_Job_Key__c
      : job.Scheduler_Name__c;
    String syncObjectName = String.isBlank(job.Source_Object__c)
      ? 'Unknown'
      : job.Source_Object__c;
    jobMap.put('id', job.Id);
    jobMap.put('status', job.Status__c);
    jobMap.put('syncObject', syncObjectName);
    jobMap.put('name', fullName);
    jobMap.put(
      'nextRun',
      job.Next_Run_At__c != null ? job.Next_Run_At__c.format() : 'Not Scheduled'
    );
    jobMap.put(
      'lastRun',
      job.Last_Run_At__c != null ? job.Last_Run_At__c.format() : 'N/A'
    );
    jobMap.put(
      'createdBy',
      job.Created_By_User__r != null ? job.Created_By_User__r.Name : 'System'
    );
    jobMap.put(
      'createdDate',
      job.Created_DateTime__c != null ? job.Created_DateTime__c.format() : 'N/A'
    );
    jobMap.put(
      'frequencyText',
      formatFrequency(job.Frequency_Value__c, job.Frequency_Type__c)
    );
    return jobMap;
  }

  private static Set<String> mappingIntegrationKeys(
    ConnectorRegistryService.ConnectorDescriptor descriptor,
    String connectorKey
  ) {
    Set<String> keys = new Set<String>();
    addMappingKey(keys, connectorKey);
    if (descriptor != null) {
      addMappingKey(keys, descriptor.connectorKey);
      addMappingKey(keys, descriptor.productKey);
      addMappingKey(keys, descriptor.label);
      addMappingKey(keys, descriptor.integrationType);
      for (String aliasValue : splitList(descriptor.aliases)) {
        addMappingKey(keys, aliasValue);
      }
    }
    if (keys.isEmpty()) {
      keys.add(connectorKey);
    }
    return keys;
  }

  private static void addMappingKey(Set<String> keys, String value) {
    if (String.isNotBlank(value)) {
      keys.add(value.trim());
    }
  }

  private static List<String> splitList(String rawValue) {
    List<String> values = new List<String>();
    if (String.isBlank(rawValue)) {
      return values;
    }
    for (String value : rawValue.split(',')) {
      if (String.isNotBlank(value)) {
        values.add(value.trim());
      }
    }
    return values;
  }

  private static void validateScheduleConfiguration(String connectorKey) {
    String validatorClassName = ConnectorRegistryService.adapterClassFor(
      connectorKey,
      'scheduler.validator'
    );
    if (String.isBlank(validatorClassName)) {
      return;
    }
    ConnectorAdapterAllowlist.assertAllowed(validatorClassName);
    Type validatorType = Type.forName(validatorClassName);
    if (validatorType == null) {
      validatorType = Type.forName('QuickBridgeTLG', validatorClassName);
    }
    if (validatorType != null) {
      ((SchedulerConfigurationValidator) validatorType.newInstance()).validate();
    }
  }

  private static String buildLogicalJobName(
    String integrationType,
    String selectedObject,
    String direction
  ) {
    String connectorKey = ConnectorRegistryService.connectorKeyForIntegrationType(
      integrationType
    );
    ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(
      connectorKey
    );
    String label = descriptor == null || String.isBlank(descriptor.label)
      ? integrationType
      : descriptor.label;
    String prefix = label + ' Sync';
    String directionTag = String.isBlank(direction)
      ? ''
      : (direction == 'Out' ? ' [Out]' : ' [In]');
    return prefix +
      ' - ' +
      selectedObject +
      directionTag +
      ' - ' +
      Datetime.now().format('MM/dd/yyyy hh:mm a');
  }

  private static String formatFrequency(
    Decimal frequencyValue,
    String frequencyType
  ) {
    Integer safeValue = frequencyValue == null ? 1 : frequencyValue.intValue();
    if (String.isBlank(frequencyType))
      return 'Dynamic Schedule';
    return 'Every ' + safeValue + ' ' + frequencyType;
  }

  private static void markLogicalSchedulesDeletedByPrefix(String jobName) {
    if (String.isBlank(jobName)) {
      return;
    }
    String searchName =
      SchedulerEntitlementService.normalizeLogicalJobName(jobName) + '%';
    List<Scheduled_Integration_Job__c> jobs = [
      SELECT Id, Status__c, Deleted_DateTime__c
      FROM Scheduled_Integration_Job__c
      WHERE Logical_Job_Key__c LIKE :searchName AND Status__c IN :LIVE_STATUSES
    ];
    for (Scheduled_Integration_Job__c job : jobs) {
      job.Status__c = 'Deleted';
      job.Deleted_DateTime__c = Datetime.now();
    }
    if (!jobs.isEmpty()) {
      update jobs;
    }
  }

  private static ParsedJobName parseJobName(
    String jobName,
    String connectorKey
  ) {
    ParsedJobName parsed = new ParsedJobName();
    parsed.sourceObject = ConnectorRegistryService.normalize(connectorKey) == 'shopify'
      ? 'Customers'
      : 'Account';
    parsed.direction = ConnectorRegistryService.normalize(connectorKey) == 'shopify'
      ? 'In'
      : null;
    if (String.isBlank(jobName))
      return parsed;

    List<String> nameParts = jobName.split(' - ');
    if (nameParts.size() > 1) {
      String objectAndDirection = nameParts[1];
      parsed.direction = objectAndDirection.contains('[Out]')
        ? 'Out'
        : (objectAndDirection.contains('[In]') ? 'In' : parsed.direction);
      parsed.sourceObject = objectAndDirection.replace(' [Out]', '')
        .replace(' [In]', '')
        .trim();
    }
    return parsed;
  }

  private class ParsedJobName {
    private String sourceObject;
    private String direction;
  }
}