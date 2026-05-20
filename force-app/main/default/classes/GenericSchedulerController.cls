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

  @AuraEnabled
  public static String scheduleJob(
    String connectorKey,
    String freqValue,
    String freqType,
    String selectedObject,
    String direction
  ) {
    if (connectorKey == 'qbo') {
      QuickBooksAuthHandler.validateConfiguration();
    }
    QuickBridgeAdminGuard.requireRunSync();
    SchedulerEntitlementService.assertCanCreateSchedule();
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
    IntegrationUsageService.incrementTaskUsage(integrationType, 1);
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
    String normalized = ConnectorRegistryService.normalize(connectorKey);
    if (normalized == 'qbo' || normalized == 'quickbooks')
      return 'QuickBooks';
    if (normalized == 'shopify')
      return 'Shopify';
    ConnectorRegistryService.ConnectorDescriptor descriptor = ConnectorRegistryService.byKey(
      connectorKey
    );
    return descriptor == null ? connectorKey : descriptor.label;
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

  private static String buildLogicalJobName(
    String integrationType,
    String selectedObject,
    String direction
  ) {
    String prefix = integrationType == 'Shopify' ? 'Shopify Sync' : 'QBO Sync';
    String directionTag = integrationType == 'Shopify'
      ? (direction == 'Out' ? ' [Out]' : ' [In]')
      : '';
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
    parsed.sourceObject = ConnectorRegistryService.normalize(connectorKey) ==
      'shopify'
      ? 'Customers'
      : 'Account';
    parsed.direction = ConnectorRegistryService.normalize(connectorKey) ==
      'shopify'
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
