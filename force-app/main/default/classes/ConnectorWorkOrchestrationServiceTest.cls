@IsTest
private class ConnectorWorkOrchestrationServiceTest {
  @IsTest
  static void metaAndNetSuiteSchedulersTransferOwnershipToSharedWork() {
    Scheduled_Integration_Job__c metaSchedule = scheduleValue(
      'Meta Shared Work',
      'Meta',
      'Insights',
      'lease-meta'
    );
    Scheduled_Integration_Job__c netSuiteSchedule = scheduleValue(
      'NetSuite Shared Work',
      'NetSuite',
      'Customers',
      'lease-netsuite'
    );
    insert new List<Scheduled_Integration_Job__c>{
      metaSchedule,
      netSuiteSchedule
    };

    IntegrationWorkService.enqueue(
      MetaScheduledOperationAdapter.buildRequest(metaSchedule, 'lease-meta')
    );
    IntegrationWorkService.enqueue(
      NetSuiteScheduledOperationAdapter.buildRequest(
        netSuiteSchedule,
        'lease-netsuite'
      )
    );

    Map<String, Integration_Work_Item__c> itemsByIntegration = new Map<String, Integration_Work_Item__c>();
    for (Integration_Work_Item__c item : [
      SELECT Integration__c, Operation__c, Source_Object__c, Payload__c
      FROM Integration_Work_Item__c
      WHERE Integration__c IN ('Meta', 'NetSuite')
    ]) {
      itemsByIntegration.put(item.Integration__c, item);
    }
    Assert.areEqual(
      'InsightsSync',
      itemsByIntegration.get('Meta').Operation__c
    );
    Assert.areEqual(
      'CustomerSync',
      itemsByIntegration.get('NetSuite').Operation__c
    );
    Assert.isNotNull(
      ConnectorWorkOrchestrationService.scheduleContext(
        itemsByIntegration.get('Meta')
      )
    );
    Assert.isNotNull(
      ConnectorWorkOrchestrationService.scheduleContext(
        itemsByIntegration.get('NetSuite')
      )
    );
  }

  @IsTest
  static void terminalWorkCompletesScheduleAndStaleLeaseCannotComplete() {
    Scheduled_Integration_Job__c currentSchedule = scheduleValue(
      'Current Shared Work',
      'Meta',
      'Reconciliation',
      'lease-current'
    );
    currentSchedule.Status__c = 'Running';
    Scheduled_Integration_Job__c staleSchedule = scheduleValue(
      'Stale Shared Work',
      'Meta',
      'Reconciliation',
      'lease-new'
    );
    staleSchedule.Status__c = 'Running';
    insert new List<Scheduled_Integration_Job__c>{
      currentSchedule,
      staleSchedule
    };

    ProcessingFixture currentFixture = processingFixture(
      currentSchedule,
      'lease-current',
      'work-current'
    );
    ProcessingFixture staleFixture = processingFixture(
      staleSchedule,
      'lease-old',
      'work-stale'
    );

    new IntegrationWorkProcessor(
        currentFixture.itemId,
        currentFixture.processorToken
      )
      .execute(null);
    new IntegrationWorkProcessor(
        staleFixture.itemId,
        staleFixture.processorToken
      )
      .execute(null);

    Map<Id, Scheduled_Integration_Job__c> schedulesById = new Map<Id, Scheduled_Integration_Job__c>(
      [
        SELECT Status__c, Lease_Token__c, Last_Run_At__c
        FROM Scheduled_Integration_Job__c
        WHERE Id IN :new Set<Id>{ currentSchedule.Id, staleSchedule.Id }
      ]
    );
    Assert.areEqual('Ready', schedulesById.get(currentSchedule.Id).Status__c);
    Assert.isNull(schedulesById.get(currentSchedule.Id).Lease_Token__c);
    Assert.isNotNull(schedulesById.get(currentSchedule.Id).Last_Run_At__c);
    Assert.areEqual('Running', schedulesById.get(staleSchedule.Id).Status__c);
    Assert.areEqual(
      'lease-new',
      schedulesById.get(staleSchedule.Id).Lease_Token__c
    );
  }

