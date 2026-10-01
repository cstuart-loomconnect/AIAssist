/*
Class Name: AIMaintenanceScheduler

=================================================================
=================================================================

Description: The one job an administrator schedules (Setup > Apex Classes > Schedule Apex, typically nightly) to
run the package's housekeeping: close idle conversations, delete expired conversations, delete old
platform logs and old reviewed violations, and refresh the PII registry.

Nothing is scheduled by the package itself. A subscriber has a limit on scheduled and running jobs,
so the package adds none unasked. Each task is its own batch, so a failure in one does not stop the
others, and nothing runs while the application is switched off.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development. Replaces the separate schedulable batches with one entry point.
*/

public inherited sharing class AIMaintenanceScheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    if (!AIAssistSettingsService.isEnabled())
      return;

    try {
      Database.executeBatch(
        new AIConversationIdleBatch(),
        AIAssistApplicationConstants.HOUSEKEEPING_BATCH_SIZE
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIMaintenanceScheduler',
        'execute'
      );
    }
    try {
      Database.executeBatch(
        new AIConversationRetentionBatch(),
        AIAssistApplicationConstants.HOUSEKEEPING_BATCH_SIZE
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIMaintenanceScheduler',
        'execute'
      );
    }
    try {
      Database.executeBatch(
        new AIRecordRetentionBatch(AIRecordRetentionBatch.LOGS),
        AIAssistApplicationConstants.HOUSEKEEPING_BATCH_SIZE
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIMaintenanceScheduler',
        'execute'
      );
    }
    try {
      Database.executeBatch(
        new AIRecordRetentionBatch(AIRecordRetentionBatch.VIOLATIONS),
        AIAssistApplicationConstants.HOUSEKEEPING_BATCH_SIZE
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIMaintenanceScheduler',
        'execute'
      );
    }

    AIPiiRegistrySyncDispatcher.dispatchDueRegistries();
  }
}
