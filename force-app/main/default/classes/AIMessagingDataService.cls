/*
Class Name: AIMessagingDataService

=================================================================
=================================================================

Description: Every write the messaging layer makes to data the end user is not allowed to write,
and the one place a write is marked as the package's own. The write half of what was
AIMessagingRepository; AIMessagingSelector is the read half.

`without sharing` and explicit system mode on every statement, because the fields written are
system-managed: a message's processing status and token counts, a conversation's totals, usage
rows, execution evidence. The AI Assist User permission set can set none of them.

Nothing here decides WHO may do something; the caller authorises first.

The package's own writes bump a counter that AIConversationMessageTriggerHandler reads. A user
can create a message and choose its Sender, so the trigger refuses anything but a User message
unless the write came through here. That is what stops a message made to look like the
assistant's, which would be shown to colleagues and replayed to the model as its own answer.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, as the write half of AIMessagingRepository.
*/

public without sharing class AIMessagingDataService {
  // What one turn (or one new conversation) adds to the user's row in AIUsageDaily__c.
  public class UsageDelta {
    public Id userId;
    public Id agentId;
    public Id modelConfigurationId;
    public Integer messages = 0;
    public Integer conversations = 0;
    public Integer failedTurns = 0;
    public Integer violations = 0;
    public Decimal inputTokens = 0;
    public Decimal outputTokens = 0;
  }

  @TestVisible
  private static Integer writeDepth = 0;

  // True while the package itself is writing, read by the message trigger.
  public static Boolean isPackageWriting() {
    return writeDepth > 0;
  }

  // Inserts as the package. Throws on the first failure: a generic message for the user, the real error in detail.
  public static void insertAsPackage(List<SObject> records) {
    write(records, true, true, null, null);
  }

  public static void updateAsPackage(List<SObject> records) {
    write(records, false, true, null, null);
  }

  // For bookkeeping that must never fail the turn it describes (roll-ups, evidence). A failure is logged, not thrown.
  public static void insertAndLogFailures(
    List<SObject> records,
    String className,
    String methodName
  ) {
    write(records, true, false, className, methodName);
  }

  public static void updateAndLogFailures(
    List<SObject> records,
    String className,
    String methodName
  ) {
    write(records, false, false, className, methodName);
  }

  // Deletes as the package and returns how many were deleted. A record that cannot be deleted is logged once and the rest still go.
  public static Integer deleteAndLogFailures(
    List<SObject> records,
    String className,
    String methodName
  ) {
    if (records == null || records.isEmpty())
      return 0;

    Integer deletedCount = 0;
    Boolean isFailureLogged = false;

    for (
      Database.DeleteResult deleteResult : Database.delete(
        records,
        false,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      if (deleteResult.isSuccess()) {
        deletedCount++;
      } else if (!isFailureLogged) {
        isFailureLogged = true;
        AIPlatformLogManager.logCustomMessage(
          'A record could not be deleted: ' +
          deleteResult.getErrors()[0].getStatusCode(),
          deleteResult.getErrors()[0].getMessage(),
          className,
          methodName,
          deleteResult.getId()
        );
      }
    }

    return deletedCount;
  }

  // Adds a turn's usage to the user's row for the day, creating the row on first use. The row is read FOR UPDATE so two of the user's conversations finishing together add to each other instead of overwriting. Two simultaneous first-use inserts are settled by the unique UsageKey__c: the loser re-reads and adds.
  public static void addToDailyUsage(UsageDelta usageDelta) {
    if (usageDelta == null || usageDelta.userId == null)
      return;

    Date usageDate = Datetime.now().dateGmt();
    String usageKey =
      usageDelta.userId +
      '|' +
      usageDelta.agentId +
      '|' +
      usageDelta.modelConfigurationId +
      '|' +
      Datetime.newInstanceGmt(
          usageDate.year(),
          usageDate.month(),
          usageDate.day()
        )
        .formatGmt('yyyyMMdd');

    AIUsageDaily__c usageRow = AIMessagingSelector.lockDailyUsageRow(usageKey);

    if (usageRow == null) {
      usageRow = new AIUsageDaily__c(
        UsageKey__c = usageKey,
        UsageDate__c = usageDate,
        User__c = usageDelta.userId,
        AIAgent__c = usageDelta.agentId,
        AIModelConfiguration__c = usageDelta.modelConfigurationId,
        MessageCount__c = usageDelta.messages,
        ConversationCount__c = usageDelta.conversations,
        FailedTurnCount__c = usageDelta.failedTurns,
        InputTokens__c = usageDelta.inputTokens,
        OutputTokens__c = usageDelta.outputTokens,
        ViolationCount__c = usageDelta.violations
      );

      Database.SaveResult insertResult = Database.insert(
        usageRow,
        false,
        AccessLevel.SYSTEM_MODE
      );
      if (insertResult.isSuccess())
        return;

      usageRow = AIMessagingSelector.lockDailyUsageRow(usageKey);
      if (usageRow == null)
        throw AIMessagingException.newFailure(
          'Could not create usage row ' +
            usageKey +
            ': ' +
            insertResult.getErrors()[0].getMessage(),
          null
        );
    }

    usageRow.MessageCount__c =
      (usageRow.MessageCount__c == null ? 0 : usageRow.MessageCount__c) +
      usageDelta.messages;
    usageRow.ConversationCount__c =
      (usageRow.ConversationCount__c == null
        ? 0
        : usageRow.ConversationCount__c) + usageDelta.conversations;
    usageRow.FailedTurnCount__c =
      (usageRow.FailedTurnCount__c == null ? 0 : usageRow.FailedTurnCount__c) +
      usageDelta.failedTurns;
    usageRow.ViolationCount__c =
      (usageRow.ViolationCount__c == null ? 0 : usageRow.ViolationCount__c) +
      usageDelta.violations;
    usageRow.InputTokens__c =
      (usageRow.InputTokens__c == null ? 0 : usageRow.InputTokens__c) +
      usageDelta.inputTokens;
    usageRow.OutputTokens__c =
      (usageRow.OutputTokens__c == null ? 0 : usageRow.OutputTokens__c) +
      usageDelta.outputTokens;

    updateAsPackage(new List<SObject>{ usageRow });
  }

  private static void write(
    List<SObject> records,
    Boolean isInsert,
    Boolean shouldThrow,
    String className,
    String methodName
  ) {
    if (records == null || records.isEmpty())
      return;

    writeDepth++;

    try {
      List<Database.SaveResult> saveResults = isInsert
        ? Database.insert(records, false, AccessLevel.SYSTEM_MODE)
        : Database.update(records, false, AccessLevel.SYSTEM_MODE);

      if (!shouldThrow) {
        AIPlatformLogManager.logExceptions(saveResults, className, methodName);
        return;
      }

      for (Database.SaveResult saveResult : saveResults) {
        if (!saveResult.isSuccess())
          throw AIMessagingException.newFailure(
            'Failed to ' +
              (isInsert ? 'insert' : 'update') +
              ' record: ' +
              saveResult.getErrors()[0].getStatusCode() +
              ' ' +
              saveResult.getErrors()[0].getMessage(),
            null
          );
      }
    } finally {
      writeDepth--; // Cleared even when a write throws, or a user insert later in the transaction would be allowed to forge a sender.
    }
  }
}
