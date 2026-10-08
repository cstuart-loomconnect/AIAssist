/*
Class Name: AIAssistSettingsServiceTest

=================================================================
=================================================================

Description: Testing utility for AIAssistSettingsService: the one reader of the application settings, and what it does with a missing, zero or garbled value.

=================================================================
=================================================================
Applicable Classes:

AIAssistSettingsService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAssistSettingsServiceTest {
  // testScenario1: With the settings the TestSetup enabled and no UI settings row, the application is on and the UI settings are the field defaults.
  // testScenario2: Unchecking the switch turns the application off, and a UI settings row replaces the field defaults.
  // testScenario3: With no organisation settings row at all, the field defaults apply instead of every checkbox reading as off.
  // testScenario4: With a settings row, getSettings returns it and caches it for the transaction until clearCache is called.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    Test.startTest();
    Boolean isEnabled = AIAssistSettingsService.isEnabled();
    AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
    Test.stopTest();

    Assert.isTrue(isEnabled, 'The application is on when the row enables it.');
    Assert.isTrue(
      uiSettings.IsUserInitiatedChatEnabled__c,
      'With no UI row the default-on switches stay on.'
    );
    Assert.isFalse(
      uiSettings.IsMaintenanceMode__c,
      'With no UI row maintenance mode is off.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.clearCache();

    AIAssistUISettings__c uiRow = AIAssistUISettings__c.getOrgDefaults();
    uiRow.IsMaintenanceMode__c = true;
    uiRow.IsUserInitiatedChatEnabled__c = false;
    upsert uiRow;

    Test.startTest();
    Boolean isEnabled = AIAssistSettingsService.isEnabled();
    AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
    Test.stopTest();

    Assert.isFalse(
      isEnabled,
      'Unchecking IsEnabled__c switches the application off.'
    );
    Assert.isTrue(
      uiSettings.IsMaintenanceMode__c,
      'The organisation UI row is read once it exists.'
    );
    Assert.isFalse(
      uiSettings.IsUserInitiatedChatEnabled__c,
      'And its switches replace the defaults.'
    );
  }

  @IsTest
  static void testScenario3() {
    delete [SELECT Id FROM AIAssistSettings__c];
    AIAssistSettingsService.clearCache();

    Test.startTest();
    AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
    Boolean isEnabled = AIAssistSettingsService.isEnabled();
    Test.stopTest();

    Assert.isNull(
      settings.Id,
      'No row exists, so the settings are the in-memory defaults.'
    );
    Assert.isTrue(
      isEnabled,
      'The IsEnabled__c field default is on, so a missing row must not switch the application off.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.ProcessingLockMinutes__c = 15;
    update settings;
    AIAssistSettingsService.clearCache();

    Test.startTest();
    AIAssistSettings__c first = AIAssistSettingsService.getSettings();
    settings.ProcessingLockMinutes__c = 30;
    update settings;
    AIAssistSettings__c cached = AIAssistSettingsService.getSettings();
    AIAssistSettingsService.clearCache();
    AIAssistSettings__c refreshed = AIAssistSettingsService.getSettings();
    Test.stopTest();

    Assert.isNotNull(first.Id, 'The organisation row is returned.');
    Assert.areEqual(
      15,
      first.ProcessingLockMinutes__c.intValue(),
      'The configured value is read from the row.'
    );
    Assert.areEqual(
      15,
      cached.ProcessingLockMinutes__c.intValue(),
      'The settings are cached for the transaction.'
    );
    Assert.areEqual(
      30,
      refreshed.ProcessingLockMinutes__c.intValue(),
      'Clearing the cache reads the change.'
    );
  }
}
