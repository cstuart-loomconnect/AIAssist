/*
Class Name: AIMaintenanceScheduler

=================================================================
=================================================================

Description: The package's one scheduled job, which runs the daily housekeeping.

Step 1: Fail messages left waiting at the cap on messages in flight
Step 2: Start the retention batch, which runs whether or not the application is on
Step 3: Start the idle conversation batch, only while the application is on
Step 4: Dispatch the PII registry syncs that are due, only while the application is on

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIMaintenanceScheduler implements Schedulable {

    public class AIMaintenanceSchedulerException extends Exception {}

    public static final String JOB_NAME = 'AI Assist Maintenance';
    private static final String DAILY_AT_2AM = '0 0 2 * * ?'; // In the time zone of the user the job runs as.

    @TestVisible
    private static Boolean isTestCustomExceptionThrown = false;

    // Schedules the daily run unless a job of this name already exists. Returns the job's Id, or null when it was already scheduled.
    public static Id scheduleDaily() {

        // [1] Throw on purpose when a test asks for it
        if (isTestCustomExceptionThrown) throw new AIMaintenanceSchedulerException('Test exception for AIMaintenanceScheduler.scheduleDaily');

        // [2] Do nothing when the job is already scheduled
        if ([SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME WITH SYSTEM_MODE] > 0) return null;

        // [3] Schedule the daily run and return the job's Id
        return System.schedule(JOB_NAME, DAILY_AT_2AM, new AIMaintenanceScheduler());
    }

    // Runs the housekeeping. A task that cannot start is logged, so one failure does not stop the others.
    public void execute(SchedulableContext context) {

        // [1] Check whether the application is switched on
        Boolean isEnabled = AIAssistSettingsService.isEnabled();

        // [2] Fail messages held at the cap that no finalizer or chat window has failed since (never throws)
        AIConversationMessageService.failExpiredHeldMessages(false);

        // [3] Always run retention, so switching AI Assist off never stops the data it already holds from expiring
        List<Database.Batchable<SObject>> housekeepingBatches = new List<Database.Batchable<SObject>>{ new AIConversationRetentionBatch() };

        // [4] Closing idle conversations is part of the chat, so it waits for the application to be on
        if (isEnabled) housekeepingBatches.add(new AIConversationIdleBatch());

        // [5] Start each batch on its own
        for (Database.Batchable<SObject> housekeepingBatch : housekeepingBatches) {

            try {

                // [6] Throw on purpose when a test asks for it
                if (isTestCustomExceptionThrown) throw new AIMaintenanceSchedulerException('Test exception for AIMaintenanceScheduler.execute');

                // [7] Start the batch
                Database.executeBatch(housekeepingBatch, AIAssistApplicationConstants.HOUSEKEEPING_BATCH_SIZE);

            } catch (Exception ex) {
                AIPlatformLogManager.logException(ex, 'AIMaintenanceScheduler', 'execute');
            }
        }

        // [8] Sync the PII registries that are due, only while the application is on
        if (isEnabled) AIPiiRegistrySyncDispatcher.dispatchDueRegistries();
    }
}
