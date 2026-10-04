/*
Class Name: AIRecordRetentionBatch

=================================================================
=================================================================

Description: Deletes the package's platform logs, violations, execution steps and conversation messages once
they are older than the lifetime set on AIAssistSettings__c (PlatformLogRetentionDays__c 30,
ViolationRetentionDays__c 365, StepRetentionDays__c 7, MessageRetentionDays__c 30). A blank or zero lifetime
keeps the records indefinitely (steps and messages then go with their conversation). Steps and messages
of a conversation on legal hold are kept. A violation that is still New is kept whatever its age, because
deleting evidence nobody has reviewed would hide it.

One instance handles one object, chosen by the constructor, so each runs in its own transactions. The
no-argument constructor works through every kind in turn, each run starting the next, so the maintenance
job starts a single batch.
System mode: no user holds Delete on either object. It runs whether or not the
application is switched on.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development. Applies the two retention settings the object model added.
2.0          Chandler Stuart          Runs while the application is off.
3.0          Chandler Stuart          Steps and messages by their own retention settings, honouring legal hold. A chained run for the maintenance job.
*/

public inherited sharing class AIRecordRetentionBatch implements Database.Batchable<SObject> {
  public static final String LOGS = 'Logs';
  public static final String VIOLATIONS = 'Violations';
  public static final String STEPS = 'Steps';
  public static final String MESSAGES = 'Messages';
  // The order a chained run works through.
  private static final List<String> RECORD_KINDS = new List<String>{
    LOGS,
    VIOLATIONS,
    STEPS,
    MESSAGES
  };

  private String recordKind;
  private Boolean isChained = false;

  public AIRecordRetentionBatch(String recordKind) {
    this.recordKind = recordKind;
  }

  // Every kind, one after another: each run starts the next when it finishes, so the maintenance job starts one batch, not four.
  public AIRecordRetentionBatch() {
    this.recordKind = RECORD_KINDS[0];
    this.isChained = true;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
    Decimal lifetimeDays = recordKind == VIOLATIONS
      ? settings.ViolationRetentionDays__c
      : (recordKind == STEPS
          ? settings.StepRetentionDays__c
          : (recordKind == MESSAGES
              ? settings.MessageRetentionDays__c
              : settings.PlatformLogRetentionDays__c));
    Boolean isKept = lifetimeDays == null || lifetimeDays < 1;
    Datetime cutoff = isKept
      ? Datetime.newInstance(1900, 1, 1)
      : System.now().addDays(-Integer.valueOf(lifetimeDays));

    if (recordKind == VIOLATIONS) {
      return Database.getQueryLocator(
        [
          SELECT Id
          FROM AIViolation__c
          WHERE
            CreatedDate < :cutoff
            AND ReviewStatus__c != :AIAssistApplicationConstants.REVIEW_STATUS_NEW
          WITH SYSTEM_MODE
        ]
      );
    }

    // Steps and messages of a conversation on legal hold are kept, like the conversation itself.
    if (recordKind == STEPS) {
      return Database.getQueryLocator(
        [
          SELECT Id
          FROM AIExecutionStep__c
          WHERE
            CreatedDate < :cutoff
            AND AIConversationMessage__r.AIConversation__r.IsOnLegalHold__c = FALSE
          WITH SYSTEM_MODE
        ]
      );
    }

    if (recordKind == MESSAGES) {
      return Database.getQueryLocator(
        [
          SELECT Id
          FROM AIConversationMessage__c
          WHERE
            CreatedDate < :cutoff
            AND AIConversation__r.IsOnLegalHold__c = FALSE
          WITH SYSTEM_MODE
        ]
      );
    }

    return Database.getQueryLocator(
      [
        SELECT Id
        FROM AIPlatformLog__c
        WHERE CreatedDate < :cutoff
        WITH SYSTEM_MODE
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    AIMessagingDataService.deleteAndLogFailures(
      scope,
      'AIRecordRetentionBatch',
      'execute'
    );
  }

  // A chained run starts the next kind. A failure to start it is logged: the next maintenance run tries again.
  public void finish(Database.BatchableContext context) {
    Integer nextIndex = RECORD_KINDS.indexOf(recordKind) + 1;
    if (!isChained || nextIndex == 0 || nextIndex >= RECORD_KINDS.size())
      return;

    try {
      AIRecordRetentionBatch nextBatch = new AIRecordRetentionBatch(
        RECORD_KINDS[nextIndex]
      );
      nextBatch.isChained = true;
      Database.executeBatch(
        nextBatch,
        AIAssistApplicationConstants.HOUSEKEEPING_BATCH_SIZE
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIRecordRetentionBatch',
        'finish'
      );
    }
  }
}
