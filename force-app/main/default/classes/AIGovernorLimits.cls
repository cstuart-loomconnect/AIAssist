/*
Class Name: AIGovernorLimits

=================================================================
=================================================================

Description: Checks, before work starts, that enough of a Salesforce limit is left to finish it,
so the work stops cleanly instead of running into an uncatchable LimitException. The package
shares its transaction's limits with the subscriber's own code, so it stops early and leaves
room.

- Stop running tool calls before SOQL, callouts, CPU or heap run out.
- Detect a data source that wrote to the database, since uncommitted DML blocks every later
  callout in the same transaction.
- Keep track of the 120 seconds of callout time a transaction is allowed.

Every method returns the conservative answer if its own check fails: the one that stops the
work rather than letting it run on into a limit.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Sharing relaxed to inherited. Failures of the checks themselves are no longer logged one by one (reading Limits cannot fail).
*/

public inherited sharing class AIGovernorLimits {
  // A point-in-time count of the statements that can block callouts. Take one before running code you don't control (for example an Apex data source), then call isUncommittedDmlSince() afterwards.
  public class DmlSnapshot {
    private Integer dmlStatementCount;
    private Integer publishImmediateStatementCount;
  }

  public static DmlSnapshot takeDmlSnapshot() {
    DmlSnapshot snapshot = new DmlSnapshot();
    snapshot.dmlStatementCount = Limits.getDmlStatements();
    snapshot.publishImmediateStatementCount = Limits.getPublishImmediateDML();

    return snapshot;
  }

  // True when DML ran since the snapshot. Publish Immediately events (which is how AIPlatformLogManager logs) do not block callouts, so they are discounted in case the platform counts them as DML statements. A null snapshot never reports DML.
  public static Boolean isUncommittedDmlSince(DmlSnapshot snapshot) {
    if (snapshot == null)
      return false;

    return (Limits.getDmlStatements() - snapshot.dmlStatementCount) >
      (Limits.getPublishImmediateDML() -
      snapshot.publishImmediateStatementCount);
  }

  // True when a callout failed because of uncommitted DML earlier in the transaction. Retrying will not help: the same code will write again.
  public static Boolean isUncommittedWorkException(Exception calloutException) {
    return calloutException instanceof CalloutException &&
      String.isNotBlank(calloutException.getMessage()) &&
      calloutException.getMessage()
        .containsIgnoreCase(
          AIAssistApplicationConstants.UNCOMMITTED_WORK_ERROR_TEXT
        );
  }

  // How much of the 120 second callout budget is left, measured by wall-clock time since the start. Wall-clock is deliberately conservative: it also covers any callouts an Apex data source makes along the way.
  public static Integer getRemainingCalloutMilliseconds(
    Long calloutBudgetStartMilliseconds
  ) {
    if (calloutBudgetStartMilliseconds == null)
      return 0; // No start, no budget: the caller stops rather than risk the platform's limit.

    return AIAssistApplicationConstants.MAX_TRANSACTION_CALLOUT_MILLISECONDS -
      (System.currentTimeMillis() - calloutBudgetStartMilliseconds).intValue();
  }

  // True when enough Publish Immediately headroom is left to publish one more progress event. That allowance is shared with AIPlatformLogManager, whose logging must always get through, so live progress gives up first.
  public static Boolean isSafeToPublishProgress() {
    return Limits.getLimitPublishImmediateDML() -
      Limits.getPublishImmediateDML() >
      AIAssistApplicationConstants.PROGRESS_EVENT_RESERVED_PUBLISH_IMMEDIATE;
  }

  // True when enough of each limit is left to run one more tool call and still finish the turn safely.
  public static Boolean isSafeToRunToolCall() {
    return Limits.getLimitQueries() - Limits.getQueries() >
      AIAssistApplicationConstants.TOOL_CALL_RESERVED_SOQL_QUERIES &&
      Limits.getLimitCallouts() - Limits.getCallouts() >
      AIAssistApplicationConstants.TOOL_CALL_RESERVED_CALLOUTS &&
      Limits.getLimitCpuTime() - Limits.getCpuTime() >
      AIAssistApplicationConstants.TOOL_CALL_RESERVED_CPU_MILLISECONDS &&
      Limits.getLimitHeapSize() - Limits.getHeapSize() >
      AIAssistApplicationConstants.TOOL_CALL_RESERVED_HEAP_BYTES;
  }
}
