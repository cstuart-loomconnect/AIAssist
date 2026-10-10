/*
Class Name: AIPiiRegistrySyncDispatcher

=================================================================
=================================================================

Description: Finds the PII registry objects that are due a sync and hands them to AIPiiRegistrySyncWorker in a single job.

Step 1: Do nothing while the application is switched off
Step 2: Work out how many registries to take, capped by AIAssistSettings__c.MaxPIIRegistryObjects__c and the per-run maximum
Step 3: Find the registries due a sync: never synced, failed last time, or past their Cache Reset Date
Step 4: Mark them Queued and enqueue one AIPiiRegistrySyncWorker for all of them

Bounded for the subscriber's org: never more than the worker can finish in one transaction, and
one queueable however many registries there are. Not called at all unless an administrator
schedules AIMaintenanceScheduler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiRegistrySyncDispatcher {
  // Returns how many registries were handed to the worker.
  public static Integer dispatchDueRegistries() {
    try {
      // [1] Do nothing while the application is switched off
      if (!AIAssistSettingsService.isEnabled())
        return 0;

      // [2] Work out how many registries to take this run
      Decimal configuredMaxRegistries = AIAssistSettingsService.getSettings()
        .MaxPIIRegistryObjects__c;
      Integer maxRegistries = Math.min(
        configuredMaxRegistries == null
          ? AIAssistApplicationConstants.MAX_PII_REGISTRIES_PER_RUN
          : Integer.valueOf(configuredMaxRegistries),
        AIAssistApplicationConstants.MAX_PII_REGISTRIES_PER_RUN
      );
      if (maxRegistries < 1)
        return 0;

      // [3] Find the registries that are due and not already queued or running, oldest first
      Date today = Datetime.now().dateGmt();

      List<AIPIIRegistry__c> dueRegistries = [
        SELECT Id
        FROM AIPIIRegistry__c
        WHERE
          IsActive__c = TRUE
          AND (LastSynced__c = NULL
          OR SyncStatus__c = :AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED
          OR (CacheResetDate__c != NULL
          AND CacheResetDate__c <= :today))
          AND SyncStatus__c != :AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED
          AND SyncStatus__c != :AIAssistApplicationConstants.PII_SYNC_STATUS_IN_PROGRESS
        WITH SYSTEM_MODE
        ORDER BY LastSynced__c ASC NULLS FIRST
        LIMIT :maxRegistries
      ];

      // [4] Nothing is due
      if (dueRegistries.isEmpty())
        return 0;

      // [5] Mark each registry Queued
      List<Id> registryIds = new List<Id>();

      for (AIPIIRegistry__c registry : dueRegistries) {
        registry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED;
        registryIds.add(registry.Id);
      }

      AIMessagingDataService.updateAndLogFailures(
        dueRegistries,
        'AIPiiRegistrySyncDispatcher',
        'dispatchDueRegistries'
      );

      // [6] Hand every registry to one worker job
      System.enqueueJob(new AIPiiRegistrySyncWorker(registryIds));

      return registryIds.size();
    } catch (Exception ex) {
      AIPlatformLogManager.logException(
        ex,
        'AIPiiRegistrySyncDispatcher',
        'dispatchDueRegistries'
      );
      return 0;
    }
  }
}
