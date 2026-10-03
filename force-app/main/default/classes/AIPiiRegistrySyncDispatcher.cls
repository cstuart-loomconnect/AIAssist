/*
Class Name: AIPiiRegistrySyncDispatcher

=================================================================
=================================================================

Description: Finds the PII registry objects that are due a sync (never synced, failed last time, or past their
Cache Reset Date), marks them Queued and hands them to AIPiiRegistrySyncWorker in a single job.

Bounded for the subscriber's org: at most AIAssistSettings__c.MaxPIIRegistryObjects__c registries a
run, never more than the worker can finish in one transaction, and one queueable however many
registries there are. Not called while the application is switched off, and not called at all unless
an administrator schedules AIMaintenanceScheduler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old dispatcher. One job for all registries instead of a future call each.
*/

public inherited sharing class AIPiiRegistrySyncDispatcher {
  // Returns how many registries were handed to the worker.
  public static Integer dispatchDueRegistries() {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return 0;

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

      if (dueRegistries.isEmpty())
        return 0;

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
      System.enqueueJob(new AIPiiRegistrySyncWorker(registryIds));

      return registryIds.size();
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIPiiRegistrySyncDispatcher',
        'dispatchDueRegistries'
      );
      return 0;
    }
  }
}
