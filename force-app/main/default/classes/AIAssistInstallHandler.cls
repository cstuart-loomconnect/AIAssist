/*
Class Name: AIAssistInstallHandler

=================================================================
=================================================================

Description: Post-install script. Custom setting rows are data, not metadata, so installing
the package does not create them. Without a row the object's own default values are not applied
(getOrgDefaults() returns every checkbox as false), and the application would start switched off
with its limits blank.

On a first install this creates the organisation-level AIAssistSettings__c and
AIAssistUISettings__c rows from the fields' default values. On an upgrade, or when a row already
exists, it does nothing: it never overwrites what the subscriber has configured.

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
*/

public with sharing class AIAssistInstallHandler implements InstallHandler {
  public void onInstall(InstallContext context) {
    try {
      if (context != null && context.previousVersion() != null)
        return; // An upgrade - the subscriber's settings stay as they are.

      if (AIAssistSettings__c.getOrgDefaults().Id == null) {
        AIAssistSettings__c settings = (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(
          null,
          true
        );
        settings.SetupOwnerId = UserInfo.getOrganizationId();
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
}
