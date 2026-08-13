public class ConnectorScheduleDispatchResult {
  public Boolean ownershipTransferred { get; private set; }
  public Id asyncJobId { get; private set; }
  public String errorMessage { get; private set; }

  private ConnectorScheduleDispatchResult(
    Boolean ownershipTransferred,
    Id asyncJobId,
    String errorMessage
  ) {
    this.ownershipTransferred = ownershipTransferred == true;
    this.asyncJobId = asyncJobId;
    this.errorMessage = String.isBlank(errorMessage)
      ? null
      : errorMessage.left(32768);
  }

  public static ConnectorScheduleDispatchResult synchronous() {
    return new ConnectorScheduleDispatchResult(false, null, null);
  }

  public static ConnectorScheduleDispatchResult deferred(Id asyncJobId) {
    if (asyncJobId == null) {
      return failed(
        'A deferred scheduled operation must return an async job ID.'
      );
    }
    return new ConnectorScheduleDispatchResult(true, asyncJobId, null);
  }

  public static ConnectorScheduleDispatchResult failed(String errorMessage) {
    return new ConnectorScheduleDispatchResult(
      false,
      null,
      String.isBlank(errorMessage)
        ? 'Scheduled operation dispatch failed.'
        : errorMessage
    );
  }

  public Boolean hasFailed() {
    return String.isNotBlank(errorMessage);
  }
}