  @IsTest
  static void overlappingScheduledRunsUseDistinctWorkAndTheSameLock() {
    Scheduled_Integration_Job__c firstSchedule = scheduleValue(
      'Meta Overlap One',
      'Meta',
      'Insights',
      'lease-overlap-one'
    );
    Scheduled_Integration_Job__c secondSchedule = scheduleValue(
      'Meta Overlap Two',
      'Meta',
      'Insights',
      'lease-overlap-two'
    );
    insert new List<Scheduled_Integration_Job__c>{
      firstSchedule,
      secondSchedule
    };

    IntegrationWorkService.enqueue(
      MetaScheduledOperationAdapter.buildRequest(
        firstSchedule,
        'lease-overlap-one'
      )
    );
    IntegrationWorkService.enqueue(
      MetaScheduledOperationAdapter.buildRequest(
        secondSchedule,
        'lease-overlap-two'
      )
    );

    List<Integration_Work_Item__c> workItems = [
      SELECT Source_Record_Id__c, Lock_Key__c
      FROM Integration_Work_Item__c
      WHERE Integration__c = 'Meta' AND Operation__c = 'InsightsSync'
    ];
    Assert.areEqual(2, workItems.size());
    Assert.areNotEqual(
      workItems[0].Source_Record_Id__c,
      workItems[1].Source_Record_Id__c
    );
    Assert.areEqual('Meta:InsightsSync', workItems[0].Lock_Key__c);
    Assert.areEqual(workItems[0].Lock_Key__c, workItems[1].Lock_Key__c);
  }

