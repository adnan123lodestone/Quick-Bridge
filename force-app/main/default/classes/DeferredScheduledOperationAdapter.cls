public interface DeferredScheduledOperationAdapter {
  ConnectorScheduleDispatchResult dispatch(
    Scheduled_Integration_Job__c job,
    String leaseToken
  );
}