/*
Class Name: AIAssistSettingsServiceTest

=================================================================
=================================================================

Description: Testing utility for AIAssistSettingsService: the one reader of the application settings, and what it does with a missing, zero or garbled value.

=================================================================
=================================================================
Applicable Classes:

AIAssistSettingsService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAssistSettingsServiceTest {

    // testScenario1: The TestSetup enables the application and there is no UI settings row -> the application is on and the UI settings are the field defaults.
    // testScenario2: The switch is unchecked and a UI settings row is added -> the application is off and the row replaces the field defaults.
    // testScenario3: There is no organisation settings row at all -> the field defaults apply instead of every checkbox reading as off.
    // testScenario4: A settings row exists and is changed after the first read -> getSettings returns the cached value until the cache is reset.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Read the enabled switch and the UI settings
        Test.startTest();
            Boolean isEnabled = AIAssistSettingsService.isEnabled();
            AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
        Test.stopTest();

        // [2] Check the application is on and the UI settings are the defaults
        Assert.isTrue(isEnabled, 'The application is on when the row enables it.');
        Assert.isTrue(uiSettings.IsUserInitiatedChatEnabled__c, 'With no UI row the default-on switches stay on.');
        Assert.isFalse(uiSettings.IsMaintenanceMode__c, 'With no UI row maintenance mode is off.');
    }

    @IsTest static void testScenario2() {

        // [1] Switch the application off and clear the settings cache
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = false;
        update settings;
        AIAssistSettingsService.cachedSettings = null;

        // [2] Add an organisation UI settings row
        AIAssistUISettings__c uiRow = AIAssistUISettings__c.getOrgDefaults();
        uiRow.IsMaintenanceMode__c = true;
        uiRow.IsUserInitiatedChatEnabled__c = false;
        upsert uiRow;

        // [3] Read the enabled switch and the UI settings
        Test.startTest();
            Boolean isEnabled = AIAssistSettingsService.isEnabled();
            AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
        Test.stopTest();

        // [4] Check the application is off and the UI row is used
        Assert.isFalse(isEnabled, 'Unchecking IsEnabled__c switches the application off.');
        Assert.isTrue(uiSettings.IsMaintenanceMode__c, 'The organisation UI row is read once it exists.');
        Assert.isFalse(uiSettings.IsUserInitiatedChatEnabled__c, 'And its switches replace the defaults.');
    }

    @IsTest static void testScenario3() {

        // [1] Delete the settings row and clear the settings cache
        delete [SELECT Id FROM AIAssistSettings__c];
        AIAssistSettingsService.cachedSettings = null;

        // [2] Read the settings and the enabled switch
        Test.startTest();
            AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
            Boolean isEnabled = AIAssistSettingsService.isEnabled();
        Test.stopTest();

        // [3] Check the field defaults apply
        Assert.isNull(settings.Id, 'No row exists, so the settings are the in-memory defaults.');
        Assert.isTrue(isEnabled, 'The IsEnabled__c field default is on, so a missing row must not switch the application off.');
    }

    @IsTest static void testScenario4() {

        // [1] Set the lock minutes on the settings row and clear the settings cache
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.ProcessingLockMinutes__c = 15;
        update settings;
        AIAssistSettingsService.cachedSettings = null;

        // [2] Read, change the row, read again, clear the cache and read a third time
        Test.startTest();
            AIAssistSettings__c first = AIAssistSettingsService.getSettings();
            settings.ProcessingLockMinutes__c = 30;
            update settings;
            AIAssistSettings__c cached = AIAssistSettingsService.getSettings();
            AIAssistSettingsService.cachedSettings = null;
            AIAssistSettings__c refreshed = AIAssistSettingsService.getSettings();
        Test.stopTest();

        // [3] Check the cached and refreshed values
        Assert.isNotNull(first.Id, 'The organisation row is returned.');
        Assert.areEqual(15, first.ProcessingLockMinutes__c.intValue(), 'The configured value is read from the row.');

        Assert.areEqual(15, cached.ProcessingLockMinutes__c.intValue(), 'The settings are cached for the transaction.');
        Assert.areEqual(30, refreshed.ProcessingLockMinutes__c.intValue(), 'Resetting the cache reads the change.');
    }
}
