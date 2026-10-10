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

    // The organisation settings, cached for the transaction.
    public static AIAssistSettings__c getSettings() {

        if (cachedSettings == null) {

            // [1] Read the organisation row
            AIAssistSettings__c organisationDefaults = AIAssistSettings__c.getOrgDefaults();

            // [2] Use the row if it exists, otherwise load the field defaults so the switches do not all read as off
            cachedSettings = organisationDefaults != null && organisationDefaults.Id != null ? organisationDefaults : (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(null, true);
        }

        // [3] Return the cached settings
        return cachedSettings;
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
}