  @IsTest
  static void permanentWorkFailureFailsOwnedSchedule() {
    Scheduled_Integration_Job__c schedule = scheduleValue(
      'Failed Shared Work',
      'Meta',
      'Unsupported',
      'lease-failed'
    );
    schedule.Status__c = 'Running';
    insert schedule;
    ProcessingFixture fixture = processingFixture(
      schedule,
      'lease-failed',
      'work-failed'
    );
    Integration_Work_Item__c itemUpdate = new Integration_Work_Item__c(
      Id = fixture.itemId,
      Operation__c = 'Unsupported'
    );
    update itemUpdate;

    new IntegrationWorkProcessor(fixture.itemId, fixture.processorToken)
      .execute(null);

    Integration_Work_Item__c failedItem = [
      SELECT Status__c, Last_Error__c
      FROM Integration_Work_Item__c
      WHERE Id = :fixture.itemId
    ];
    Scheduled_Integration_Job__c failedSchedule = [
      SELECT Status__c, Lease_Token__c, Last_Error__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual(IntegrationWorkService.STATUS_FAILED, failedItem.Status__c);
    Assert.areEqual('Failed', failedSchedule.Status__c);
    Assert.isNull(failedSchedule.Lease_Token__c);
    Assert.isTrue(failedSchedule.Last_Error__c.contains('Unsupported'));
  }

  @IsTest
  static void needsReprocessRenewsThenCompletesTheSameSchedule() {
    Scheduled_Integration_Job__c schedule = scheduleValue(
      'Reprocess Shared Work',
      'Meta',
      'Reconciliation',
      'lease-reprocess'
    );
    schedule.Status__c = 'Running';
    insert schedule;
    ProcessingFixture fixture = processingFixture(
      schedule,
      'lease-reprocess',
      'work-reprocess'
    );
    update new Integration_Work_Item__c(
      Id = fixture.itemId,
      Needs_Reprocess__c = true
    );

    new IntegrationWorkProcessor(fixture.itemId, fixture.processorToken)
      .execute(null);

    Integration_Work_Item__c pendingItem = [
      SELECT Status__c, Needs_Reprocess__c
      FROM Integration_Work_Item__c
      WHERE Id = :fixture.itemId
    ];
    Scheduled_Integration_Job__c runningSchedule = [
      SELECT Status__c, Lease_Token__c
      FROM Scheduled_Integration_Job__c
      WHERE Id = :schedule.Id
    ];
    Assert.areEqual(
      IntegrationWorkService.STATUS_PENDING,
      pendingItem.Status__c
    );
    Assert.isFalse(pendingItem.Needs_Reprocess__c);
    Assert.areEqual('Running', runningSchedule.Status__c);
    Assert.areEqual('lease-reprocess', runningSchedule.Lease_Token__c);

    String secondToken = 'processor-work-reprocess-2';
    update new Integration_Work_Item__c(
      Id = fixture.itemId,
      Status__c = IntegrationWorkService.STATUS_PROCESSING,
      Processor_Token__c = secondToken,
      Lease_Expires_At__c = System.now().addMinutes(5)
    );
    Integration_Work_Lock__c releasedLock = [
      SELECT Id
      FROM Integration_Work_Lock__c
      WHERE Lock_Key__c = 'Meta:work-reprocess'
      LIMIT 1
    ];
    update new Integration_Work_Lock__c(
      Id = releasedLock.Id,
      Status__c = 'Locked',
      Work_Item__c = fixture.itemId,
      Processor_Token__c = secondToken,
      Lease_Expires_At__c = System.now().addMinutes(5)
    );

    new IntegrationWorkProcessor(fixture.itemId, secondToken).execute(null);

    Assert.areEqual(
      IntegrationWorkService.STATUS_COMPLETED,
      [
        SELECT Status__c
        FROM Integration_Work_Item__c
        WHERE Id = :fixture.itemId
      ]
      .Status__c
    );
    Assert.areEqual(
      'Ready',
      [
        SELECT Status__c
        FROM Scheduled_Integration_Job__c
        WHERE Id = :schedule.Id
      ]
      .Status__c
    );
  }

  @IsTest
  static void legacyAdapterEntryPointsAndAliasesRemainCompatible() {
    IntegrationWorkRequest legacyMeta = MetaScheduledOperationAdapter.buildRequest(
      new Scheduled_Integration_Job__c(Source_Object__c = 'InsightsSync'),
      null
    );
    Assert.areEqual('Meta', legacyMeta.integration);
    Assert.areEqual('InsightsSync', legacyMeta.operation);
    Assert.isNull(
      ConnectorWorkOrchestrationService.scheduleContext(
        new Integration_Work_Item__c(Payload__c = legacyMeta.payloadJson)
      )
    );
    Assert.areEqual(
      'CustomerSync',
      NetSuiteScheduledOperationAdapter.operationFor('account')
    );
    Assert.areEqual(
      'ItemSync',
      NetSuiteScheduledOperationAdapter.operationFor('Product2')
    );
    Assert.areEqual(
      'FulfillmentSync',
      NetSuiteScheduledOperationAdapter.operationFor('shipment')
    );
    IntegrationWorkRequest legacyNetSuite = NetSuiteScheduledOperationAdapter.buildRequest(
      new Scheduled_Integration_Job__c(Source_Object__c = 'Customers'),
      null
    );
    Assert.areEqual('NetSuite', legacyNetSuite.integration);
    Assert.areEqual('CustomerSync', legacyNetSuite.operation);
    Assert.isNull(
      ConnectorWorkOrchestrationService.scheduleContext(
        new Integration_Work_Item__c(Payload__c = legacyNetSuite.payloadJson)
      )
    );

    ConnectorScheduleDispatchResult missingLease = new MetaScheduledOperationAdapter()
      .dispatch(
        new Scheduled_Integration_Job__c(Source_Object__c = 'Campaign'),
        null
      );
    Assert.isTrue(missingLease.hasFailed());
    Assert.isFalse(missingLease.ownershipTransferred);
  }

  private static ProcessingFixture processingFixture(
    Scheduled_Integration_Job__c schedule,
    String leaseToken,
    String uniqueSuffix
  ) {
    IntegrationWorkRequest request = ConnectorWorkOrchestrationService.scheduledRequest(
      schedule,
      leaseToken,
      'Meta',
      'Reconciliation',
      'Reconciliation',
      uniqueSuffix,
      'Meta:' + uniqueSuffix,
      null
    );
    String processorToken = 'processor-' + uniqueSuffix;
    Integration_Work_Item__c item = new Integration_Work_Item__c(
      Unique_Key__c = IntegrationWorkService.buildUniqueKey(request),
      Status__c = IntegrationWorkService.STATUS_PROCESSING,
      Integration__c = request.integration,
      Operation__c = request.operation,
      Source_Object__c = request.sourceObject,
      Source_Record_Id__c = request.sourceRecordId,
      Lock_Key__c = request.lockKey,
      Payload__c = request.payloadJson,
      Attempt_Count__c = 0,
      Max_Attempts__c = 2,
      Processor_Token__c = processorToken,
      Lease_Expires_At__c = System.now().addMinutes(5)
    );
    insert item;
    insert new Integration_Work_Lock__c(
      Name = request.lockKey.left(80),
      Lock_Key__c = request.lockKey,
      Status__c = 'Locked',
      Work_Item__c = item.Id,
      Processor_Token__c = processorToken,
      Lease_Expires_At__c = System.now().addMinutes(5)
    );
    return new ProcessingFixture(item.Id, processorToken);
  }

  private static Scheduled_Integration_Job__c scheduleValue(
    String keyValue,
    String integration,
    String sourceObject,
    String leaseToken
  ) {
    return new Scheduled_Integration_Job__c(
      Logical_Job_Key__c = keyValue,
      Scheduler_Name__c = keyValue,
      Integration_Type__c = integration,
      Source_Object__c = sourceObject,
      Direction__c = 'In',
      Frequency_Value__c = 5,
      Frequency_Type__c = 'Minutes',
      Status__c = 'Claimed',
      Lease_Token__c = leaseToken,
      Lease_Expires_At__c = System.now().addMinutes(5),
      Next_Run_At__c = System.now().addMinutes(-1)
    );
  }

  private class ProcessingFixture {
    Id itemId;
    String processorToken;

    ProcessingFixture(Id itemId, String processorToken) {
      this.itemId = itemId;
      this.processorToken = processorToken;
    }
  }
}