/*
Class Name: AIAssistSettingsService

=================================================================
=================================================================

Description: The one reader of AIAssistSettings__c and AIAssistUISettings__c. A caller asks for the
settings record once and reads the fields it needs; the field defaults supply a value for a setting
that has never been changed.

A custom setting row is data, not metadata. With no organisation row yet, getOrgDefaults()
returns every checkbox as false, which would read every "Is ... Enabled" switch as off. So when
there is no row the field defaults are loaded instead (the post-install script creates the
row, but a scratch org or a deleted row must still work).


=================================================================
=================================================================

Version      Author                   Description
TBC          TBC                      TBC
*/

public inherited sharing class AIAssistSettingsService {
  public class AIAssistSettingsServiceException extends Exception {
  }

  @TestVisible
  private static AIAssistSettings__c cachedSettings; // Tests clear it to read a setting changed earlier in the same transaction.

  // Forgets the cached settings so the next read sees a change made in this transaction.
  public static void clearCache() {
    cachedSettings = null;
  }

  // The organisation settings, cached for the transaction.
  public static AIAssistSettings__c getSettings() {
    if (cachedSettings == null) {
      AIAssistSettings__c organisationDefaults = AIAssistSettings__c.getOrgDefaults();
      cachedSettings = organisationDefaults != null &&
        organisationDefaults.Id != null
        ? organisationDefaults
        : (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(
            null,
            true
          );
    }

    return cachedSettings;
  }

  // The running user's AIAssistUISettings__c (user, then profile, then organisation level), uncached so the chat window sees a change made earlier in the transaction. With no row at any level the field defaults apply, otherwise the default-on switches would all read as off.
  public static AIAssistUISettings__c getUiSettings() {
    AIAssistUISettings__c mergedSettings = AIAssistUISettings__c.getInstance();
    if (mergedSettings != null && mergedSettings.Id != null)
      return mergedSettings;

    Set<Id> hierarchyOwnerIds = new Set<Id>{
      UserInfo.getUserId(),
      UserInfo.getProfileId(),
      UserInfo.getOrganizationId()
    };
    Boolean hasAnyRow =
      [
        SELECT COUNT()
        FROM AIAssistUISettings__c
        WHERE SetupOwnerId IN :hierarchyOwnerIds
        WITH SYSTEM_MODE
      ] > 0;

    return hasAnyRow
      ? mergedSettings
      : (AIAssistUISettings__c) AIAssistUISettings__c.SObjectType.newSObject(
          null,
          true
        );
  }

  // The application switch every trigger and entry point respects. Blank counts as on. Off as well when the settings were activated in another org (isActivatedElsewhere): a sandbox copied from production stays off until it is activated there.
  public static Boolean isEnabled() {
    return getSettings().IsEnabled__c != false && !isActivatedElsewhere();
  }

  // True when ActivatedOrgId__c names an org other than this one. Blank is not "elsewhere": it has not been recorded yet.
  public static Boolean isActivatedElsewhere() {
    String activatedOrgId = getSettings().ActivatedOrgId__c;

    return String.isNotBlank(activatedOrgId) &&
      !UserInfo.getOrganizationId().startsWith(activatedOrgId.left(15));
  }

  // Switches the application on in this org and records the org, which is what makes a copy of the settings in another org inactive. Creates the settings row when there is none.
  public static void activate() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    if (settings == null || settings.Id == null) {
      settings = (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(
        null,
        true
      );
      settings.SetupOwnerId = UserInfo.getOrganizationId();
    }
    settings.IsEnabled__c = true;
    settings.ActivatedOrgId__c = UserInfo.getOrganizationId();
    Database.upsert(settings, true, AccessLevel.SYSTEM_MODE);
    clearCache();
  }

  // Records this org on settings that are switched on and have no org recorded yet (switched on in Setup, or from before the field existed). Called where DML is safe: the maintenance job and after a turn. A failure is logged, never thrown.
  public static void recordActivatedOrg() {
    try {
      AIAssistSettings__c settings = getSettings();
      if (
        settings.Id == null ||
        settings.IsEnabled__c == false ||
        String.isNotBlank(settings.ActivatedOrgId__c)
      )
        return;

      Database.update(
        new AIAssistSettings__c(
          Id = settings.Id,
          ActivatedOrgId__c = UserInfo.getOrganizationId()
        ),
        true,
        AccessLevel.SYSTEM_MODE
      );
      clearCache();
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAssistSettingsService',
        'recordActivatedOrg'
      );
    }
  }
}
