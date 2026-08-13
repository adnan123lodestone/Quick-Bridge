/**
 * Owns terminal schedule completion for legacy scheduled adapters that enqueue
 * asynchronous work without implementing DeferredScheduledOperationAdapter.
 *
 * The original processor job remains the immutable discovery root. Monitor
 * queueables are excluded from the descendant graph so their own chaining can
 * never be mistaken for provider work.
 */
public with sharing class ConnectorAsyncJobMonitor implements Queueable {
  public static final Integer POLL_DELAY_MINUTES = 1;
  @TestVisible
  private static final Integer MAX_POLL_COUNT = 120;
  @TestVisible
  private static final Integer MAX_MONITOR_MINUTES = 180;
  @TestVisible
  private static final Integer MAX_DISCOVERY_DEPTH = 25;
  @TestVisible
  private static final Integer MAX_JOBS_PER_LEVEL = 2000;
  private static final String MONITOR_CLASS_NAME = 'ConnectorAsyncJobMonitor';

  private Id scheduleId;
  private String leaseToken;
  private Id rootJobId;
  private Datetime startedAt;
  private Integer pollCount;

  public ConnectorAsyncJobMonitor(
    Id scheduleId,
    String leaseToken,
    Id rootJobId,
    Datetime startedAt,
    Integer pollCount
  ) {
    this.scheduleId = scheduleId;
    this.leaseToken = leaseToken;
    this.rootJobId = rootJobId;
    this.startedAt = startedAt == null ? Datetime.now() : startedAt;
    this.pollCount = pollCount == null ? 0 : Math.max(0, pollCount);
  }

  public void execute(QueueableContext context) {
    Id monitorJobId = context == null ? null : context.getJobId();
    if (
      !ConnectorScheduleService.markRunning(
        scheduleId,
        leaseToken,
        monitorJobId,
        POLL_DELAY_MINUTES * 60
      )
    ) {
      return;
    }

    DiscoveryResult discovery = discoverDescendants(rootJobId, monitorJobId);
    PollDecision decision = evaluateSnapshots(
      discovery.snapshots,
      discovery.complete
    );
    if (decision.failed) {
      ConnectorScheduleService.completeFailure(
        scheduleId,
        leaseToken,
        decision.errorMessage
      );
      return;
    }
    if (decision.complete) {
      ConnectorScheduleService.completeSuccess(scheduleId, leaseToken);
      return;
    }
    if (hasTimedOut(startedAt, pollCount, Datetime.now())) {
      ConnectorScheduleService.completeFailure(
        scheduleId,
        leaseToken,
        'Legacy asynchronous work did not reach a terminal state within the bounded monitoring window.'
      );
      return;
    }

    try {
      Id nextMonitorJobId = System.enqueueJob(
        new ConnectorAsyncJobMonitor(
          scheduleId,
          leaseToken,
          rootJobId,
          startedAt,
          pollCount + 1
        ),
        POLL_DELAY_MINUTES
      );
      if (
        !ConnectorScheduleService.markRunning(
          scheduleId,
          leaseToken,
          nextMonitorJobId,
          POLL_DELAY_MINUTES * 60
        )
      ) {
        return;
      }
    } catch (Exception enqueueException) {
      ConnectorScheduleService.completeFailure(
        scheduleId,
        leaseToken,
        'Unable to continue legacy asynchronous job monitoring: ' +
        ConnectorExecutionResult.sanitizeError(enqueueException.getMessage())
      );
    }
  }

  @TestVisible
  public static List<AsyncApexJob> directProviderChildren(Id rootId) {
    if (rootId == null) {
      return new List<AsyncApexJob>();
    }
    List<AsyncApexJob> children = [
      SELECT
        Id,
        ParentJobId,
        Status,
        NumberOfErrors,
        ExtendedStatus,
        JobType,
        ApexClass.Name
      FROM AsyncApexJob
      WHERE ParentJobId = :rootId
      LIMIT 2001
    ];
    return providerJobs(children, null);
  }

  private static DiscoveryResult discoverDescendants(
    Id rootId,
    Id currentMonitorJobId
  ) {
    DiscoveryResult result = new DiscoveryResult();
    if (rootId == null) {
      result.complete = false;
      return result;
    }

    Set<Id> frontier = new Set<Id>{ rootId };
    Set<Id> visited = new Set<Id>{ rootId };
    for (Integer depth = 0; depth < MAX_DISCOVERY_DEPTH; depth++) {
      if (frontier.isEmpty()) {
        return result;
      }
      List<AsyncApexJob> queried = [
        SELECT
          Id,
          ParentJobId,
          Status,
          NumberOfErrors,
          ExtendedStatus,
          JobType,
          ApexClass.Name
        FROM AsyncApexJob
        WHERE ParentJobId IN :frontier
        LIMIT 2001
      ];
      if (queried.size() > MAX_JOBS_PER_LEVEL) {
        result.complete = false;
        return result;
      }

      Set<Id> nextFrontier = new Set<Id>();
      for (AsyncApexJob job : providerJobs(queried, currentMonitorJobId)) {
        if (visited.add(job.Id)) {
          result.snapshots.add(jobSnapshot(job));
          nextFrontier.add(job.Id);
        }
      }
      frontier = nextFrontier;
    }
    result.complete = frontier.isEmpty();
    return result;
  }

  private static List<AsyncApexJob> providerJobs(
    List<AsyncApexJob> jobs,
    Id currentMonitorJobId
  ) {
    List<AsyncApexJob> providerJobs = new List<AsyncApexJob>();
    for (AsyncApexJob job : jobs) {
      if (job.Id == currentMonitorJobId || job.JobType == 'BatchApexWorker') {
        continue;
      }
      if (job.ApexClass != null && job.ApexClass.Name == MONITOR_CLASS_NAME) {
        continue;
      }
      providerJobs.add(job);
    }
    return providerJobs;
  }

  @TestVisible
  static PollDecision evaluateSnapshots(
    List<JobSnapshot> snapshots,
    Boolean discoveryComplete
  ) {
    if (discoveryComplete != true) {
      return pollFailure(
        'Legacy asynchronous job discovery exceeded its safety bounds.'
      );
    }
    if (snapshots == null || snapshots.isEmpty()) {
      return pollPending();
    }

    Boolean allCompleted = true;
    for (JobSnapshot snapshot : snapshots) {
      if (
        snapshot.status == 'Failed' ||
        snapshot.status == 'Aborted' ||
        snapshot.numberOfErrors > 0
      ) {
        String diagnostic =
          'Legacy asynchronous job ' +
          snapshot.jobId +
          ' ended with status ' +
          snapshot.status +
          ' and ' +
          snapshot.numberOfErrors +
          ' error(s).';
        if (String.isNotBlank(snapshot.extendedStatus)) {
          diagnostic += ' ' + snapshot.extendedStatus;
        }
        return pollFailure(ConnectorExecutionResult.sanitizeError(diagnostic));
      }
      allCompleted = allCompleted && snapshot.status == 'Completed';
    }
    return allCompleted ? pollSuccess() : pollPending();
  }

  private static JobSnapshot jobSnapshot(AsyncApexJob job) {
    return new JobSnapshot(
      job.Id,
      job.Status,
      job.NumberOfErrors,
      job.ExtendedStatus
    );
  }

  private static PollDecision pollSuccess() {
    return new PollDecision(true, false, null);
  }

  private static PollDecision pollPending() {
    return new PollDecision(false, false, null);
  }

  private static PollDecision pollFailure(String message) {
    return new PollDecision(false, true, message);
  }

  @TestVisible
  static Boolean hasTimedOut(
    Datetime monitorStartedAt,
    Integer completedPollCount,
    Datetime nowValue
  ) {
    Integer safePollCount = completedPollCount == null ? 0 : completedPollCount;
    Datetime safeNow = nowValue == null ? Datetime.now() : nowValue;
    return safePollCount >= MAX_POLL_COUNT ||
      monitorStartedAt == null ||
      monitorStartedAt.addMinutes(MAX_MONITOR_MINUTES) <= safeNow;
  }

  @TestVisible
  private class DiscoveryResult {
    @TestVisible
    Boolean complete = true;
    @TestVisible
    List<JobSnapshot> snapshots = new List<JobSnapshot>();
  }

  @TestVisible
  class JobSnapshot {
    @TestVisible
    Id jobId;
    @TestVisible
    String status;
    @TestVisible
    Integer numberOfErrors;
    @TestVisible
    String extendedStatus;

    @TestVisible
    JobSnapshot(
      Id jobId,
      String status,
      Integer numberOfErrors,
      String extendedStatus
    ) {
      this.jobId = jobId;
      this.status = status;
      this.numberOfErrors = numberOfErrors == null ? 0 : numberOfErrors;
      this.extendedStatus = extendedStatus;
    }
  }

  @TestVisible
  class PollDecision {
    @TestVisible
    Boolean complete;
    @TestVisible
    Boolean failed;
    @TestVisible
    String errorMessage;

    private PollDecision(
      Boolean complete,
      Boolean failed,
      String errorMessage
    ) {
      this.complete = complete;
      this.failed = failed;
      this.errorMessage = errorMessage;
    }
  }
}