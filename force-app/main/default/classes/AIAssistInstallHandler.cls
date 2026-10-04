/*
Class Name: AIAssistInstallHandler

=================================================================
=================================================================

Description: Post-install script. Custom setting rows are data, not metadata, so installing
the package does not create them. Without a row the object's own default values are not applied
(getOrgDefaults() returns every checkbox as false), and the application would start switched off
with its limits blank.

On a first install this creates the organisation-level AIAssistSettings__c and
AIAssistUISettings__c rows from the fields' default values. When a row already exists it is left as
it is: the subscriber's configuration is never overwritten. In production the application starts
switched on and recorded against the org (ActivatedOrgId__c). In a sandbox or scratch org it starts
switched off, so nothing calls an AI provider there until an administrator activates it.

An upgrade creates nothing. It runs the numbered upgrade steps that shipped after the version being
upgraded from (previousVersion), in order, each once. A step that fails is logged and the others run.

A first install also schedules the daily housekeeping job (AIMaintenanceScheduler.scheduleDaily).
An upgrade does not, so a job the administrator deleted or moved stays as they left it.

Nothing subscriber-specific is created. Named Credentials, API keys, agents and model
configurations are the subscriber's to set up.

It is public, not global: the platform calls a post-install script by name, and a global class
would become part of the package's permanent API for no benefit.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Schedules the daily housekeeping job on a first install.
3.0          Chandler Stuart          Off on a sandbox install; numbered upgrade steps keyed on the previous version.
*/

public with sharing class AIAssistInstallHandler implements InstallHandler {
  // Upgrade steps by number, with the version each first shipped in. A step runs when the version being upgraded from is older than that, so each runs once, and they run in number order. Add a step with the next number; never renumber or remove one.
  private static final Map<Integer, Version> UPGRADE_STEP_VERSIONS = new Map<Integer, Version>{
    1 => new Version(0, 2), // Record the org the application is switched on in (the sandbox guard).
    2 => new Version(0, 2) // Count the organisation's usage totals, which the limit check now reads.
  };

  // A test cannot change what kind of org it runs in.
  @TestVisible
  private static Boolean isSandboxOverride;
  // The steps run by this transaction's install, in the order they ran.
  @TestVisible
  private static List<Integer> upgradeStepsRun = new List<Integer>();

  public void onInstall(InstallContext context) {
    try {
      if (context != null && context.previousVersion() != null) {
        runUpgradeSteps(context.previousVersion()); // An upgrade - the subscriber's settings stay as they are.
        return;
      }

      if (AIAssistSettings__c.getOrgDefaults().Id == null) {
        AIAssistSettings__c settings = (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(
          null,
          true
        );
        settings.SetupOwnerId = UserInfo.getOrganizationId();

        // A sandbox (or scratch org) starts switched off: nothing calls an AI provider until an administrator activates it there. Production starts on, recorded against this org.
        Boolean isSandbox = isSandboxOverride != null
          ? isSandboxOverride
          : [SELECT IsSandbox FROM Organization WITH SYSTEM_MODE LIMIT 1]
            .IsSandbox;
        settings.IsEnabled__c = !isSandbox;
        settings.ActivatedOrgId__c = isSandbox
          ? null
          : UserInfo.getOrganizationId();
        insert settings;
      }

      if (AIAssistUISettings__c.getOrgDefaults().Id == null) {
        AIAssistUISettings__c uiSettings = (AIAssistUISettings__c) AIAssistUISettings__c.SObjectType.newSObject(
          null,
          true
        );
        uiSettings.SetupOwnerId = UserInfo.getOrganizationId();
        insert uiSettings;
      }

      // On its own, so a job that cannot be scheduled (the subscriber is at their scheduled job limit) leaves the settings in place.
      try {
        AIMaintenanceScheduler.scheduleDaily();
      } catch (Exception scheduleException) {
        AIPlatformLogManager.logException(
          scheduleException,
          'AIAssistInstallHandler',
          'onInstall'
        );
      }
    } catch (Exception caughtException) {
      // An install must not fail because a settings row could not be created; an admin can still create it, and the application reads field defaults until then.
      AIPlatformLogManager.logException(
        caughtException,
        'AIAssistInstallHandler',
        'onInstall'
      );
    }
  }

  // Runs, in number order, every step that shipped after the version being upgraded from. Each step is on its own: one that fails is logged and the rest still run.
  private static void runUpgradeSteps(Version previousVersion) {
    List<Integer> stepNumbers = new List<Integer>(
      UPGRADE_STEP_VERSIONS.keySet()
    );
    stepNumbers.sort();

    for (Integer stepNumber : stepNumbers) {
      if (previousVersion.compareTo(UPGRADE_STEP_VERSIONS.get(stepNumber)) >= 0)
        continue;

      try {
        if (stepNumber == 1)
          AIAssistSettingsService.recordActivatedOrg();
        else if (stepNumber == 2)
          Database.executeBatch(
            new AIOrgUsageTotalsBatch(),
            AIAssistApplicationConstants.HOUSEKEEPING_BATCH_SIZE
          );

        upgradeStepsRun.add(stepNumber);
      } catch (Exception stepException) {
        AIPlatformLogManager.logCustomMessage(
          'Upgrade step ' + stepNumber + ' failed.',
          stepException.getMessage(),
          'AIAssistInstallHandler',
          'runUpgradeSteps',
          null,
          AIAssistApplicationConstants.LOG_SEVERITY_ERROR
        );
      }
    }
  }
}
