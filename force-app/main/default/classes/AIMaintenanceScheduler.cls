/*
Class Name: AIMaintenanceScheduler

=================================================================
=================================================================

Description: The package's one scheduled job. It runs the housekeeping: close idle conversations, delete
expired conversations, delete old platform logs and old reviewed violations, and refresh the PII
registry. Without it retention is never applied and no field is ever registered as personal data.

The post-install script schedules it once, daily, on a first install (scheduleDaily). That is the
only job the package adds: a subscriber has a limit on scheduled jobs. An administrator can delete
it or schedule it at another time in Setup > Scheduled Jobs; an upgrade does not put it back. Each
task is its own batch, so a failure in one does not stop the others, and nothing runs while the
application is switched off.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development. Replaces the separate schedulable batches with one entry point.
2.0          Chandler Stuart          scheduleDaily added, called by the post-install script.
3.0          Chandler Stuart          Refreshes the reading of the org limits (AIOrgLimitMonitor).
*/

public inherited sharing class AIMaintenanceScheduler implements Schedulable {
  public class AIMaintenanceSchedulerException extends Exception {
  }

  public static final String JOB_NAME = 'AI Assist Maintenance';
  private static final String DAILY_AT_2AM = '0 0 2 * * ?'; // In the time zone of the user the job runs as.

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  // Schedules the daily run unless a job of this name already exists. Returns the job's Id, or null when it was already scheduled.
  public static Id scheduleDaily() {
    if (isTestCustomExceptionThrown) {
      throw new AIMaintenanceSchedulerException(
        'Test exception for AIMaintenanceScheduler.scheduleDaily'
      );
    }

    if (
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name = :JOB_NAME
        WITH SYSTEM_MODE
      ] > 0
    )
      return null;

    return System.schedule(
      JOB_NAME,
      DAILY_AT_2AM,
      new AIMaintenanceScheduler()
    );
  }

  public void execute(SchedulableContext context) {
    if (!AIAssistSettingsService.isEnabled())
      return;

    AIOrgLimitMonitor.refreshIfStale(); // Keeps the mode and its alert current in an org where nobody is chatting. Never throws.

    // Each task is its own batch, started on its own, so one failing to start does not stop the others.
    List<Database.Batchable<SObject>> housekeepingBatches = new List<Database.Batchable<SObject>>{
      new AIConversationIdleBatch(),
      new AIConversationRetentionBatch(),
      new AIRecordRetentionBatch(AIRecordRetentionBatch.LOGS),
      new AIRecordRetentionBatch(AIRecordRetentionBatch.VIOLATIONS)
    };

    for (Database.Batchable<SObject> housekeepingBatch : housekeepingBatches) {
      try {
        if (isTestCustomExceptionThrown) {
          throw new AIMaintenanceSchedulerException(
            'Test exception for AIMaintenanceScheduler.execute'
          );
        }

        Database.executeBatch(
          housekeepingBatch,
          AIAssistApplicationConstants.HOUSEKEEPING_BATCH_SIZE
        );
      } catch (Exception caughtException) {
        AIPlatformLogManager.logException(
          caughtException,
          'AIMaintenanceScheduler',
          'execute'
        );
      }
    }

    AIPiiRegistrySyncDispatcher.dispatchDueRegistries();
  }
}
