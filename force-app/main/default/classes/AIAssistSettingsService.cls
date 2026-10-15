/*
Class Name: AIAssistSettingsService

=================================================================
=================================================================

Description: The one reader of AIAssistSettings__c and AIAssistUISettings__c.

Step 1: Read the settings row that applies (organisation, or user/profile/organisation for the UI settings)
Step 2: If no row exists, load the field defaults so the default-on switches do not all read as off
Step 3: Return the settings to the caller

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAssistSettingsService {

    public class AIAssistSettingsServiceException extends Exception {}

    @TestVisible
    private static AIAssistSettings__c cachedSettings; // Tests clear it to read a setting changed earlier in the same transaction.

    @TestVisible
    private static Id cachedSettingsUserId; // The user the cached settings were built for, because five of the numbers can differ by profile or user.

    // The settings for the running user, cached for the transaction: the organisation row, with the five limits a profile or user row may override taken from the row that applies to the user.
    public static AIAssistSettings__c getSettings() {

        // [1] Rebuild when nothing is cached, or the cache was built for another user
        if (cachedSettings == null || cachedSettingsUserId != UserInfo.getUserId()) {

            // [2] Read the organisation row, or load the field defaults so the switches do not all read as off
            AIAssistSettings__c organisationDefaults = AIAssistSettings__c.getOrgDefaults();
            AIAssistSettings__c builtSettings = organisationDefaults != null && organisationDefaults.Id != null ? organisationDefaults.clone(true, true, true, true) : (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(null, true);

            // [3] Take the overridable limits from the profile or user row when the user has one
            applyOverridableLimits(builtSettings, organisationDefaults);

            // [4] Give a cleared required number its default, so a blank cannot stop a reply
            applyRequiredDefaults(builtSettings);

            cachedSettings = builtSettings;
            cachedSettingsUserId = UserInfo.getUserId();
        }

        // [5] Return the cached settings
        return cachedSettings;
    }

    // Drops the cached settings so the next read sees a change made earlier in the same transaction.
    public static void clearCache() {

        // [1] Forget the cached settings
        cachedSettings = null;
        cachedSettingsUserId = null;
    }

    // The running user's AIAssistUISettings__c (user, then profile, then organisation level), uncached so the chat window sees a change made earlier in the transaction. With no row at any level the field defaults apply, otherwise the default-on switches would all read as off.
    public static AIAssistUISettings__c getUiSettings() {

        // [1] Read the settings that apply to the running user
        AIAssistUISettings__c mergedSettings = AIAssistUISettings__c.getInstance();

        // [2] A row exists at some level, so use it
        if (mergedSettings != null && mergedSettings.Id != null) return mergedSettings;

        // [3] Check whether any row exists for this user, profile or organisation
        Set<Id> hierarchyOwnerIds = new Set<Id>{UserInfo.getUserId(), UserInfo.getProfileId(), UserInfo.getOrganizationId()};

        Boolean hasAnyRow = [SELECT COUNT() FROM AIAssistUISettings__c WHERE SetupOwnerId IN :hierarchyOwnerIds WITH SYSTEM_MODE] > 0;

        // [4] Return the merged settings, or the field defaults when there is no row at all
        return hasAnyRow ? mergedSettings : (AIAssistUISettings__c) AIAssistUISettings__c.SObjectType.newSObject(null, true);
    }

    // The application switch every trigger and entry point respects. Blank counts as on.
    public static Boolean isEnabled() {

        // [1] Treat a blank switch as on
        return getSettings().IsEnabled__c != false;
    }

    // Copies the five limits a profile or user may override from the row that applies to the running user, when that row is not the organisation row.
    private static void applyOverridableLimits(AIAssistSettings__c targetSettings, AIAssistSettings__c organisationDefaults) {

        // [1] Read the row that applies to the running user (user, then profile, then organisation)
        AIAssistSettings__c userRow = AIAssistSettings__c.getInstance();

        // [2] Nothing to copy when there is no row, or it is the organisation row
        if (userRow == null || userRow.Id == null) return;
        if (organisationDefaults != null && userRow.Id == organisationDefaults.Id) return;

        // [3] Copy the five limits
        targetSettings.MaxMessageLength__c = userRow.MaxMessageLength__c;
        targetSettings.MaxMessagesPerUserPerMinute__c = userRow.MaxMessagesPerUserPerMinute__c;
        targetSettings.DefaultMaxToolCallingIterations__c = userRow.DefaultMaxToolCallingIterations__c;
        targetSettings.MaxToolCallingIterationsCap__c = userRow.MaxToolCallingIterationsCap__c;
        targetSettings.MaxToolCallsPerIteration__c = userRow.MaxToolCallsPerIteration__c;
    }

    // Gives each required number its default when it is blank, which Setup allows once a row exists.
    private static void applyRequiredDefaults(AIAssistSettings__c targetSettings) {

        // [1] Fill each blank required number
        if (targetSettings.ProcessingLockSeconds__c == null) targetSettings.ProcessingLockSeconds__c = AIAssistApplicationConstants.SETTINGS_DEFAULT_PROCESSING_LOCK_SECONDS;
        if (targetSettings.CalloutTimeoutMilliseconds__c == null) targetSettings.CalloutTimeoutMilliseconds__c = AIAssistApplicationConstants.SETTINGS_DEFAULT_CALLOUT_TIMEOUT_MILLISECONDS;
        if (targetSettings.RetryAttempts__c == null) targetSettings.RetryAttempts__c = AIAssistApplicationConstants.SETTINGS_DEFAULT_RETRY_ATTEMPTS;
        if (targetSettings.DefaultMaxToolCallingIterations__c == null) targetSettings.DefaultMaxToolCallingIterations__c = AIAssistApplicationConstants.SETTINGS_DEFAULT_MAX_TOOL_CALLING_ITERATIONS;
        if (targetSettings.MaxToolCallingIterationsCap__c == null) targetSettings.MaxToolCallingIterationsCap__c = AIAssistApplicationConstants.SETTINGS_DEFAULT_TOOL_CALLING_ITERATIONS_CAP;
        if (targetSettings.MaxToolCallsPerIteration__c == null) targetSettings.MaxToolCallsPerIteration__c = AIAssistApplicationConstants.SETTINGS_DEFAULT_MAX_TOOL_CALLS_PER_ITERATION;
    }
}
